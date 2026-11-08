class Analyst::HomeController < ApplicationController
  require_role :analyst, :admin

  def show
  end
end
