# Production's extractor until the Scaleway client exists: every call fails, so each report goes
# through Report::Analyzer#record_failure and the analyst codes it by hand. Never the double there: its
# proposals would pass for the LLM's.
class Llm::UnconfiguredExtractor
  class NotConfigured < StandardError; end

  def provider
    "none"
  end

  def model
    "none"
  end

  def prompt_version
    "unconfigured-v1"
  end

  def extract(text:, schema:)
    raise NotConfigured, "no LLM extractor is configured"
  end
end
