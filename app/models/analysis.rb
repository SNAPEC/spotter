# A snapshot of what the extractor proposed for a report. The analyst's final codes live on the report;
# Analysis.proposal_vs_validated compares the two to measure the extractor.
class Analysis < ApplicationRecord
  include ReadOnlyOnceDecided

  STATUSES = %w[proposed failed].freeze
  PROVIDERS = %w[fake none scaleway].freeze

  belongs_to :report

  serialize :proposals, coder: JSON
  attribute :proposals, default: -> { {} }
  encrypts :proposals

  validates :status, inclusion: { in: STATUSES }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :model, :prompt_version, presence: true

  # Excerpts quote the declarant's narrative: they do not outlive the decision. Only each proposal's coded
  # value is kept, and only for a field of the report's taxonomy: any other key (an anonymised text the
  # extractor would add, say) is derived from the narrative and goes with it.
  def strip_raw_excerpts!
    codes = coded_field_codes
    update!(proposals: proposals.to_h.filter_map { |code, proposal| [ code, proposal.slice("value") ] if codes.include?(code) && proposal.is_a?(Hash) }.to_h)
  end

  # What the extractor proposed against what the analyst validated, field by field, over the validated
  # reports that have a proposing analysis: [{ prompt_version:, field:, proposed:, validated: }, ...].
  # A field the analyst left empty is validated as nil, and an unstated proposal is nil too: both sides
  # are compared as stored. Only codes come out, no report, no date, no text, so rows can be aggregated.
  def self.proposal_vs_validated
    where(status: "proposed").joins(:report).merge(Report.where(status: "validated")).includes(:report).flat_map do |analysis|
      validated = analysis.report.final_codes
      analysis.proposals.filter_map do |code, proposal|
        next unless proposal.is_a?(Hash) && proposal.key?("value")

        { prompt_version: analysis.prompt_version, field: code, proposed: proposal["value"], validated: validated[code] }
      end
    end
  end

  private
    def kept_after_decision?
      codes = coded_field_codes
      proposals.to_h.all? { |code, proposal| codes.include?(code) && proposal.is_a?(Hash) && (proposal.keys - [ "value" ]).empty? }
    end

    def coded_field_codes
      report.taxonomy_version.fields.where(scope: "report", kind: Report::Analyzer::ANSWER_KINDS).pluck(:code)
    end
end
