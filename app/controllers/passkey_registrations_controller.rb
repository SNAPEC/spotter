class PasskeyRegistrationsController < ApplicationController
  allow_pending_passkey
  require_role :analyst, :admin
  before_action :require_registration_allowed
  rate_limit to: 5, within: 3.minutes, only: :create,
    by: -> { Current.user.id },
    with: -> { flash.now[:alert] = t(".too_many_requests"); render :new, status: :too_many_requests },
    store: Rails.configuration.x.rate_limit_store || cache_store

  def new
  end

  def options
    render json: Current.session.passkey_registration_options!
  end

  def create
    @recovery_codes = Current.session.register_passkey!(
      credential: params[:credential].to_s,
      nickname: params[:nickname].to_s,
      enrollment_code: params[:enrollment_code].to_s
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
