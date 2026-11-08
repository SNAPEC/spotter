require "rails_helper"

RSpec.describe "Health check", type: :request do
  it "answers 200 on /up" do
    get "/up"

    expect(response).to have_http_status(:ok)
  end
end
