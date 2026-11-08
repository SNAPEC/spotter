# Registered in development only: lets a developer sign in without a mail server.
class MagicLinkLogObserver
  def self.delivered_email(message)
    url = message.text_part&.body&.decoded.to_s[%r{https?://\S+/login/\S+}]
    Rails.logger.info("Magic link: #{url}") if url
  end
end
