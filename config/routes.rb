# frozen_string_literal: true

DataDrip::Engine.routes.draw do
  root to: "backfill_runs#index"

  resources :backfill_runs, only: %i[index show new create destroy] do
    post :stop, on: :member
    get :updates, on: :member
    get :stream, on: :member
    get :backfill_options, on: :collection
  end

  post "backfill_runs/set_timezone",
       to: "backfill_runs#set_timezone",
       as: :set_timezone_backfill_runs
end
