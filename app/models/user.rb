class User < ApplicationRecord
  ROLES = %w[declarant analyst admin].freeze
  MINIMUM_ADMINS = 2

  class PasskeyResetNotAllowed < StandardError; end
  class EnrollmentNotAllowed < StandardError; end

  before_destroy :keep_enough_admins_on_destroy, if: :admin?, prepend: true

  has_many :sessions, dependent: :destroy
  has_many :passkeys, dependent: :delete_all
  has_many :recovery_codes, dependent: :delete_all

  enum :role, ROLES.index_with(&:itself), default: "declarant", validate: true

  scope :staff, -> { where(role: %w[analyst admin]) }

  encrypts :email, deterministic: true, downcase: true
  normalizes :email, with: ->(email) { email.strip }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validate :keeps_enough_admins, if: -> { will_save_change_to_role?(from: "admin") }

  generates_token_for :magic_link, expires_in: 15.minutes do
    login_token_version
  end

  # Unknown emails get a declarant account so the answer never reveals who is registered.
  def self.send_magic_link(email)
    create_or_find_by(email: email).tap do |user|
      MagicLinkMailer.with(user: user).sign_in.deliver_later if user.persisted?
    end
  end

  def self.sign_in_with_magic_link(token)
    user = find_by_token_for(:magic_link, token)
    user if user&.consume_magic_link!
  end

  def magic_link_token
    generate_token_for(:magic_link)
  end

  # Compare-and-swap on the version, so two concurrent clicks cannot both sign in.
  def consume_magic_link!
    consumed = User.where(id: id, login_token_version: login_token_version)
      .update_all("login_token_version = login_token_version + 1") == 1
    reload if consumed
    consumed
  end

  def sign_out_everywhere!
    transaction do
      sessions.destroy_all
      increment!(:login_token_version)
    end
  end

  # Returns the codes in clear: this is the only time they exist outside the user's hands.
  def generate_recovery_codes!
    RecoveryCode.generate.tap do |codes|
      transaction do
        recovery_codes.delete_all
        codes.each { |code| recovery_codes.create!(code: code) }
      end
    end
  end

  # A single DELETE both checks and burns the code, so it cannot be used twice concurrently.
  def use_recovery_code!(code)
    return false if RecoveryCode.normalize(code).empty?

    recovery_codes.where(digest: RecoveryCode.digest(code)).delete_all == 1
  end

  # Signing out everywhere too: whoever held the lost passkey may hold a verified session.
  # Returns the new enrollment code in clear, for the admin to hand over.
  def reset_passkeys!(by:)
    raise PasskeyResetNotAllowed unless by.admin? && by != self && staff?

    transaction do
      passkeys.delete_all
      recovery_codes.delete_all
      sign_out_everywhere!
      AuditEvent.record!(actor: by, action: "passkeys.reset", subject: self)
      issue_enrollment_code!(by: by)
    end
  end

  # The magic link alone must not be enough to enrol a first passkey: an admin hands over this code.
  # Returns it in clear, once. From the console, the first admin issues their own with `by: self`.
  def issue_enrollment_code!(by:)
    raise EnrollmentNotAllowed unless by.admin? && staff?

    RecoveryCode.generate_one.tap do |code|
      transaction do
        update!(enrollment_code_digest: RecoveryCode.digest(code, purpose: :enrollment_code))
        AuditEvent.record!(actor: by, action: "enrollment_code.issued", subject: self)
      end
    end
  end

  # Compare-and-swap on the digest: one statement checks and burns the code.
  def consume_enrollment_code!(code)
    return false if RecoveryCode.normalize(code).empty?

    consumed = User.where(id: id, enrollment_code_digest: RecoveryCode.digest(code, purpose: :enrollment_code))
      .update_all(enrollment_code_digest: nil) == 1
    self.enrollment_code_digest = nil if consumed
    consumed
  end

  def staff?
    analyst? || admin?
  end

  def member?
    membership_expires_on.present? && membership_expires_on >= Date.current
  end

  private
    def keeps_enough_admins
      errors.add(:role, :too_few_admins, count: MINIMUM_ADMINS) if other_admins_count < MINIMUM_ADMINS
    end

    def keep_enough_admins_on_destroy
      return if other_admins_count >= MINIMUM_ADMINS

      errors.add(:base, :too_few_admins, count: MINIMUM_ADMINS)
      throw :abort
    end

    # Locking every admin row, self included, in id order: concurrent demotions queue up instead of
    # both passing or deadlocking.
    def other_admins_count
      (User.where(role: "admin").order(:id).lock.pluck(:id) - [ id ]).size
    end
end
