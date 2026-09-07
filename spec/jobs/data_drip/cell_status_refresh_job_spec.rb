# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::CellStatusRefreshJob do
  let(:backfiller) { User.create!(name: "Suzie") }

  before { configure_multi_cell! }

  let!(:run) do
    DataDrip::BackfillRun.create!(
      backfill_class_name: "AddRoleToEmployee",
      batch_size: 100,
      start_at: 1.hour.from_now,
      backfiller: backfiller,
      group_uuid: "g-1"
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

  it "caches what each cell reports onto its dispatch row" do
    stub_request(:get, cell_api_url("cell-b", "/v1/groups/g-1?target_cell_id=cell-b"))
      .to_return(
        status: 200,
        body: { cell_id: "cell-b", runs: [ { "id" => 77, "status" => "running" } ] }.to_json
      )

    described_class.perform_now("g-1")

    expect(dispatch.reload.last_status).to eq("running")
  end

  it "records an unreachable cell without discarding its last snapshot" do
    dispatch.update!(
      last_status: "running",
      last_synced_at: 10.minutes.ago,
      last_snapshot: { "id" => 77, "status" => "running" }
    )
    stub_request(:get, %r{cell-b\.example\.com}).to_timeout

    described_class.perform_now("g-1")

    dispatch.reload
    expect(dispatch).to be_unreachable
    expect(dispatch.last_status).to eq("running")
  end

  it "finds the coordinator run for a script group too" do
    run.destroy!
    script =
      DataDrip::ScriptRun.create!(
        script_class_name: "GreetEmployees",
        inputs: { "greeting" => "Hi", "dry_run" => true },
        backfiller: backfiller,
        group_uuid: "g-1"
      )
    dispatch.update!(runnable_type: :script)
    stub_request(:get, %r{cell-b\.example\.com})
      .to_return(
        status: 200,
        body: {
          cell_id: "cell-b",
          runs: [ { "id" => 77, "type" => "script", "status" => "completed" } ]
        }.to_json
      )

    described_class.perform_now("g-1")

    expect(script.reload.group_uuid).to eq("g-1")
    expect(dispatch.reload.last_status).to eq("completed")
  end

  # The group may have been deleted between the page render that asked for a
  # refresh and the job running.
  it "does nothing for a group that no longer exists" do
    run.destroy!

    expect { described_class.perform_now("g-1") }.not_to raise_error
    expect(a_request(:any, %r{cell-b\.example\.com})).not_to have_been_made
  end

  # A remote cell's own copy of the run must never be mistaken for the
  # coordinator: it has no dispatch records and asking it to refresh would be
  # asking a cell about itself.
  it "ignores a remote-origin run with the same group" do
    run.destroy!
    DataDrip::BackfillRun.create!(
      backfill_class_name: "AddRoleToEmployee",
      batch_size: 100,
      start_at: 1.hour.from_now,
      backfiller_id: backfiller.id,
      backfiller_name: "Suzie",
      group_uuid: "g-1",
      origin: :remote,
      origin_cell_id: "cell-z"
    )

    described_class.perform_now("g-1")

    expect(a_request(:any, %r{cell-b\.example\.com})).not_to have_been_made
  end
end
