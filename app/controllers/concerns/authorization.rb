module Authorization
  extend ActiveSupport::Concern

  class_methods do
    def require_role(*roles, **options)
      before_action(**options) { require_role(*roles) }
    end
  end

  private
    def require_role(*roles)
      render "errors/forbidden", status: :forbidden unless roles.map(&:to_s).include?(Current.user.role)
    end

    # Wired in task 5 together with passkeys; until then every signed-in user passes.
    def require_passkey_verified
    end
end
