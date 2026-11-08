class User < ApplicationRecord
  ROLES = %w[declarant analyst admin].freeze

  has_many :sessions, dependent: :destroy

  enum :role, ROLES.index_with(&:itself), default: "declarant", validate: true

  encrypts :email, deterministic: true, downcase: true
  normalizes :email, with: ->(email) { email.strip }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  generates_token_for :magic_link, expires_in: 15.minutes do
    login_token_version
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

  def staff?
    analyst? || admin?
  end

  def member?
    membership_expires_on.present? && membership_expires_on >= Date.current
  end
end
