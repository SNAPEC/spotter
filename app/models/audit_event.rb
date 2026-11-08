class AuditEvent < ApplicationRecord
  ACTIONS = %w[passkeys.reset enrollment_code.issued user.deactivated passkey.enrolled_after_recovery].freeze

  belongs_to :actor, class_name: "User"
  belongs_to :subject, polymorphic: true

  validates :action, inclusion: { in: ACTIONS }

  def self.record!(actor:, action:, subject:)
    create!(actor: actor, action: action, subject: subject)
  end
end
