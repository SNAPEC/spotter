Rails.application.routes.draw do
  get "login" => "magic_links#new", as: :login
  post "login" => "magic_links#create"
  # The GET only shows a confirmation button: mail scanners that prefetch links must not burn them.
  get "login/:token" => "magic_links#show", as: :magic_link
  post "login/:token" => "magic_links#consume"

  resource :session, only: :destroy
  delete "sessions" => "sessions#destroy_all", as: :sessions

  resource :passkey_registration, only: %i[new create] do
    post :options
  end
  resource :passkey_session, only: %i[new create] do
    post :options
  end
  resource :recovery_code, only: %i[new create]

  root "declarant/home#show"
  get "analyst" => "analyst/home#show", as: :analyst_root
  get "admin" => "admin/home#show", as: :admin_root
  namespace :admin do
    resources :users, only: [] do
      resource :passkey_reset, only: :create
      resource :deactivation, only: :create
    end
  end

  # Development only. The controller refuses on its own too.
  constraints(-> { Rails.env.development? }) do
    namespace :dev do
      resource :login, only: %i[show create]
      get "styleguide" => "styleguide#show"
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
