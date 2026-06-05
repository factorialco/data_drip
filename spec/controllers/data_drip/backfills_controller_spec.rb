# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::BackfillsController, type: :controller do
  routes { DataDrip::Engine.routes }

  describe "GET #index" do
    render_views

    it "lists available backfills with their descriptions and custom fields" do
      get :index

      expect(response).to have_http_status(:ok)

      # Backfill name
      expect(response.body).to include("AddRoleToEmployee")
      # Description (clean substring — apostrophes are HTML-escaped in output)
      expect(response.body).to include("Assigns the default")
      # Declared custom fields rendered as chips
      expect(response.body).to include("age: integer")
      expect(response.body).to include("name: string")
    end

    it "renders the search box for filtering the catalog" do
      get :index

      expect(response.body).to include("backfill_search")
    end
  end
end
