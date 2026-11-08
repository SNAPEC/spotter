# Development only: every interface component on one page. Refused twice outside development, by the
# route constraint and here.
class Dev::StyleguideController < ApplicationController
  allow_unauthenticated_access
  allow_pending_passkey
  before_action :refuse_outside_development

  def show
  end

  private
    def refuse_outside_development
      head :not_found unless Rails.env.development?
    end
end
