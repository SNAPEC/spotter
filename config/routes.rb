Rails.application.routes.draw do
  get "login" => "magic_links#new", as: :login
  post "login" => "magic_links#create"
  # The GET only shows a confirmation button: mail scanners that prefetch links must not burn them.
  get "login/:token" => "magic_links#show", as: :magic_link
  post "login/:token" => "magic_links#consume"

  # Placeholder until the declarant home lands (task 4).
  root "magic_links#new"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
