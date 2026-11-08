require "rails_helper"

RSpec.describe Llm::FakeExtractor do
  let(:extractor) { described_class.new }
  let(:schema) do
    {
      "type" => "object",
      "properties" => {
        "weather" => { "type" => "object", "properties" => { "value" => { "enum" => %w[good rain wind] }, "excerpt" => { "type" => "string" } } },
        "risk_factors" => { "type" => "object", "properties" => { "value" => { "type" => "array", "items" => { "enum" => %w[fatigue cold] } }, "excerpt" => { "type" => "string" } } },
        "clients_count" => { "type" => "object", "properties" => { "value" => { "type" => "integer" }, "excerpt" => { "type" => "string" } } }
      }
    }
  end
  let(:text) { "Chute fictive au deuxième point. Le reste de la séance s'est bien passé." }

  it "is the configured extractor in test and development, with no network, and never in production" do
    expect(Rails.configuration.x.llm_extractor).to be_a(described_class)
    expect(Rails.application.config_for(:external_services, env: "development")[:llm_extractor]).to eq("Llm::FakeExtractor")
    expect(Rails.application.config_for(:external_services, env: "production")[:llm_extractor]).to eq("Llm::UnconfiguredExtractor")
  end

  it "names its provider, model and prompt version" do
    expect([ extractor.provider, extractor.model, extractor.prompt_version ]).to all(be_present)
  end

  it "returns a value from the schema and an excerpt for every field" do
    result = extractor.extract(text: text, schema: schema)

    expect(result.keys).to contain_exactly("weather", "risk_factors", "clients_count")
    expect(%w[good rain wind]).to include(result["weather"]["value"])
    expect(result["risk_factors"]["value"]).to all(be_in(%w[fatigue cold]))
    expect(result["clients_count"]["value"]).to be_a(Integer)
    expect(result.values.map { |proposal| proposal["excerpt"] }).to all(eq("Chute fictive au deuxième point."))
  end

  it "gives the same answer for the same text" do
    expect(extractor.extract(text: text, schema: schema)).to eq(described_class.new.extract(text: text.dup, schema: schema))
  end
end
