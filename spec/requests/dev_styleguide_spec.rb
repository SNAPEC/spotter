require "rails_helper"

RSpec.describe "Development styleguide", type: :request do
  it "is not routed outside development" do
    get "/dev/styleguide"

    expect(response).to have_http_status(:not_found)
  end

  it "refuses outside development, even when the route constraint lets the request through" do
    # First call: the route constraint. Second: the controller's own check.
    allow(Rails.env).to receive(:development?).and_return(true, false)

    get "/dev/styleguide"

    expect(response).to have_http_status(:not_found)
  end

  it "shows every component in development, without signing in" do
    allow(Rails.env).to receive(:development?).and_return(true)

    get "/dev/styleguide"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Guide de style", 'role="alert"', 'aria-current="step"', 'type="radio"', 'type="checkbox"', 'aria-invalid="true"')
  end
end
