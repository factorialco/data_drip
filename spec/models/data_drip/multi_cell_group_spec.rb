# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::MultiCellGroup do
  let(:backfiller) { User.create!(name: "Suzie") }

  before { configure_multi_cell! }

  def build_run(status: :pending, group_uuid: "g-1", **overrides)
    run =
      DataDrip::BackfillRun.create!(
        {
          backfill_class_name: "AddRoleToEmployee",
          batch_size: 100,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          group_uuid: group_uuid
        }.merge(overrides)
      )
    run.update_column(:status, DataDrip::BackfillRun.statuses[status])
    run.reload
  end

  def dispatch(cell_id:, group_uuid: "g-1", **overrides)
    DataDrip::CellDispatch.create!(
      {
        group_uuid: group_uuid,
        cell_id: cell_id,
        runnable_type: :backfill,
        status: :dispatched,
        remote_run_id: 77
      }.merge(overrides)
    )
  end

  describe "#status" do
    it "is the run's own status when there are no other cells" do
      expect(described_class.new(run: build_run(status: :running)).status).to eq("running")
    end

    # A coordinator run that finished says nothing about the rest of the group.
    it "reports a still-running cell over a completed local run" do
      run = build_run(status: :completed)
      dispatch(cell_id: "cell-b", last_status: "running")

      expect(described_class.new(run: run).status).to eq("running")
    end

    it "reports a failed cell over everything else" do
      run = build_run(status: :running)
      dispatch(cell_id: "cell-b", last_status: "failed")

      expect(described_class.new(run: run).status).to eq("failed")
    end

    it "treats a dispatch that never landed as a failure of the group" do
      run = build_run(status: :completed)
      dispatch(cell_id: "cell-b", status: :failed, error_message: "no such class")

      expect(described_class.new(run: run).status).to eq("failed")
    end

    it "is completed only once every cell completed" do
      run = build_run(status: :completed)
      dispatch(cell_id: "cell-b", last_status: "completed")
      dispatch(cell_id: "cell-c", last_status: "completed")

      expect(described_class.new(run: run).status).to eq("completed")
    end

    # Cells report their own status, so one on a newer DataDrip can name a
    # status this version does not know. Never treat that as finished.
    it "surfaces a status it does not recognise instead of ignoring it" do
      run = build_run(status: :completed)
      dispatch(cell_id: "cell-b", last_status: "paused")

      expect(described_class.new(run: run).status).to eq("paused")
    end

    it "still lets an outright failure win over an unrecognised status" do
      run = build_run(status: :completed)
      dispatch(cell_id: "cell-b", last_status: "paused")
      dispatch(cell_id: "cell-c", last_status: "failed")

      expect(described_class.new(run: run).status).to eq("failed")
    end

    it "ignores a cell it has never reached rather than guessing" do
      run = build_run(status: :completed)
      dispatch(cell_id: "cell-b")

      group = described_class.new(run: run)
      expect(group.status).to eq("completed")
      expect(group.complete_picture?).to be(false)
      expect(group.active?).to be(true)
    end
  end

  describe "#active?" do
    it "is true while the local run is unfinished" do
      run = build_run(status: :running)
      dispatch(cell_id: "cell-b", last_status: "completed")

      expect(described_class.new(run: run)).to be_active
    end

    it "is true while a dispatch has not been delivered" do
      run = build_run(status: :completed)
      dispatch(cell_id: "cell-b", status: :pending)

      expect(described_class.new(run: run)).to be_active
    end

    # A failed dispatch waits for a human to press "Retry dispatch": nothing
    # will change on its own, so the page should stop polling for it.
    it "is false for a failed dispatch nobody has retried" do
      run = build_run(status: :completed)
      dispatch(cell_id: "cell-b", status: :failed, error_message: "nope")

      expect(described_class.new(run: run)).not_to be_active
    end

    it "is false once the local run and every leg are terminal" do
      run = build_run(status: :completed)
      dispatch(cell_id: "cell-b", last_status: "stopped")

      expect(described_class.new(run: run)).not_to be_active
    end
  end

  describe "#refresh!" do
    it "caches what each cell reports onto its dispatch row" do
      run = build_run(status: :completed)
      leg = dispatch(cell_id: "cell-b")
      stub_request(:get, cell_api_url("cell-b", "/v1/groups/g-1?target_cell_id=cell-b"))
        .to_return(
          status: 200,
          body: { cell_id: "cell-b", runs: [ { "id" => 77, "status" => "running" } ] }.to_json
        )

      described_class.new(run: run).refresh!

      expect(leg.reload.last_status).to eq("running")
      expect(leg.last_snapshot["id"]).to eq(77)
      expect(leg.last_synced_at).to be_present
    end

    it "never asks a cell whose run already reached a terminal status" do
      run = build_run(status: :completed)
      dispatch(cell_id: "cell-b", last_status: "completed", last_synced_at: 1.hour.ago)
      stubbed = stub_request(:get, %r{cell-b\.example\.com})

      described_class.new(run: run).refresh!

      expect(stubbed).not_to have_been_requested
    end

    # An unreachable cell must not blank the card out: the group keeps rendering
    # what that cell last said, flagged as stale.
    it "keeps the last snapshot when a cell becomes unreachable" do
      run = build_run(status: :completed)
      leg = dispatch(cell_id: "cell-b", last_status: "running",
                     last_snapshot: { "id" => 77, "status" => "running" })
      stub_request(:get, %r{cell-b\.example\.com}).to_timeout

      described_class.new(run: run).refresh!

      leg.reload
      expect(leg).to be_unreachable
      expect(leg.last_status).to eq("running")
      expect(leg.last_snapshot["status"]).to eq("running")
    end

    it "clears the unreachable flag once the cell answers again" do
      run = build_run(status: :completed)
      leg = dispatch(cell_id: "cell-b", last_status: "running", unreachable_since: 1.hour.ago)
      stub_request(:get, %r{cell-b\.example\.com})
        .to_return(
          status: 200,
          body: { cell_id: "cell-b", runs: [ { "id" => 77, "status" => "completed" } ] }.to_json
        )

      described_class.new(run: run).refresh!

      expect(leg.reload).not_to be_unreachable
    end
  end

  describe ".preload_for" do
    it "loads every run's dispatches in a single query" do
      first = build_run(group_uuid: "g-1")
      second = build_run(group_uuid: "g-2", amount_of_elements: 5)
      dispatch(cell_id: "cell-b", group_uuid: "g-1")
      dispatch(cell_id: "cell-b", group_uuid: "g-2")
      dispatch(cell_id: "cell-c", group_uuid: "g-2")

      queries = 0
      subscriber =
        ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          queries += 1 unless payload[:name].to_s.include?("SCHEMA")
        end

      groups = described_class.preload_for([ first, second ])

      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(queries).to eq(1)
      expect(groups[first.id].cells_count).to eq(2)
      expect(groups[second.id].cells_count).to eq(3)
    end

    it "skips runs that are not coordinating a group" do
      plain = build_run(group_uuid: nil)

      expect(described_class.preload_for([ plain ])).to eq({})
    end
  end
end
