class RecoveryCodesController < ApplicationController
  allow_pending_passkey
  require_role :analyst, :admin
  rate_limit to: 5, within: 3.minutes, only: :create,
    by: -> { Current.user.id },
    with: -> { flash.now[:alert] = t(".too_many_requests"); render :new, status: :too_many_requests },
    store: Rails.configuration.x.rate_limit_store || cache_store

  def new
  end

  def create
    if Current.session.verify_recovery_code(params[:code].to_s)
      redirect_to new_passkey_registration_path, notice: t(".done")
    else
      flash.now[:alert] = t(".invalid")
      render :new, status: :unprocessable_entity
    end
  end
end
