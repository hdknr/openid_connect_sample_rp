ConnectRp::Application.routes.draw do
  match 'providers/:provider_id/open_id/verify', to: 'open_ids#verify' ,:via => [:post]
  resources :providers, only: :create do
    resource :open_id, only: [:show, :create,]
  end
  resource :account, only: :show
  resource :session, only: :destroy

  root to: 'top#index'
end
