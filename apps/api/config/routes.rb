Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "ready", to: "health#ready"
  get "internal/metrics", to: "metrics#show"
  mount ActionCable.server => "/cable"
  post "api/v1/publishing/callbacks/:partner_id", to: "publishing_callbacks#create"
  namespace :api do
    namespace :v1 do
      get "publishing", to: "publishing#index"
      post "publishing/partners", to: "publishing#register"
      post "publishing/partners/:partner_id/candidates", to: "publishing#submit"
      post "publishing/candidates/:candidate_id/validate", to: "publishing#validate"
      post "publishing/candidates/:candidate_id/publish", to: "publishing#publish"
      get "publishing/deployments/:deployment_id/diagnose", to: "publishing#diagnose"
      post "publishing/deployments/:deployment_id/reconcile", to: "publishing#reconcile"
      resource :session, only: %i[show create destroy], controller: :sessions
      post "accounts", to: "sessions#register"
      resources :creators, only: %i[index create] do
        get :mine, on: :collection
      end
      resources :projects, only: %i[index show create update] do
        post :propose, on: :member
        post :award, on: :member
        post :intake, on: :member
        resources :proposal_examples, only: %i[create show destroy] do
          get :download, on: :member
        end
      end
      resources :engagements, only: %i[index show] do
        post :submit, on: :member
        post :start, on: :member
        post :feedback, on: :member
        get :archive, on: :member
        post :accept, on: :member
        resources :work_files, only: %i[index create show destroy] do
          get :download, on: :member
        end
        get "finance", to: "finance#show"
        post "finance", to: "finance#create"
        post "hold", to: "finance#hold"
      end
      resources :notifications, only: %i[index update]
      resources :portfolio, only: %i[index create], controller: :portfolio do
        get :download, on: :member
      end
      get "operations", to: "operations#index"
      post "operations/reconcile", to: "operations#reconcile"
      post "operations/settlements/:id/release", to: "operations#release_hold"
      post "operations/deliveries/:id/retry", to: "operations#retry_delivery"
      post "webhooks/sandbox", to: "webhooks#create"
    end
  end
end
