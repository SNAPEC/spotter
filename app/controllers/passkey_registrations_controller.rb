class PasskeyRegistrationsController < ApplicationController
  allow_pending_passkey
  require_role :analyst, :admin
  before_action :require_registration_allowed

  def new
  end

  def options
    options = Passkey.registration_options_for(Current.user)
    session[:passkey_registration_challenge] = options.challenge
    render json: options
  end

  def create
    @recovery_codes = Current.session.register_passkey!(
      credential: params[:credential].to_s,
      challenge: session.delete(:passkey_registration_challenge),
      nickname: params[:nickname].to_s
    )

    if @recovery_codes.any?
      response.headers["Cache-Control"] = "no-store"
      @continue_url = after_authentication_url
    else
      redirect_to after_authentication_url, notice: t(".done")
    end
  rescue Passkey::InvalidCredential
    redirect_to new_passkey_registration_path, alert: t(".failed")
  end

  private
    def require_registration_allowed
      redirect_to new_passkey_session_path unless Current.session.may_register_passkey?
    end
end
