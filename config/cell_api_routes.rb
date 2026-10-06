# frozen_string_literal: true

DataDrip::CellApi::Engine.routes.draw do
  scope "v1", module: "v1", as: "v1" do
    resources :backfill_runs, only: %i[create destroy] do
      post :stop, on: :member
      post :retry_failed_batches, on: :member
    end

    resources :script_runs, only: %i[create destroy]

    resources :groups, only: :show, param: :group_uuid
  end
end
