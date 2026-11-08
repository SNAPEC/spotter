class SessionsController < ApplicationController
  allow_pending_passkey only: :destroy
  allow_recovered_session only: %i[destroy destroy_all]

  def destroy
    terminate_session
    redirect_to login_path, notice: t("sessions.signed_out"), status: :see_other
  end

  def destroy_all
    terminate_all_sessions
    redirect_to login_path, notice: t(".done"), status: :see_other
  end
end
