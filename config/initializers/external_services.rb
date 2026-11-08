# Code that talks to the outside goes through these objects, so a double can stand in for it.
# Every environment uses the doubles for now, production included: the Scaleway extractor and the
# SNAPEC membership API are not written yet. Set in to_prepare so a reload in development picks up
# the reloaded classes.
Rails.application.config.to_prepare do
  Rails.application.config.x.llm_extractor = Llm::FakeExtractor.new
  Rails.application.config.x.membership_verifier = Membership::FakeVerifier.new
end
