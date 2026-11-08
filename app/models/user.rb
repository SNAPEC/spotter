class User < ApplicationRecord
  ROLES = %w[declarant analyst admin].freeze
  MINIMUM_ADMINS = 2
  ENROLLMENT_CODE_VALIDITY = 7.days
  # Declarant accounts nobody uses are purged: never signed in, 30 days after creation; otherwise
  # 12 months after the last session expired. Both rounded up to the end of a month.
  UNUSED_ACCOUNT_DELAY = 30.days
  DORMANT_ACCOUNT_DELAY = 12.months

  class PasskeyResetNotAllowed < StandardError; end
  class EnrollmentNotAllowed < StandardError; end
  class DeactivationNotAllowed < StandardError; end
  class TooFewAdmins < DeactivationNotAllowed; end

  before_destroy :keep_enough_admins_on_destroy, if: -> { admin? && active? }, prepend: true

  has_many :sessions, dependent: :destroy
  has_many :passkeys, dependent: :delete_all
  has_many :recovery_codes, dependent: :delete_all

  enum :role, ROLES.index_with(&:itself), default: "declarant", validate: true

  scope :staff, -> { where(role: %w[analyst admin]) }
  scope :active, -> { where(deactivated_at: nil) }
  scope :purge_due, -> { declarant.where(purge_on: ...Date.current) }

  attribute :purge_on, :date, default: -> { (Date.current + UNUSED_ACCOUNT_DELAY).end_of_month }

  encrypts :email, deterministic: true, downcase: true
  normalizes :email, with: ->(email) { email.strip }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validate :keeps_enough_admins, if: -> { will_save_change_to_role?(from: "admin") && active? }

  generates_token_for :magic_link, expires_in: 15.minutes do
    login_token_version
  end

  # Unknown emails get a declarant account so the answer never reveals who is registered. A deactivated
  # account gets the same answer and the same work; the mailer sends nothing for it.
  def self.send_magic_link(email)
    create_or_find_by(email: email).tap do |user|
      MagicLinkMailer.with(user: user).sign_in.deliver_later if user.persisted?
    end
  end

  # A rate-limit key per address that never stores the address, normalised as the email column is.
  def self.email_fingerprint(email)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.key_generator.generate_key("email_fingerprint", 32),
      email.to_s.strip.downcase)
  end

  def self.purge_unused
    purge_due.find_each do |user|
      user.purge_if_unused!
    rescue ActiveRecord::RecordNotFound
      next
    end
  end

  def self.sign_in_with_magic_link(token)
    user = find_by_token_for(:magic_link, token)
    user if user&.active? && user.consume_magic_link!
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

  # Lock order: the user, then the new session. A purge holding the lock first wins, and the sign-in
  # finds no account instead of failing on the foreign key.
  def start_session!
    transaction do
      lock!
      sessions.create!
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  # Lock order, on every path: admin rows (id order), then the user, then its sessions. Taking the
  # user first here keeps a concurrent passkey enrolment, which does the same, from deadlocking.
  def sign_out_everywhere!
    transaction do
      lock!
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
    return false if deactivated? || RecoveryCode.normalize(code).empty?

    recovery_codes.where(digest: RecoveryCode.digest(code)).delete_all == 1
  end

  # Pushed forward only: an older session created later never brings the date back.
  def postpone_purge!(session_expires_on:)
    purge_on = (session_expires_on + DORMANT_ACCOUNT_DELAY).end_of_month
    User.where(id: id, purge_on: ...purge_on).update_all(purge_on: purge_on)
  end

  # Hard delete, through the same path as any account deletion. Everything is checked again under the
  # row lock, which a sign-in creating a session also needs.
  def purge_if_unused!
    with_lock do
      destroy! if declarant? && purge_on < Date.current && sessions.none? && ReportOwnership.of(self).live.none?
    end
  end

  # Signing out everywhere too: whoever held the lost passkey may hold a verified session.
  # Returns the new enrollment code in clear, for the admin to hand over.
  def reset_passkeys!(by:)
    raise PasskeyResetNotAllowed unless by.admin? && by.active? && by != self && staff? && active?

    transaction do
      raise PasskeyResetNotAllowed unless acting_admin?(by)
      lock_for_passkey_change!
      raise PasskeyResetNotAllowed unless staff? && active?

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
    raise EnrollmentNotAllowed unless by.admin? && by.active? && staff? && active?

    RecoveryCode.generate_one.tap do |code|
      transaction do
        raise EnrollmentNotAllowed unless acting_admin?(by)

        update!(
          enrollment_code_digest: RecoveryCode.digest(code, purpose: :enrollment_code),
          enrollment_code_expires_on: Date.current + ENROLLMENT_CODE_VALIDITY
        )
        AuditEvent.record!(actor: by, action: "enrollment_code.issued", subject: self)
      end
    end
  end

  # Compare-and-swap on the digest: one statement checks and burns the code. Valid through its expiry day.
  def consume_enrollment_code!(code)
    return false if deactivated? || RecoveryCode.normalize(code).empty?

    consumed = User.where(id: id, enrollment_code_digest: RecoveryCode.digest(code, purpose: :enrollment_code))
      .where(enrollment_code_expires_on: Date.current..)
      .update_all(enrollment_code_digest: nil, enrollment_code_expires_on: nil) == 1
    self.enrollment_code_digest = self.enrollment_code_expires_on = nil if consumed
    consumed
  end

  def enrollment_code_expired?
    enrollment_code_digest.present? && enrollment_code_expires_on < Date.current
  end

  # For a staff member who leaves: the account cannot be deleted, access logs and audit events keep
  # pointing at it. Passkeys and codes go, so nothing is left to sign in with. Idempotent.
  def deactivate!(by:)
    raise DeactivationNotAllowed unless by.admin? && by.active? && by != self && staff?

    transaction do
      raise DeactivationNotAllowed unless acting_admin?(by)
      lock_for_passkey_change!
      raise TooFewAdmins if admin? && active? && other_admins_count < MINIMUM_ADMINS

      deactivated = User.active.where(id: id)
        .update_all(deactivated_at: Time.current, enrollment_code_digest: nil, enrollment_code_expires_on: nil) == 1
      if deactivated
        reload
        passkeys.delete_all
        recovery_codes.delete_all
        sign_out_everywhere!
        AuditEvent.record!(actor: by, action: "user.deactivated", subject: self)
      end
    end
    self
  end

  def deactivated?
    deactivated_at.present?
  end

  def active?
    !deactivated?
  end

  def staff?
    analyst? || admin?
  end

  def active_staff?
    staff? && active?
  end

  def member?
    membership_expires_on.present? && membership_expires_on >= Date.current
  end

  private
    # `by` may be a stale object: reread it once the admin rows are locked, in the same id order as
    # other_admins_count, so a concurrent deactivation of the actor cannot slip through or deadlock.
    def acting_admin?(by)
      User.where(role: "admin").order(:id).lock.pluck(:id)
      by.reload.then { |actor| actor.admin? && actor.active? }
    end

    # Serialises with Session#register_passkey!, which locks the same row. Lock order: after the admin
    # rows (acting_admin?), before any session, so two admins acting on each other cannot deadlock.
    def lock_for_passkey_change!
      lock!
    end

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
      (User.active.where(role: "admin").order(:id).lock.pluck(:id) - [ id ]).size
    end
end
