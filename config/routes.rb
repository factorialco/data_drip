DataDrip::Engine.routes.draw do
  resources :backfill_runs, only: %i[index show new create destroy] do
    post :stop, on: :member
  end
end
