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

    def dispatch_to(cell_id, remote_run_id: 77)
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: cell_id,
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: remote_run_id
      )
    end

    def stub_leg(cell_id, status:, remote_run_id: 77)
      stub_request(
        :get,
        cell_api_url(cell_id, "/v1/groups/g-1?target_cell_id=#{cell_id}")
      ).to_return(
        status: 200,
        body: {
          cell_id: cell_id,
          runs: [ { "id" => remote_run_id, "type" => "backfill", "status" => status } ]
        }.to_json
      )
    end

    it "stays active while a remote leg is still running, even once this cell finished" do
      run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])
      dispatch_to("cell-b")
      stub_leg("cell-b", status: "running")

      get :updates, params: { id: run.id }

      body = response.parsed_body
      expect(body["active"]).to be(true)
      expect(body["cells_html"]).to include("cell-b")
    end

    # The whole point of a group status: a coordinator run that completed must
    # not report the group as completed while another cell is working or broken.
    it "reports the worst status across the group, not this cell's" do
      run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])
      dispatch_to("cell-b")
      stub_leg("cell-b", status: "failed")

      get :updates, params: { id: run.id }

      body = response.parsed_body
      expect(body["status"]).to eq("failed")
      expect(body["status_html"]).to include("Failed")
    end

    it "goes inactive once every leg is terminal" do
      run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])
      dispatch_to("cell-b")
      stub_leg("cell-b", status: "completed")

      get :updates, params: { id: run.id }

      body = response.parsed_body
      expect(body["active"]).to be(false)
      expect(body["status"]).to eq("completed")
    end

    # A leg that reached a terminal status can never change, so its snapshot is
    # cached on the dispatch row and the cell is never asked again.
    it "serves a settled leg from cache instead of re-fetching it" do
      run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])
      dispatch_to("cell-b")
      request_stub = stub_leg("cell-b", status: "completed")

      get :updates, params: { id: run.id }
      get :updates, params: { id: run.id }

      expect(request_stub).to have_been_requested.once
      expect(response.parsed_body["cells_html"]).to include("cell-b")
    end

    it "sends no cells payload for single-cell runs" do
      # A different amount_of_elements sidesteps the duplicate-active-run guard.
      plain =
        DataDrip::BackfillRun.create!(
          valid_attributes.merge(backfiller: backfiller, amount_of_elements: 3)
        )

      get :updates, params: { id: plain.id }

      body = response.parsed_body
      expect(body["active"]).to be(true)
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

    # The remote leg is enqueued in its own cell and will run. Destroying the
    # coordinator's run and its dispatch rows would erase the only place that
    # leg is visible or stoppable from, so an unacknowledged delete is refused.
    it "refuses to delete while a cell has not acknowledged" do
      stub_request(:delete, cell_api_url("cell-b", "/v1/backfill_runs/77"))
        .to_timeout

      delete :destroy, params: { id: run.id }

      expect(DataDrip::BackfillRun.exists?(run.id)).to be(true)
      expect(DataDrip::CellDispatch.exists?(dispatch.id)).to be(true)
      expect(flash[:alert]).to match(/not deleted/)
      expect(response).to redirect_to(
        DataDrip::Engine.routes.url_helpers.backfill_run_path(run)
      )
    end

    it "refuses to delete when a cell rejects the delete" do
      stub_request(:delete, cell_api_url("cell-b", "/v1/backfill_runs/77"))
        .to_return(status: 500, body: "")

      delete :destroy, params: { id: run.id }

      expect(DataDrip::BackfillRun.exists?(run.id)).to be(true)
      expect(flash[:alert]).to match(/not deleted/)
    end
  end

  describe "fanned-in runs in the cell executing them" do
    # backfiller ids are cell-scoped, so a run fanned in from another cell
    # matches no local backfiller and would be unstoppable here on ownership
    # grounds — from the only cell that can actually stop it.
    let!(:remote_run) do
      DataDrip::BackfillRun.create!(
        valid_attributes.merge(
          backfiller_id: 999_999,
          backfiller_name: "Someone Else",
          group_uuid: "g-remote",
          origin: :remote,
          origin_cell_id: "cell-b"
        )
      )
    end

    it "may be stopped by any operator in this cell" do
      remote_run.update_column(:status, DataDrip::BackfillRun.statuses[:running])

      post :stop, params: { id: remote_run.id }

      expect(remote_run.reload).to be_stopped
      expect(flash[:alert]).to be_nil
    end

    it "may be deleted by any operator in this cell" do
      delete :destroy, params: { id: remote_run.id }

      expect(DataDrip::BackfillRun.exists?(remote_run.id)).to be(false)
    end

    it "still refuses a local run the operator does not own" do
      other = User.create!(name: "Someone")
      mine =
        DataDrip::BackfillRun.create!(
          valid_attributes.merge(backfiller: other, amount_of_elements: 7)
        )
      mine.update_column(:status, DataDrip::BackfillRun.statuses[:running])

      post :stop, params: { id: mine.id }

      expect(mine.reload).to be_running
      expect(flash[:alert]).to match(/only stop backfill runs you created/)
    end
  end
end
