class Admin::HomeController < ApplicationController
  require_role :admin

  def show
  end
end
