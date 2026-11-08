class Admin::PasskeyResetsController < ApplicationController
  require_role :admin

  def create
    user = User.find(params[:user_id])
    user.reset_passkeys!(by: Current.user)
    redirect_to admin_root_path, notice: t(".done")
  rescue User::PasskeyResetNotAllowed
    redirect_to admin_root_path, alert: t(".not_allowed")
  end
end
