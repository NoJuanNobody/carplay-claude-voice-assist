Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # Authentication
      post   "auth/register", to: "auth#register"
      post   "auth/login",    to: "auth#login"
      delete "auth/logout",   to: "auth#logout"
      get    "auth/me",       to: "auth#me"

      # Profile management
      get    "profile",                 to: "profiles#show"
      put    "profile",                 to: "profiles#update"
      post   "profile/voice_signature", to: "profiles#enroll_voice_signature"
      delete "profile/voice_signature", to: "profiles#delete_voice_signature"

      # Voice sessions
      resources :sessions, only: %i[create destroy] do
        member do
          post   "messages", to: "sessions#create_message"
          get    "messages", to: "sessions#messages"
        end
      end

      # Vehicles
      resources :vehicles, only: %i[index create update] do
        member do
          put "state", to: "vehicles#update_state"
        end
      end

      # Safety
      post "safety/report_event", to: "safety#report_event"
      get  "safety/events",       to: "safety#events"
      post "safety/emergency",    to: "safety#emergency"

      # Health monitoring
      get "health",          to: "health#show"
      get "health/detailed", to: "health#detailed"
      get "health/metrics",  to: "health#metrics"
    end
  end
end
