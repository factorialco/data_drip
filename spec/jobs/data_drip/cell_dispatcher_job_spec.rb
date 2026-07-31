# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::CellDispatcherJob do
  before { configure_multi_cell! }

  let(:dispatch) do
    DataDrip::CellDispatch.create!(
      group_uuid: "group-1",
      cell_id: "cell-b",
      runnable_type: :backfill,
      status: :pending,
      payload: {
        "group_uuid" => "group-1",
        "origin_cell_id" => "cell-a",
        "backfill_class_name" => "AddRoleToEmployee",
        "options" => {},
        "batch_size" => 100,
        "start_at" => Time.current.utc.iso8601,
        "backfiller_id" => 1,
        "backfiller_name" => "Suzie"
      }
    )
  end

  let(:create_url) { cell_api_url("cell-b", "/v1/backfill_runs") }

  it "marks the dispatch as dispatched and records the remote run id" do
    stub =
      stub_request(:post, create_url)
        .with { |request| JSON.parse(request.body)["target_cell_id"] == "cell-b" }
        .to_return(status: 201, body: { id: 4242, status: "enqueued" }.to_json)

    described_class.perform_now(dispatch)

    expect(stub).to have_been_requested
    expect(dispatch.reload).to be_dispatched
    expect(dispatch.remote_run_id).to eq(4242)
    expect(dispatch.error_message).to be_nil
  end

  it "treats a 200 (idempotent redelivery) as dispatched" do
    stub_request(:post, create_url).to_return(
      status: 200,
      body: { id: 4242 }.to_json
    )

    described_class.perform_now(dispatch)

    expect(dispatch.reload).to be_dispatched
  end

  it "marks a 422 rejection as failed with the errors, without raising" do
    stub_request(:post, create_url).to_return(
      status: 422,
      body: { errors: [ "Backfill class name must be a valid DataDrip backfill class" ] }.to_json
    )

    expect { described_class.perform_now(dispatch) }.not_to raise_error

    expect(dispatch.reload).to be_failed
    expect(dispatch.error_message).to match(/must be a valid DataDrip backfill class/)
  end

  it "marks a 5xx as failed and raises so the queue retries" do
    stub_request(:post, create_url).to_return(status: 503, body: "")

    expect { described_class.perform_now(dispatch) }.to raise_error(
      DataDrip::CellTransport::Error
    )

    expect(dispatch.reload).to be_failed
    expect(dispatch.error_message).to match(/HTTP 503/)
  end

  it "marks a network failure as failed and raises so the queue retries" do
    stub_request(:post, create_url).to_timeout

    expect { described_class.perform_now(dispatch) }.to raise_error(
      DataDrip::CellTransport::Error
    )

    expect(dispatch.reload).to be_failed
  end

  it "does nothing when the dispatch was already delivered" do
    dispatch.update!(status: :dispatched, remote_run_id: 1)

    described_class.perform_now(dispatch)

    expect(a_request(:post, create_url)).not_to have_been_made
  end

  it "delivers script dispatches to the script endpoint" do
    script_dispatch =
      DataDrip::CellDispatch.create!(
        group_uuid: "group-s",
        cell_id: "cell-b",
        runnable_type: :script,
        status: :pending,
        payload: {
          "group_uuid" => "group-s",
          "script_class_name" => "GreetEmployees",
          "inputs" => { "greeting" => "Hi", "dry_run" => true },
          "backfiller_id" => 1,
          "backfiller_name" => "Suzie"
        }
      )

    stub =
      stub_request(:post, cell_api_url("cell-b", "/v1/script_runs"))
        .to_return(status: 201, body: { id: 55 }.to_json)

    described_class.perform_now(script_dispatch)

    expect(stub).to have_been_requested
    expect(script_dispatch.reload).to be_dispatched
    expect(script_dispatch.remote_run_id).to eq(55)
  end
end
