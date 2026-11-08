# Asks the extractor to code a submitted report, once per prompt version. The extractor call runs
# outside any lock: it is slow, and the report row must stay free meanwhile (an analyst may reject it).
class Report::Analyzer
  class InvalidProposals < StandardError; end
  class ExtractionFailed < StandardError; end

  PROPOSAL_KEYS = %w[value excerpt].freeze

  ANSWER_KINDS = %w[single multi integer].freeze

  def initialize(extractor: Rails.configuration.x.llm_extractor)
    @extractor = extractor
  end

  # Returns the analysis for the extractor's prompt version, or nil when the report is not waiting for
  # one (decided meanwhile, already analysed under another prompt version, or edited since: the
  # revision names the content this run was asked to analyse).
  def call(report, revision: report.content_revision)
    existing = analysis_of(report)
    return existing if existing

    report.with_lock { report.start_analysis! if report.submitted? && report.content_revision == revision }
    return unless report.analyzing? && report.content_revision == revision

    fields = report.taxonomy_version.fields.where(scope: "report", kind: ANSWER_KINDS).includes(:options)
    proposals = extract(report, fields)
    check!(report, proposals, fields)

    # The declarant may have edited the report while the extractor ran: proposals and excerpts would
    # then describe a text that no longer exists.
    report.with_lock do
      next analysis_of(report) unless report.analyzing? && report.content_revision == revision

      analysis = report.analyses.create!(
        provider: @extractor.provider, model: @extractor.model, prompt_version: @extractor.prompt_version, proposals: proposals
      )
      report.ready_for_validation!
      analysis
    end
  end

  # When the extractor fails for good, the analyst codes the report by hand: a failed analysis takes
  # the prompt version's place, so the job stays idempotent, and the report moves on to validation.
  def record_failure(report, revision: report.content_revision)
    report.with_lock do
      next unless report.content_revision == revision

      existing = analysis_of(report)
      next existing if existing

      report.start_analysis! if report.submitted?
      next unless report.analyzing?

      analysis = report.analyses.create!(
        status: "failed", provider: @extractor.provider, model: @extractor.model, prompt_version: @extractor.prompt_version
      )
      report.ready_for_validation!
      analysis
    end
  end

  private
    # The extractor's own error may quote the narrative (an echoed request, a provider message): it must
    # not reach the failed jobs table nor Sentry, so it is replaced, cause included.
    def extract(report, fields)
      @extractor.extract(text: text_of(report), schema: schema_for(fields))
    rescue StandardError
      raise ExtractionFailed, "extractor failed", cause: nil
    end

    def analysis_of(report)
      report.analyses.find_by(prompt_version: @extractor.prompt_version)
    end

    def text_of(report)
      narrative = report.narrative
      return "" unless narrative

      [ narrative.raw_text, *Narrative::DEBRIEF_FIELDS.map { |field| narrative[field] } ].compact_blank.join("\n\n")
    end

    def schema_for(fields)
      properties = fields.to_h do |field|
        value = case field.kind
        when "single" then { "enum" => field.options.map(&:code) }
        when "multi" then { "type" => "array", "items" => { "enum" => field.options.map(&:code) } }
        when "integer" then { "type" => "integer", "minimum" => 0 }
        end
        [ field.code, closed_object("value" => value, "excerpt" => { "type" => "string" }) ]
      end
      closed_object(properties)
    end

    # Closed at every level: anything the schema does not name could carry a quote of the narrative.
    def closed_object(properties)
      { "type" => "object", "properties" => properties, "required" => properties.keys, "additionalProperties" => false }
    end

    # The extractor validates its JSON already; this checks it again against the report's own taxonomy.
    # Messages name only taxonomy codes, never what the extractor wrote.
    def check!(report, proposals, fields)
      raise InvalidProposals, "not an object" unless proposals.is_a?(Hash)
      raise InvalidProposals, "fields differ from the schema" unless proposals.keys.sort == fields.map(&:code).sort

      malformed = proposals.reject do |_code, proposal|
        proposal.is_a?(Hash) && proposal.keys.sort == PROPOSAL_KEYS.sort && proposal["excerpt"].is_a?(String)
      end
      raise InvalidProposals, "malformed: #{malformed.keys.join(", ")}" if malformed.any?

      codes = report.taxonomy_version.validate_answers(proposals.transform_values { |proposal| proposal["value"] }, scope: :report)
      raise InvalidProposals, codes.join(", ") if codes.any?
    end
end
