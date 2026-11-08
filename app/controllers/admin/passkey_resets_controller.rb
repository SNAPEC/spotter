class Admin::PasskeyResetsController < ApplicationController
  require_role :admin

  def create
    @user = User.find(params[:user_id])
    @enrollment_code = @user.reset_passkeys!(by: Current.user)
    response.headers["Cache-Control"] = "no-store"
  rescue User::PasskeyResetNotAllowed
    redirect_to admin_root_path, alert: t(".not_allowed")
  end
end
