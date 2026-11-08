class PasskeySessionsController < ApplicationController
  allow_pending_passkey
  require_role :analyst, :admin
  before_action :require_passkey

  def new
  end

  def options
    render json: Current.session.passkey_authentication_options!
  end

  def create
    if Current.session.verify_passkey(credential: params[:credential].to_s)
      redirect_to after_authentication_url
    else
      redirect_to new_passkey_session_path, alert: t(".failed")
    end
  end

  private
    def require_passkey
      redirect_to new_passkey_registration_path if Current.user.passkeys.none?
    end
end
