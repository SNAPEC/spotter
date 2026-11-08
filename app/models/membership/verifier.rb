# Checks SNAPEC membership for an address. Implementations return { valid: Boolean, expires_on: Date | nil }.
class Membership::Verifier
  def call(email:)
    raise NotImplementedError, "#{self.class} must implement call(email:)"
  end
end
