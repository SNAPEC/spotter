require "rails_helper"

RSpec.describe "Filtered parameters" do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it "masks free-text answers and the anonymised text, wherever they are nested" do
    params = {
      "report" => {
        "answers" => { "material_damage" => "Texte libre fictif" },
        "casualties_attributes" => { "0" => { "answers" => { "injury_detail" => "Détail fictif" } } }
      },
      "analysis" => { "anonymized_text" => "Récit anonymisé fictif" }
    }

    filtered = filter.filter(params).to_s

    expect(filtered).not_to include("Texte libre fictif", "Détail fictif", "Récit anonymisé fictif")
    expect(filtered).to include("[FILTERED]")
  end
end
