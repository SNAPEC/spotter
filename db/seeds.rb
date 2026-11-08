# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

taxonomy_path = Rails.root.join("db/seeds/taxonomy_v0.yml")
TaxonomyVersion.import!(taxonomy_path).publish! unless TaxonomyVersion.exists?(number: 0)

# Fictional accounts and reports: never in production.
load Rails.root.join("db/seeds/fake_reports.rb") unless Rails.env.production?
