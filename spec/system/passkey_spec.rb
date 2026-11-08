require "rails_helper"
require "capybara/rspec"

RSpec.describe "Passkeys", type: :system do
  let(:origin) { URI(Rails.configuration.x.webauthn.origin) }
  let(:analyst) { User.create!(email: "analyste@example.com", role: "analyst") }
  let(:admin) { User.create!(email: "admin@example.com", role: "admin") }

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
    # Kept in sessionStorage so violations survive full page loads as well as Turbo visits.
    browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      document.addEventListener("securitypolicyviolation", event => {
        const violations = JSON.parse(sessionStorage.getItem("csp-violations") || "[]")
        violations.push(`${event.violatedDirective} ${event.blockedURI}`)
        sessionStorage.setItem("csp-violations", JSON.stringify(violations))
      })
    JS
  end

  after { Capybara.app_host = nil }

  def csp_violations
    JSON.parse(page.evaluate_script("sessionStorage.getItem('csp-violations') || '[]'"))
  end

  def sign_in(user)
    path = magic_link_path(user.reload.magic_link_token)
    visit path
    click_on "Se connecter"
    expect(page).to have_no_current_path(path)
  end

  it "registers a passkey with an enrollment code, then signs in with it" do
    code = analyst.issue_enrollment_code!(by: admin)
    visit "/analyst"
    sign_in(analyst)

    expect(page).to have_content("Enregistrer une passkey")
    fill_in "Code d’enrôlement", with: code
    fill_in "Nom de l’appareil", with: "Ordinateur de test"
    click_on "Enregistrer une passkey"

    # Wait for each navigation through the title or the path, which need no DOM node of the page being
    # replaced: reading one mid-navigation raises a Selenium error that Capybara does not retry.
    expect(page).to have_title("Vos codes de secours")
    expect(page).to have_css("li code", count: 10)
    click_on "Continuer"
    expect(page).to have_current_path("/analyst")
    expect(page).to have_css("h1", text: "Analyse")
    expect(analyst.passkeys.sole.nickname).to eq("Ordinateur de test")

    click_on "Se déconnecter", exact: true
    expect(page).to have_current_path(login_path)
    expect(page).to have_content("Vous êtes déconnecté.")

    visit "/analyst"
    sign_in(analyst)
    expect(page).to have_content("Vérifier avec ma passkey")
    click_on "Vérifier avec ma passkey"

    expect(page).to have_current_path("/analyst")
    expect(page).to have_css("h1", text: "Analyse")
    expect(csp_violations).to be_empty
  end
end
