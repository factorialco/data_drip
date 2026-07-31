# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::GroupCreator do
  include ActiveJob::TestHelper

  let!(:backfiller) { User.create!(name: "Suzie") }

  def build_run
    DataDrip::BackfillRun.new(
      backfill_class_name: "AddRoleToEmployee",
      batch_size: 100,
      start_at: 1.hour.from_now,
      backfiller: backfiller
    )
  end

  context "in single-cell mode" do
    it "saves the run without any group or dispatches" do
      run = build_run

      expect(described_class.call(run: run, remote_cell_ids: [])).to be(true)

      expect(run).to be_persisted
      expect(run.group_uuid).to be_nil
      expect(run.cell_id).to be_nil
      expect(DataDrip::CellDispatch.count).to eq(0)
    end
  end

  context "in multi-cell mode" do
    before { configure_multi_cell! }

    it "assigns a group, stamps the cell, and creates one dispatch per remote cell" do
      run = build_run

      result =
        described_class.call(run: run, remote_cell_ids: %w[cell-b cell-c])

      expect(result).to be(true)
      expect(run.group_uuid).to be_present
      expect(run.cell_id).to eq("cell-a")
      expect(run.origin).to eq("local")
      expect(run.multi_cell_group?).to be(true)

      dispatches = DataDrip::CellDispatch.order(:cell_id)
      expect(dispatches.map(&:cell_id)).to eq(%w[cell-b cell-c])
      expect(dispatches).to all(be_pending)
      expect(dispatches).to all(be_backfill)

      payload = dispatches.first.payload
      expect(payload["group_uuid"]).to eq(run.group_uuid)
      expect(payload["origin_cell_id"]).to eq("cell-a")
      expect(payload["backfill_class_name"]).to eq("AddRoleToEmployee")
      expect(payload["batch_size"]).to eq(100)
      expect(payload["backfiller_id"]).to eq(backfiller.id)
      expect(payload["backfiller_name"]).to eq("Suzie")
      expect(Time.iso8601(payload["start_at"])).to be_within(1.second).of(run.start_at)

      expect(enqueued_jobs.count { |job| job[:job] == DataDrip::CellDispatcherJob }).to eq(2)
    end

    it "ignores unknown cells and never dispatches to the current cell" do
      run = build_run

      described_class.call(
        run: run,
        remote_cell_ids: %w[cell-a cell-b nope]
      )

      expect(DataDrip::CellDispatch.pluck(:cell_id)).to eq(%w[cell-b])
    end

    it "creates no dispatches for a local-only run" do
      run = build_run

      described_class.call(run: run, remote_cell_ids: [])

      expect(run.group_uuid).to be_present
      expect(DataDrip::CellDispatch.count).to eq(0)
      expect(run.multi_cell_group?).to be(false)
    end

    it "creates nothing when the run is invalid" do
      run = build_run
      run.backfill_class_name = nil

      expect(
        described_class.call(run: run, remote_cell_ids: %w[cell-b])
      ).to be(false)

      expect(run).not_to be_persisted
      expect(DataDrip::CellDispatch.count).to eq(0)
    end

    it "builds a script payload for script runs" do
      run =
        DataDrip::ScriptRun.new(
          script_class_name: "GreetEmployees",
          backfiller: backfiller,
          inputs: { "greeting" => "Hi", "dry_run" => true }
        )

      described_class.call(run: run, remote_cell_ids: %w[cell-b])

      dispatch = DataDrip::CellDispatch.last!
      expect(dispatch).to be_script
      expect(dispatch.payload["script_class_name"]).to eq("GreetEmployees")
      expect(dispatch.payload).to have_key("inputs")
      expect(dispatch.payload).not_to have_key("batch_size")
    end
  end
end
