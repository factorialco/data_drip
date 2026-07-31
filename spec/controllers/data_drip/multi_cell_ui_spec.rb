# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::BackfillRunsController, type: :controller do
  routes { DataDrip::Engine.routes }

  let!(:backfiller) { User.create!(name: "Suzie") }

  let(:valid_attributes) do
    {
      backfill_class_name: "AddRoleToEmployee",
      batch_size: 100,
      start_at: 1.hour.from_now
    }
  end

  before do
    Employee.create!(name: "Pepe", role: nil, age: 25)
    configure_multi_cell!
  end

  describe "POST #create with cell targeting" do
    it "fans out to every remote cell by default" do
      post :create, params: { backfill_run: valid_attributes }

      run = DataDrip::BackfillRun.last!
      expect(run.group_uuid).to be_present
      expect(run.cell_id).to eq("cell-a")
      expect(run.dispatches.map(&:cell_id)).to eq(%w[cell-b cell-c])
    end

    it "creates no dispatches for 'only this cell'" do
      post :create,
           params: { backfill_run: valid_attributes, cell_scope: "local" }

      run = DataDrip::BackfillRun.last!
      expect(run.dispatches).to be_empty
    end

    it "honors a custom subset of cells" do
      post :create,
           params: {
             backfill_run: valid_attributes,
             cell_scope: "custom",
             target_cell_ids: %w[cell-c]
           }

      run = DataDrip::BackfillRun.last!
      expect(run.dispatches.map(&:cell_id)).to eq(%w[cell-c])
    end
  end

  describe "GET #new" do
    render_views

    it "renders the cell targeting section in multi-cell mode" do
      get :new

      expect(response.body).to include("Where to run")
      expect(response.body).to include("cell-b")
      expect(response.body).to include("cell-c")
    end

    it "hides the cell targeting section in single-cell mode" do
      reset_multi_cell_config!

      get :new

      expect(response.body).not_to include("Where to run")
    end
  end

  describe "GET #show with a multi-cell group" do
    render_views

    let!(:run) do
      DataDrip::BackfillRun.create!(
        valid_attributes.merge(backfiller: backfiller, group_uuid: "g-1")
      )
    end

    it "renders per-cell cards from the fetched snapshots" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77
      )
      stub_request(
        :get,
        cell_api_url("cell-b", "/v1/groups/g-1?target_cell_id=cell-b")
      ).to_return(
        status: 200,
        body: {
          cell_id: "cell-b",
          runs: [
            {
              "id" => 77,
              "type" => "backfill",
              "status" => "running",
              "terminal" => false,
              "progress_percent" => 40,
              "processed_count" => 40,
              "total_count" => 100,
              "failed_batches_count" => 0
            }
          ]
        }.to_json
      )

      get :show, params: { id: run.id }

      expect(response.body).to include("Cells")
      expect(response.body).to include("cell-b")
      expect(response.body).to include("this cell")
      expect(response.body).to include("Running")
    end

    it "renders an unreachable card when the cell cannot be reached" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77
      )
      stub_request(:get, %r{cell-b\.example\.com}).to_timeout

      get :show, params: { id: run.id }

      expect(response.body).to include("Unreachable")
    end

    it "renders a failed dispatch with its error and a retry button" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :failed,
        error_message: "Backfill class not found in this cell"
      )

      get :show, params: { id: run.id }

      expect(response.body).to include("Dispatch failed")
      expect(response.body).to include("Backfill class not found in this cell")
      expect(response.body).to include("Retry dispatch")
    end

    it "renders no cells section for single-cell runs" do
      # A different amount_of_elements sidesteps the duplicate-active-run guard.
      plain =
        DataDrip::BackfillRun.create!(
          valid_attributes.merge(backfiller: backfiller, amount_of_elements: 3)
        )

      get :show, params: { id: plain.id }

      expect(response.body).not_to include(">Cells<")
    end
  end

  describe "GET #updates with a multi-cell group" do
    render_views

    let!(:run) do
      DataDrip::BackfillRun.create!(
        valid_attributes.merge(backfiller: backfiller, group_uuid: "g-1")
      )
    end

    it "reports cells_active while a remote leg is still running" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77
      )
      stub_request(
        :get,
        cell_api_url("cell-b", "/v1/groups/g-1?target_cell_id=cell-b")
      ).to_return(
        status: 200,
        body: {
          cell_id: "cell-b",
          runs: [ { "id" => 77, "type" => "backfill", "status" => "running", "terminal" => false } ]
        }.to_json
      )

      get :updates, params: { id: run.id }

      body = response.parsed_body
      expect(body["cells_active"]).to be(true)
      expect(body["cells_html"]).to include("cell-b")
    end

    it "reports cells inactive once every leg is terminal" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77
      )
      stub_request(
        :get,
        cell_api_url("cell-b", "/v1/groups/g-1?target_cell_id=cell-b")
      ).to_return(
        status: 200,
        body: {
          cell_id: "cell-b",
          runs: [ { "id" => 77, "type" => "backfill", "status" => "completed", "terminal" => true } ]
        }.to_json
      )

      get :updates, params: { id: run.id }

      expect(response.parsed_body["cells_active"]).to be(false)
    end

    it "sends no cells payload for single-cell runs" do
      # A different amount_of_elements sidesteps the duplicate-active-run guard.
      plain =
        DataDrip::BackfillRun.create!(
          valid_attributes.merge(backfiller: backfiller, amount_of_elements: 3)
        )

      get :updates, params: { id: plain.id }

      body = response.parsed_body
      expect(body["cells_active"]).to be(false)
      expect(body["cells_html"]).to be_nil
    end
  end

  describe "POST #retry_dispatch" do
    let!(:run) do
      DataDrip::BackfillRun.create!(
        valid_attributes.merge(backfiller: backfiller, group_uuid: "g-1")
      )
    end

    let!(:dispatch) do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :failed,
        error_message: "boom"
      )
    end

    it "re-enqueues a failed dispatch" do
      post :retry_dispatch, params: { id: run.id, cell_id: "cell-b" }

      expect(dispatch.reload).to be_pending
      expect(flash[:notice]).to match(/re-enqueued/)
    end

    it "refuses for a non-owner" do
      run.update_column(:backfiller_id, backfiller.id + 1)

      post :retry_dispatch, params: { id: run.id, cell_id: "cell-b" }

      expect(dispatch.reload).to be_failed
      expect(flash[:alert]).to match(/runs you created/)
    end

    it "reports when there is no failed dispatch for the cell" do
      post :retry_dispatch, params: { id: run.id, cell_id: "cell-c" }

      expect(flash[:alert]).to match(/No failed dispatch/)
    end
  end

  describe "POST #stop across cells" do
    let!(:run) do
      DataDrip::BackfillRun.create!(
        valid_attributes.merge(
          backfiller: backfiller,
          group_uuid: "g-1",
          start_at: Time.current
        )
      )
    end

    let!(:dispatch) do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77
      )
    end

    it "stops the local run and fans the stop out to dispatched cells" do
      run.running!
      stop_stub =
        stub_request(:post, cell_api_url("cell-b", "/v1/backfill_runs/77/stop"))
          .to_return(status: 200, body: { id: 77, status: "stopped" }.to_json)

      post :stop, params: { id: run.id }

      expect(run.reload).to be_stopped
      expect(stop_stub).to have_been_requested
      expect(flash[:notice]).to match(/stopped/)
    end

    it "stops a single remote leg when a cell_id is given" do
      stop_stub =
        stub_request(:post, cell_api_url("cell-b", "/v1/backfill_runs/77/stop"))
          .to_return(status: 200, body: { id: 77, status: "stopped" }.to_json)

      post :stop, params: { id: run.id, cell_id: "cell-b" }

      expect(stop_stub).to have_been_requested
      expect(run.reload).not_to be_stopped
      expect(flash[:notice]).to match(/stopped in cell-b/i)
    end

    it "reports an unreachable cell instead of failing" do
      run.running!
      stub_request(:post, cell_api_url("cell-b", "/v1/backfill_runs/77/stop"))
        .to_timeout

      post :stop, params: { id: run.id }

      expect(run.reload).to be_stopped
      expect(flash[:notice]).to match(/did not acknowledge/)
    end
  end

  describe "DELETE #destroy across cells" do
    let!(:run) do
      DataDrip::BackfillRun.create!(
        valid_attributes.merge(backfiller: backfiller, group_uuid: "g-1")
      )
    end

    let!(:dispatch) do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77
      )
    end

    it "deletes the local run, its dispatches, and asks remote cells to delete" do
      delete_stub =
        stub_request(:delete, cell_api_url("cell-b", "/v1/backfill_runs/77"))
          .to_return(status: 204, body: "")

      delete :destroy, params: { id: run.id }

      expect(delete_stub).to have_been_requested
      expect(DataDrip::BackfillRun.exists?(run.id)).to be(false)
      expect(DataDrip::CellDispatch.count).to eq(0)
    end

    it "notes remote legs that already ran and were kept" do
      stub_request(:delete, cell_api_url("cell-b", "/v1/backfill_runs/77"))
        .to_return(status: 409, body: { error: "already_run" }.to_json)

      delete :destroy, params: { id: run.id }

      expect(DataDrip::BackfillRun.exists?(run.id)).to be(false)
      expect(flash[:notice]).to match(/kept as history/)
    end
  end
end
