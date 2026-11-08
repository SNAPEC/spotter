require "rails_helper"

RSpec.describe "Content Security Policy", type: :request do
  def directives
    response.headers["Content-Security-Policy"].split(";").to_h { |directive| directive.strip.split(" ", 2) }
  end

  before { get login_path }

  it "allows only the app's own origin, and no plugin, frame or foreign form target" do
    expect(directives).to include(
      "default-src" => "'self'", "object-src" => "'none'", "base-uri" => "'self'",
      "form-action" => "'self'", "frame-ancestors" => "'none'"
    )
  end

  it "never allows inline code or eval" do
    expect(response.headers["Content-Security-Policy"]).not_to include("unsafe-inline", "unsafe-eval")
  end

  it "lets the inline importmap run through a nonce" do
    nonce = directives["script-src"][/'nonce-([^']+)'/, 1]
    page = Nokogiri::HTML(response.body)

    expect(nonce).to be_present
    expect(page.at('script[type="importmap"]')["nonce"]).to eq(nonce)
    expect(page.css("script:not([src])").map { |script| script["nonce"] }).to all(eq(nonce))
    expect(page.at('meta[name="csp-nonce"]')["content"]).to eq(nonce)
    expect(directives["style-src"]).to include("'nonce-#{nonce}'")
  end

  it "renders no inline style attribute, which the policy would block" do
    expect(Nokogiri::HTML(response.body).css("[style]")).to be_empty
  end
end
