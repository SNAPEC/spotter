class Admin::HomeController < ApplicationController
  require_role :admin

  def show
    @staff = User.where(role: %w[analyst admin]).includes(:passkeys).order(:id)
  end
end
