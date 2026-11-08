# Code that talks to the outside goes through these objects, so a double can stand in for it. The class
# for each environment is in config/external_services.yml. Set in to_prepare so a reload in development
# picks up the reloaded classes.
services = Rails.application.config_for(:external_services)

Rails.application.config.to_prepare do
  Rails.application.config.x.llm_extractor = services.fetch(:llm_extractor).constantize.new
  Rails.application.config.x.membership_verifier = services.fetch(:membership_verifier).constantize.new
end
