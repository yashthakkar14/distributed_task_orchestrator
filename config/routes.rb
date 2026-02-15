require 'sidekiq/web'

# Sidekiq::Web needs sessions for CSRF protection, but this is an API-only app.
# Wrap it with cookie-based session middleware.
Sidekiq::Web.use ActionDispatch::Cookies
Sidekiq::Web.use ActionDispatch::Session::CookieStore, key: '_job_orchestrator_session'

Rails.application.routes.draw do
  mount Sidekiq::Web => '/sidekiq'

  resources :jobs, only: [:create]

  get 'health/detailed', to: 'health#detailed'
end
