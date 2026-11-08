module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      return unless (id = cookies.signed[:session_id])

      Session.resume(id).tap { |session| cookies.delete(:session_id) unless session }
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to login_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    # A fresh Rails session defeats fixation; only the return URL survives it.
    def start_new_session_for(user)
      return_to = session[:return_to_after_authenticating]
      reset_session
      session[:return_to_after_authenticating] = return_to if return_to

      user.sessions.create!.tap do |session|
        Current.session = session
        cookies.signed[:session_id] = { value: session.id, expires: session.expires_on.end_of_day, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end

    def terminate_all_sessions
      Current.user.sign_out_everywhere!
      cookies.delete(:session_id)
    end
end
