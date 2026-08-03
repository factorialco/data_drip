# frozen_string_literal: true

DataDrip::Engine.routes.draw do
  root to: "backfill_runs#index"

  # Compiled Tailwind CSS, served outside the host asset pipeline.
  get "tailwind.css", to: "assets#stylesheet", as: :tailwind_stylesheet

  resources :backfill_runs, only: %i[index show new create destroy] do
    post :stop, on: :member
    post :retry_failed_batches, on: :member
    get :updates, on: :member
    get :backfill_options, on: :collection
  end

  post "backfill_runs/set_timezone",
       to: "backfill_runs#set_timezone",
       as: :set_timezone_backfill_runs

  # Catalog of the backfill *definitions* available in the host app (as opposed
  # to backfill_runs, which lists persisted runs).
  resources :backfills, only: %i[index]

  resources :script_runs, only: %i[index show new create destroy] do
    get :updates, on: :member
    get :script_inputs, on: :collection
  end
end
