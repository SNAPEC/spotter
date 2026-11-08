require "rails_helper"
require "capybara/rspec"

RSpec.describe "Passkeys", type: :system do
  let(:origin) { URI(Rails.configuration.x.webauthn.origin) }
  let(:analyst) { User.create!(email: "analyste@example.com", role: "analyst") }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    # WebAuthn refuses IP addresses as relying party: the browser must reach the app as localhost.
    Capybara.server_port = origin.port
    Capybara.app_host = origin.to_s

    browser = page.driver.browser
    browser.execute_cdp("WebAuthn.enable", enableUI: false)
    browser.execute_cdp("WebAuthn.addVirtualAuthenticator", options: {
      protocol: "ctap2", transport: "internal",
      hasResidentKey: true, hasUserVerification: true, isUserVerified: true,
      automaticPresenceSimulation: true
    })
  end

  after { Capybara.app_host = nil }

  def sign_in(user)
    visit magic_link_path(user.reload.magic_link_token)
    click_on "Se connecter"
  end

  it "registers a passkey, then signs in with it" do
    visit "/analyst"
    sign_in(analyst)

    expect(page).to have_content("Enregistrer une passkey")
    fill_in "Nom de l’appareil", with: "Ordinateur de test"
    click_on "Enregistrer une passkey"

    expect(page).to have_content("Vos codes de secours")
    expect(page).to have_css("li code", count: 10)
    click_on "Continuer"
    expect(page).to have_css("h1", text: "Analyse")
    expect(analyst.passkeys.sole.nickname).to eq("Ordinateur de test")

    click_on "Se déconnecter", exact: true
    expect(page).to have_content("Vous êtes déconnecté.")

    visit "/analyst"
    sign_in(analyst)
    expect(page).to have_content("Vérifier avec ma passkey")
    click_on "Vérifier avec ma passkey"

    expect(page).to have_css("h1", text: "Analyse")
  end
end
