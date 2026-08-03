# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::BackfillsController, type: :controller do
  routes { DataDrip::Engine.routes }

  # The catalog page renders the shared header, which resolves the current
  # backfiller — so at least one user has to exist.
  let!(:backfiller) { User.create!(name: "Suzie") }

  describe "GET #index" do
    render_views

    it "renders the catalog" do
      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Backfills catalog")
    end

    it "shows a backfill's description and its configurable fields" do
      # Scope to a single backfill so the assertions don't depend on how many
      # other named backfills happen to be loaded in the suite.
      get :index, params: { q: "intern" } # matches AddRoleToEmployee's description

      expect(response.body).to include("AddRoleToEmployee")
      expect(response.body).to include("Assigns the default")
      expect(response.body).to include(">age</span>")     # option pill (name)
      expect(response.body).to include(">integer</span>") # option pill (type)
    end

    it "filters by an option name so operators can find a field" do
      get :index, params: { q: "max_age" }

      expect(response.body).to include("SetEmployeeRole")
      expect(response.body).not_to include("AddBirthdayToEmployee")
    end

    it "lists matching backfills in alphabetical order" do
      get :index, params: { q: "employee" } # matches only the three fixtures

      body = response.body
      expect(body.index("AddBirthdayToEmployee")).to be < body.index(
        "AddRoleToEmployee"
      )
      expect(body.index("AddRoleToEmployee")).to be < body.index(
        "SetEmployeeRole"
      )
    end

    it "shows at most one page (10) of results at a time" do
      # More named backfills than fit on a page, all matching one query.
      11.times do |i|
        stub_const(
          "PageProbe#{format("%02d", i)}Backfill",
          Class.new(DataDrip::Backfill) do
            def scope
              Employee.all
            end

            def process_element(_element); end
          end
        )
      end

      get :index, params: { q: "pageprobe" }

      rows = response.body.scan('<tr class="align-top"').size
      expect(rows).to eq(10)
      expect(response.body).to include("Next")
    end
  end
end
