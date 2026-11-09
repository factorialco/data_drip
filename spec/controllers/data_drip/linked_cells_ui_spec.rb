# frozen_string_literal: true

require "spec_helper"

# Linked cells (DataDrip.linked_cells) are offered as boxes of their own on
# the new-run forms, independent of "Run this in multiple cells".
module LinkedCellsUiHelpers
  def linked_box(id = "linked-x")
    Nokogiri::HTML(response.body).at_css(
      "input[type=checkbox][name='linked_cell_ids[]'][value='#{id}']"
    )
  end

  def multi_cell_box
    Nokogiri::HTML(response.body).at_css("input[type=checkbox][name=multi_cell]")
  end

  def configure_linked_cells!(default_for: %i[backfill])
    DataDrip.linked_cells = {
      "linked-x" => { label: "Sandbox", default_for: default_for }
    }
  end
end

RSpec.describe DataDrip::BackfillRunsController, type: :controller do
  include LinkedCellsUiHelpers

  routes { DataDrip::Engine.routes }

  let!(:backfiller) { User.create!(name: "Suzie") }

  let(:valid_attributes) do
    { backfill_class_name: "AddRoleToEmployee", batch_size: 100, start_at: 1.hour.from_now }
  end

  before do
    Employee.create!(name: "Pepe", role: nil, age: 25)
    configure_multi_cell!
    configure_linked_cells!
  end

  describe "GET #new" do
    render_views

    it "ticks a linked cell whose default_for includes backfills" do
      get :new

      expect(linked_box["checked"]).to be_present
      expect(linked_box["disabled"]).to be_nil
      expect(response.body).to include("Also run in Sandbox")
    end

    it "leaves a linked cell unticked when its default_for leaves backfills out" do
      configure_linked_cells!(default_for: %i[script])

      get :new

      expect(linked_box["checked"]).to be_nil
    end

    it "keeps a linked cell unticked when a form submitted unticked is shown again" do
      post :create, params: { backfill_run: valid_attributes.merge(batch_size: 0) }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(linked_box["checked"]).to be_nil
    end

    it "keeps a linked cell ticked when a form submitted ticked is shown again" do
      post :create,
           params: { backfill_run: valid_attributes.merge(batch_size: 0), linked_cell_ids: %w[linked-x] }

      expect(linked_box["checked"]).to be_present
    end

    it "offers linked cells in a deployment with no other cell of its own" do
      configure_multi_cell!(cells: %w[cell-a])

      get :new

      expect(multi_cell_box).to be_nil
      expect(linked_box).to be_present
    end

    it "offers no linked cell without a current cell or a transport" do
      reset_multi_cell_config!
      configure_linked_cells!

      get :new

      expect(linked_box).to be_nil
    end
  end

  describe "POST #create" do
    it "sends the run to a ticked linked cell, alone" do
      post :create, params: { backfill_run: valid_attributes, linked_cell_ids: %w[linked-x] }

      run = DataDrip::BackfillRun.last!
      expect(run.group_uuid).to be_present
      expect(run.cell_id).to eq("cell-a")
      expect(run.dispatches.map(&:cell_id)).to eq(%w[linked-x])
    end

    it "sends the run to the picked cells and the ticked linked cell together" do
      post :create,
           params: {
             backfill_run: valid_attributes,
             multi_cell: "1",
             target_cell_ids: %w[cell-c],
             linked_cell_ids: %w[linked-x]
           }

      expect(DataDrip::BackfillRun.last!.dispatches.map(&:cell_id)).to eq(%w[cell-c linked-x])
    end

    it "creates a plain run when nothing is ticked" do
      post :create, params: { backfill_run: valid_attributes }

      expect(DataDrip::BackfillRun.last!.group_uuid).to be_nil
      expect(DataDrip::CellDispatch.count).to eq(0)
    end

    it "ignores linked cells that are not configured" do
      post :create, params: { backfill_run: valid_attributes, linked_cell_ids: %w[cell-b elsewhere] }

      expect(DataDrip::BackfillRun.last!.group_uuid).to be_nil
      expect(DataDrip::CellDispatch.count).to eq(0)
    end

    it "still asks for another cell when several cells are asked for but none is picked" do
      post :create, params: { backfill_run: valid_attributes, multi_cell: "1", linked_cell_ids: %w[linked-x] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(DataDrip::BackfillRun.count).to eq(0)
    end
  end

  describe "GET #show" do
    render_views

    it "labels a linked cell's card" do
      run =
        DataDrip::BackfillRun.create!(valid_attributes.merge(backfiller: backfiller, group_uuid: "g-1"))
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "linked-x",
        runnable_type: :backfill,
        status: :pending,
        error_message: "Not deployed in that cell yet (nope). Retrying every 15 minutes until later."
      )

      get :show, params: { id: run.id }

      expect(response.body).to include("linked-x")
      expect(response.body).to include("Sandbox")
      expect(response.body).to include("Not deployed in that cell yet")
    end
  end
end

RSpec.describe DataDrip::ScriptRunsController, type: :controller do
  include LinkedCellsUiHelpers

  routes { DataDrip::Engine.routes }

  let!(:backfiller) { User.create!(name: "Suzie") }

  before do
    configure_multi_cell!
    configure_linked_cells!
  end

  describe "GET #new" do
    render_views

    it "leaves a linked cell unticked when its default_for leaves scripts out" do
      get :new

      expect(linked_box).to be_present
      expect(linked_box["checked"]).to be_nil
    end

    it "ticks a linked cell whose default_for includes scripts" do
      configure_linked_cells!(default_for: %i[backfill script])

      get :new

      expect(linked_box["checked"]).to be_present
    end
  end

  describe "POST #create" do
    it "sends the script to a ticked linked cell" do
      post :create,
           params: {
             script_run: { script_class_name: "GreetEmployees", inputs: { greeting: "Hello", dry_run: "1" } },
             linked_cell_ids: %w[linked-x]
           }

      expect(DataDrip::ScriptRun.last!.dispatches.map(&:cell_id)).to eq(%w[linked-x])
    end
  end
end
