class MagicLinksController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 3.minutes, only: :create,
    by: -> { IpFingerprint.for(request) },
    with: -> { flash.now[:alert] = t(".too_many_requests"); render :new, status: :too_many_requests },
    store: Rails.configuration.x.rate_limit_store || cache_store
  # Per address, against mail-bombing one inbox from many clients. The answer stays the generic one,
  # so the limit says nothing about the address.
  rate_limit to: 3, within: 1.hour, only: :create, name: "email",
    by: -> { User.email_fingerprint(params[:email]) },
    with: -> { render :create },
    store: Rails.configuration.x.rate_limit_store || cache_store

  def new
  end

  def create
    @user = User.send_magic_link(params[:email].to_s)

    if @user.persisted?
      render :create
    else
      flash.now[:alert] = t(".invalid_email")
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def consume
    if (user = User.sign_in_with_magic_link(params[:token])) && start_new_session_for(user)
      redirect_to after_authentication_url
    else
      redirect_to login_path, alert: t(".invalid")
    end
  end
end
