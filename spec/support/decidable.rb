# validate! needs the analyst's anonymised text, which needs the report taken in charge: most specs only
# care about what the decision does afterwards.
module Decidable
  extend self

  def validate_with_text!(report, analyst)
    report.take_charge!(analyst)
    report.write_anonymized_text!(analyst, "Récit anonymisé fictif.")
    report.validate!(analyst)
  end

  def decide_with_text!(report, decision, analyst)
    return report.public_send(decision, analyst) unless decision.to_s == "validate!"

    validate_with_text!(report, analyst)
  end
end

RSpec.configure { |config| config.include Decidable }
