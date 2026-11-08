class AddNoneToAnalysisProviders < ActiveRecord::Migration[8.1]
  def up
    replace_provider_check(Analysis::PROVIDERS)
  end

  def down
    replace_provider_check(%w[fake scaleway])
  end

  private
    def replace_provider_check(providers)
      remove_check_constraint :analyses, name: "analyses_provider_check"
      add_check_constraint :analyses, "provider IN (#{providers.map { |value| connection.quote(value) }.join(", ")})", name: "analyses_provider_check"
    end
end
