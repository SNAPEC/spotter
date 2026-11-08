module Authorization
  extend ActiveSupport::Concern

  included do
    before_action :require_passkey_verified
  end

  class_methods do
    def require_role(*roles, **options)
      before_action(**options) { require_role(*roles) }
    end

    def allow_pending_passkey(**options)
      skip_before_action :require_passkey_verified, **options
    end
  end

  private
    def require_role(*roles)
      render "errors/forbidden", status: :forbidden unless roles.map(&:to_s).include?(Current.user.role)
    end

    # The magic link alone opens a staff session "pending": every page waits for a passkey or a recovery code.
    def require_passkey_verified
      return unless Current.user&.staff?
      return if Current.session.passkey_verified?

      session[:return_to_after_authenticating] = request.url if request.get? || request.head?
      redirect_to Current.user.passkeys.any? ? new_passkey_session_path : new_passkey_registration_path
    end
end
