DataDrip::Engine.routes.draw do
  resources :backfill_runs, only: %i[index show new create destroy] do
    post :stop, on: :member
  end
  
  post 'backfill_runs/set_timezone', to: 'backfill_runs#set_timezone', as: :set_timezone_backfill_runs
end
