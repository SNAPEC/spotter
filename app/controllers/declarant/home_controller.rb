class Declarant::HomeController < ApplicationController
  require_role :declarant, :analyst, :admin

  def show
  end
end
