require "rails_helper"

RSpec.describe "Solid Queue" do
  it "deletes a job row once it has run instead of keeping it as finished" do
    expect(SolidQueue.preserve_finished_jobs?).to be(false)
  end

  it "schedules no clearing of finished jobs, since none are kept" do
    recurring = Rails.application.config_for(:recurring, env: "production")

    expect(recurring.to_s).not_to include("clear_finished")
  end
end
