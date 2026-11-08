class Admin::DeactivationsController < ApplicationController
  require_role :admin

  def create
    user = User.find(params[:user_id])
    user.deactivate!(by: Current.user)
    redirect_to admin_root_path, notice: t(".done", email: user.email), status: :see_other
  rescue User::TooFewAdmins
    redirect_to admin_root_path, alert: t(".too_few_admins", count: User::MINIMUM_ADMINS), status: :see_other
  rescue User::DeactivationNotAllowed
    redirect_to admin_root_path, alert: t(".not_allowed"), status: :see_other
  end
end
