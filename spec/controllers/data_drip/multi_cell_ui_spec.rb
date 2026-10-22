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
    # The default must be the single-cell run DataDrip has always created, so
    # nothing reaches another cell unless the operator asks for it.
    it "runs only in this cell, as a plain run, unless asked otherwise" do
      post :create, params: { backfill_run: valid_attributes }

      run = DataDrip::BackfillRun.last!
      expect(run.group_uuid).to be_nil
      expect(run.cell_id).to be_nil
      expect(run).not_to be_multi_cell_run
      expect(DataDrip::CellDispatch.count).to eq(0)
    end

    it "ignores cells picked while the box is unticked" do
      post :create, params: { backfill_run: valid_attributes, target_cell_ids: %w[cell-b] }

      expect(DataDrip::BackfillRun.last!.group_uuid).to be_nil
      expect(DataDrip::CellDispatch.count).to eq(0)
    end

    it "fans out to the picked cells when asked to run in several" do
      post :create,
           params: {
             backfill_run: valid_attributes,
             multi_cell: "1",
             target_cell_ids: %w[cell-b cell-c]
           }

      run = DataDrip::BackfillRun.last!
      expect(run.group_uuid).to be_present
      expect(run.cell_id).to eq("cell-a")
      expect(run.dispatches.map(&:cell_id)).to eq(%w[cell-b cell-c])
    end

    it "honors a subset of cells" do
      post :create,
           params: {
             backfill_run: valid_attributes,
             multi_cell: "1",
             target_cell_ids: %w[cell-c]
           }

      expect(DataDrip::BackfillRun.last!.dispatches.map(&:cell_id)).to eq(%w[cell-c])
    end

    it "refuses to run in several cells without another cell picked" do
      post :create, params: { backfill_run: valid_attributes, multi_cell: "1" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(DataDrip::BackfillRun.count).to eq(0)
    end

    it "never dispatches when multi-cell is not configured, whatever the form says" do
      reset_multi_cell_config!

      post :create,
           params: {
             backfill_run: valid_attributes,
             multi_cell: "1",
             target_cell_ids: %w[cell-b]
           }

      expect(DataDrip::BackfillRun.last!.group_uuid).to be_nil
      expect(DataDrip::CellDispatch.count).to eq(0)
    end
  end

  describe "GET #new" do
    render_views

    def multi_cell_box
      Nokogiri::HTML(response.body).at_css("input[type=checkbox][name=multi_cell]")
    end

    it "offers running in several cells, unticked, in multi-cell mode" do
      get :new

      expect(multi_cell_box).to be_present
      expect(multi_cell_box["checked"]).to be_nil
      expect(response.body).to include("cell-b")
      expect(response.body).to include("cell-c")
    end

    it "hides the cell targeting section in single-cell mode" do
      reset_multi_cell_config!

      get :new

      expect(multi_cell_box).to be_nil
    end

    it "leaves the box unticked when running a multi-cell run again" do
      source =
        DataDrip::BackfillRun.create!(
          valid_attributes.merge(backfiller: backfiller, group_uuid: "g-source", cell_id: "cell-a")
        )
      DataDrip::CellDispatch.create!(
        group_uuid: "g-source",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched
      )

      get :new, params: { source_run_id: source.id }

      expect(multi_cell_box["checked"]).to be_nil
    end
  end

  # Multi-cell mode is configured here, but these runs were not opted in to
  # several cells: they must behave exactly as single-cell runs always have.
  describe "a single-cell run while multi-cell is configured" do
    let!(:run) do
      DataDrip::BackfillRun.create!(valid_attributes.merge(backfiller: backfiller))
    end

    it "cannot be stopped before it starts, as before" do
      expect(run.reload).to be_enqueued

      post :stop, params: { id: run.id }

      expect(run.reload).to be_enqueued
      expect(flash[:alert]).to eq("Backfill run is not currently running.")
    end

    it "stops while running, with no cross-cell request" do
      run.running!

      post :stop, params: { id: run.id }

      expect(run.reload).to be_stopped
      expect(flash[:notice]).to eq("Backfill run has been stopped.")
      expect(a_request(:any, /example\.com/)).not_to have_been_made
    end

    it "lets anyone retry its failed batches, as before" do
      other = User.create!(name: "Someone")
      allow(controller).to receive(:find_current_backfiller).and_return(other)
      DataDrip::BackfillRunBatch.create!(
        backfill_run: run,
        status: :failed,
        batch_size: 100,
        start_id: 1,
        finish_id: 100
      )
      run.update!(status: :failed, total_count: 100)

      post :retry_failed_batches, params: { id: run.id }

      expect(flash[:notice]).to eq("Re-enqueued 1 failed batch.")
      expect(run.reload).to be_running
    end

    it "is deleted with no cross-cell request" do
      delete :destroy, params: { id: run.id }

      expect(DataDrip::BackfillRun.exists?(run.id)).to be(false)
      expect(flash[:notice]).to eq("Backfill run has been deleted.")
      expect(a_request(:any, /example\.com/)).not_to have_been_made
    end
  end

  describe "GET #show with a multi-cell group" do
    render_views

    let!(:run) do
      DataDrip::BackfillRun.create!(
        valid_attributes.merge(backfiller: backfiller, group_uuid: "g-1")
      )
    end

    it "renders per-cell cards from the cached snapshots" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77,
        last_status: "running",
        last_synced_at: Time.current,
        last_snapshot: {
          "id" => 77,
          "type" => "backfill",
          "status" => "running",
          "progress_percent" => 40,
          "processed_count" => 40,
          "total_count" => 100,
          "failed_batches_count" => 0
        }
      )

      get :show, params: { id: run.id }

      expect(response.body).to include("Cells")
      expect(response.body).to include("cell-b")
      expect(response.body).to include("this cell")
      expect(response.body).to include("Running")
    end

    it "offers to stop the group while another cell is still running it" do
      run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77,
        last_status: "running",
        last_synced_at: Time.current,
        last_snapshot: { "id" => 77, "type" => "backfill", "status" => "running" }
      )

      get :show, params: { id: run.id }

      expect(response.body).to include("Stop run")
    end

    it "tells a leg deleted in its own cell apart from one still running" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77,
        last_status: "deleted",
        last_synced_at: Time.current,
        last_snapshot: { "id" => 77, "type" => "backfill", "status" => "pending" }
      )

      get :show, params: { id: run.id }

      expect(response.body).to include("Deleted")
      expect(response.body).to include("deleted there before it ran")
      expect(response.body).not_to include("Stop this run in cell-b")
    end

    # Rendering a page must not wait on other cells, and must not write: hosts
    # routinely route GETs to a read replica.
    it "makes no cross-cell request, and asks a job to catch the group up" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77
      )

      expect { get :show, params: { id: run.id } }.to have_enqueued_job(
        DataDrip::CellStatusRefreshJob
      ).with("g-1")

      expect(a_request(:any, %r{cell-b\.example\.com})).not_to have_been_made
    end

    # Several people watching the same run must not each enqueue the same
    # cross-cell fan-out on every poll.
    it "asks for only one refresh per freshness window" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77
      )

      expect do
        get :show, params: { id: run.id }
        get :show, params: { id: run.id }
      end.to have_enqueued_job(DataDrip::CellStatusRefreshJob).once
    end

    # Deduplication needs a shared cache; without one the page still works, it
    # just asks every time (which is what the test app's null store does).
    it "still renders and refreshes with no usable cache store" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77
      )

      expect { get :show, params: { id: run.id } }.to have_enqueued_job(
        DataDrip::CellStatusRefreshJob
      )
      expect(response).to have_http_status(:ok)
    end

    it "does not ask for a refresh when every leg is settled" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77,
        last_status: "completed",
        last_synced_at: 1.hour.ago
      )

      expect { get :show, params: { id: run.id } }.not_to have_enqueued_job(
        DataDrip::CellStatusRefreshJob
      )
    end

    it "renders a delivered leg that has not reported yet" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77
      )

      get :show, params: { id: run.id }

      expect(response.body).to include("waiting for this cell")
    end

    it "renders an unreachable card, keeping the state that cell last reported" do
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77,
        last_status: "running",
        last_synced_at: 10.minutes.ago,
        last_snapshot: { "id" => 77, "type" => "backfill", "status" => "running" },
        unreachable_since: 5.minutes.ago
      )

      get :show, params: { id: run.id }

      expect(response.body).to include("Cell unreachable")
      expect(response.body).to include("Running")
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

    def leg_reported(cell_id, status:, remote_run_id: 77)
      dispatch_to(cell_id, remote_run_id: remote_run_id).update!(
        last_status: status,
        last_synced_at: Time.current,
        last_snapshot: {
          "id" => remote_run_id,
          "type" => "backfill",
          "status" => status
        }
      )
    end

    it "stays active while a remote leg is still running, even once this cell finished" do
      run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])
      leg_reported("cell-b", status: "running")

      get :updates, params: { id: run.id }

      body = response.parsed_body
      expect(body["active"]).to be(true)
      expect(body["cells_html"]).to include("cell-b")
    end

    # The whole point of a group status: a coordinator run that completed must
    # not report the group as completed while another cell is working or broken.
    it "reports the worst status across the group, not this cell's" do
      run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])
      leg_reported("cell-b", status: "failed")

      get :updates, params: { id: run.id }

      body = response.parsed_body
      expect(body["status"]).to eq("failed")
      expect(body["status_html"]).to include("Failed")
    end

    it "goes inactive once every leg is terminal" do
      run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])
      leg_reported("cell-b", status: "completed")

      get :updates, params: { id: run.id }

      body = response.parsed_body
      expect(body["active"]).to be(false)
      expect(body["status"]).to eq("completed")
    end

    # Polling must stay cheap: it reads the cached snapshots and lets a job do
    # any fetching, so a poll never blocks on another cell.
    it "makes no cross-cell request while polling" do
      run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])
      dispatch_to("cell-b")

      get :updates, params: { id: run.id }

      expect(a_request(:any, %r{cell-b\.example\.com})).not_to have_been_made
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

    # The local run finished first; another cell is still working. The header's
    # stop must still reach it.
    it "stops the remote legs once this cell's own run has finished" do
      run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])
      dispatch.update!(last_status: "running", last_synced_at: Time.current)
      stop_stub =
        stub_request(:post, cell_api_url("cell-b", "/v1/backfill_runs/77/stop"))
          .to_return(status: 200, body: { id: 77, status: "stopped" }.to_json)

      post :stop, params: { id: run.id }

      expect(stop_stub).to have_been_requested
      expect(run.reload).to be_completed
      expect(flash[:alert]).to be_nil
      expect(flash[:notice]).to match(/acknowledged/)
    end

    it "refuses when neither this cell nor any other is running the group" do
      run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])
      dispatch.update!(last_status: "completed", last_synced_at: Time.current)

      post :stop, params: { id: run.id }

      expect(flash[:alert]).to match(/not currently running/)
      expect(a_request(:post, %r{cell-b\.example\.com})).not_to have_been_made
    end

    # The remote cell's audit trail must name who stopped its leg.
    it "tells each cell who is acting" do
      run.running!
      stop_stub =
        stub_request(:post, cell_api_url("cell-b", "/v1/backfill_runs/77/stop"))
          .with { |request| JSON.parse(request.body)["acting_backfiller_id"] == backfiller.id }
          .to_return(status: 200, body: { id: 77, status: "stopped" }.to_json)

      post :stop, params: { id: run.id }

      expect(stop_stub).to have_been_requested
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

    it "records what each cell reports once it stopped" do
      run.running!
      dispatch.update!(last_status: "running", last_synced_at: 1.minute.ago)
      stub_request(:post, cell_api_url("cell-b", "/v1/backfill_runs/77/stop"))
        .to_return(status: 200, body: { id: 77, status: "stopped" }.to_json)

      post :stop, params: { id: run.id }

      expect(dispatch.reload.last_status).to eq("stopped")
    end

    # A run scheduled for later, here or in another cell, would otherwise
    # start after the group was stopped.
    it "stops a group none of whose runs has started yet" do
      expect(run.reload).to be_enqueued
      dispatch.update!(last_status: "enqueued", last_synced_at: Time.current)
      stop_stub =
        stub_request(:post, cell_api_url("cell-b", "/v1/backfill_runs/77/stop"))
          .to_return(status: 200, body: { id: 77, status: "stopped" }.to_json)

      post :stop, params: { id: run.id }

      expect(run.reload).to be_stopped
      expect(stop_stub).to have_been_requested
    end

    it "cancels a dispatch that has not been delivered yet" do
      run.running!
      dispatch.update!(status: :pending, remote_run_id: nil)

      post :stop, params: { id: run.id }

      expect(dispatch.reload).to be_cancelled
      expect(a_request(:post, %r{cell-b\.example\.com})).not_to have_been_made
    end

    # The dispatch was marked failed after a timeout, but the cell had
    # committed the run: it is found and stopped, not left to run alone.
    it "stops the copy a failed dispatch turns out to have landed" do
      run.running!
      dispatch.update!(status: :failed, remote_run_id: nil)
      stub_request(:get, cell_api_url("cell-b", "/v1/groups/g-1?target_cell_id=cell-b"))
        .to_return(status: 200, body: { runs: [ { id: 88, status: "enqueued" } ] }.to_json)
      stop_stub =
        stub_request(:post, cell_api_url("cell-b", "/v1/backfill_runs/88/stop"))
          .to_return(status: 200, body: { id: 88, status: "stopped" }.to_json)

      post :stop, params: { id: run.id }

      expect(stop_stub).to have_been_requested
      expect(dispatch.reload).to be_cancelled
      expect(flash[:notice]).to match(/acknowledged/)
    end
  end

  describe "POST #retry_failed_batches for a remote leg" do
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
        remote_run_id: 77,
        last_status: "failed",
        last_synced_at: 1.minute.ago
      )
    end

    # A failed leg is settled, so nothing would ask the cell about it again:
    # the card would keep showing "failed" while the leg runs.
    it "records the leg as running again, so it is polled until it settles" do
      stub_request(:post, cell_api_url("cell-b", "/v1/backfill_runs/77/retry_failed_batches"))
        .to_return(status: 200, body: { id: 77, status: "running" }.to_json)

      post :retry_failed_batches, params: { id: run.id, cell_id: "cell-b" }

      expect(dispatch.reload.last_status).to eq("running")
      expect(run.group).to be_active
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

    # A failed dispatch may still have landed: the cell can commit the run and
    # then time out answering. Deleting must find and remove that copy.
    context "with a dispatch that never confirmed delivery" do
      let!(:unconfirmed) do
        DataDrip::CellDispatch.create!(
          group_uuid: "g-1",
          cell_id: "cell-c",
          runnable_type: :backfill,
          status: :failed,
          error_message: "Net::ReadTimeout"
        )
      end

      before do
        stub_request(:delete, cell_api_url("cell-b", "/v1/backfill_runs/77"))
          .to_return(status: 204, body: "")
      end

      def stub_cell_c_group(runs)
        stub_request(:get, cell_api_url("cell-c", "/v1/groups/g-1?target_cell_id=cell-c"))
          .to_return(status: 200, body: { cell_id: "cell-c", runs: runs }.to_json)
      end

      it "deletes the copy the cell turns out to hold" do
        stub_cell_c_group([ { "id" => 88, "status" => "enqueued" } ])
        delete_stub =
          stub_request(:delete, cell_api_url("cell-c", "/v1/backfill_runs/88"))
            .to_return(status: 204, body: "")

        delete :destroy, params: { id: run.id }

        expect(delete_stub).to have_been_requested
        expect(DataDrip::BackfillRun.exists?(run.id)).to be(false)
      end

      it "deletes the run when the cell holds no copy" do
        stub_cell_c_group([])

        delete :destroy, params: { id: run.id }

        expect(DataDrip::BackfillRun.exists?(run.id)).to be(false)
        expect(DataDrip::CellDispatch.count).to eq(0)
      end

      it "refuses to delete when the cell cannot say whether it holds a copy" do
        stub_request(:get, %r{cell-c\.example\.com}).to_timeout

        delete :destroy, params: { id: run.id }

        expect(DataDrip::BackfillRun.exists?(run.id)).to be(true)
        expect(DataDrip::CellDispatch.exists?(unconfirmed.id)).to be(true)
        expect(flash[:alert]).to match(/not deleted.*cell-c/)
      end
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

    context "on its page" do
      render_views

      it "offers the stop the controller allows" do
        remote_run.update_column(:status, DataDrip::BackfillRun.statuses[:running])

        get :show, params: { id: remote_run.id }

        expect(response.body).to include("Stop run")
      end

      it "offers the delete the controller allows" do
        get :show, params: { id: remote_run.id }

        expect(response.body).to include("Delete run")
      end
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
