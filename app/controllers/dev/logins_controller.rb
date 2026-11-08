# Development only: signs in as a seeded account without a mail or a passkey. Refused twice outside
# development, by the route constraint and here.
class Dev::LoginsController < ApplicationController
  allow_unauthenticated_access
  allow_pending_passkey
  before_action :refuse_outside_development

  def show
    @users = User.active.order(:role, :id)
  end

  def create
    user = User.find(params[:user_id])
    start_new_session_for(user).update!(passkey_verified: user.staff?)
    redirect_to landing_path_for(user), status: :see_other
  end

  private
    def refuse_outside_development
      head :not_found unless Rails.env.development?
    end

    def landing_path_for(user)
      case user.role
      when "admin" then admin_root_path
      when "analyst" then analyst_root_path
      else root_path
      end
    end
end
