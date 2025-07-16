DataDrip::Engine.routes.draw do
  resources :backfill_runs, only: %i[index show new create] do
    post :stop, on: :member
  end
end
