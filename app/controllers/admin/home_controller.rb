class Admin::HomeController < ApplicationController
  require_role :admin

  def show
    @staff = User.staff.includes(:passkeys).order(:id)
  end
end
