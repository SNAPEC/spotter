# Asks the extractor to code a submitted report, once per prompt version. The extractor call runs
# outside any lock: it is slow, and the report row must stay free meanwhile (an analyst may reject it).
class Report::Analyzer
  class InvalidProposals < StandardError; end

  ANSWER_KINDS = %w[single multi integer].freeze

  def initialize(extractor: Rails.configuration.x.llm_extractor)
    @extractor = extractor
  end

  # Returns the analysis for the extractor's prompt version, or nil when the report is not waiting for
  # one (decided meanwhile, or already analysed under another prompt version).
  def call(report)
    existing = analysis_of(report)
    return existing if existing

    report.with_lock { report.start_analysis! if report.submitted? }
    return unless report.analyzing?

    fields = report.taxonomy_version.fields.where(scope: "report", kind: ANSWER_KINDS).includes(:options)
    proposals = @extractor.extract(text: text_of(report), schema: schema_for(fields))
    check!(report, proposals, fields)

    report.with_lock do
      next analysis_of(report) unless report.analyzing?

      analysis = report.analyses.create!(
        provider: @extractor.provider, model: @extractor.model, prompt_version: @extractor.prompt_version, proposals: proposals
      )
      report.ready_for_validation!
      analysis
    end
  end

  private
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
        [ field.code, { "type" => "object", "properties" => { "value" => value, "excerpt" => { "type" => "string" } } } ]
      end
      { "type" => "object", "properties" => properties }
    end

    # The extractor validates its JSON already; this checks it again against the report's own taxonomy.
    def check!(report, proposals, fields)
      raise InvalidProposals, "not a hash" unless proposals.is_a?(Hash) && proposals.values.all?(Hash)

      codes = report.taxonomy_version.validate_answers(proposals.transform_values { |proposal| proposal["value"] }, scope: :report)
      unknown = proposals.keys - fields.map(&:code)
      raise InvalidProposals, (codes + unknown).join(", ") if codes.any? || unknown.any?
    end
end
