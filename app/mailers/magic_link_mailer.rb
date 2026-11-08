class MagicLinkMailer < ApplicationMailer
  def sign_in
    @user = params[:user]
    @url = magic_link_url(@user.magic_link_token)

    mail to: @user.email
  end
end
