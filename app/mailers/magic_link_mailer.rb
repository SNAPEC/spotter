class MagicLinkMailer < ApplicationMailer
  def sign_in
    @user = params[:user]
    # A link queued before the deactivation must not leave: returning before `mail` sends nothing.
    return if @user.reload.deactivated?

    @url = magic_link_url(@user.magic_link_token)

    mail to: @user.email
  end
end
