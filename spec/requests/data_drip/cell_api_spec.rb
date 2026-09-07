# frozen_string_literal: true

require "spec_helper"

RSpec.describe "DataDrip Cell API", type: :request do
  let!(:backfiller) { User.create!(name: "Suzie") }

  let(:headers) do
    {
      "Authorization" => "Bearer #{MultiCellHelpers::CELL_API_TOKEN}",
      "CONTENT_TYPE" => "application/json"
    }
  end

  let(:create_payload) do
    {
      target_cell_id: "cell-a",
      group_uuid: "group-1",
      origin_cell_id: "cell-b",
      backfill_class_name: "AddRoleToEmployee",
      options: { "age" => 25 },
      batch_size: 50,
      amount_of_elements: nil,
      start_at: 1.hour.from_now.utc.iso8601,
      backfiller_id: backfiller.id,
      backfiller_name: "Suzie"
    }
  end

  before do
    Employee.create!(name: "Pepe", role: nil, age: 25)
    # This deployment is cell-a; requests arrive from a coordinator in cell-b.
    configure_multi_cell!(current: "cell-a")
  end

  describe "authentication" do
    it "rejects requests without a token" do
      post "/data_drip/cell_api/v1/backfill_runs",
           params: create_payload.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects requests with a wrong token" do
      post "/data_drip/cell_api/v1/backfill_runs",
           params: create_payload.to_json,
           headers: headers.merge("Authorization" => "Bearer wrong")

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects everything when no tokens are configured" do
      DataDrip.cell_api_tokens = []

      post "/data_drip/cell_api/v1/backfill_runs",
           params: create_payload.to_json,
           headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts any of the configured tokens (rotation)" do
      DataDrip.cell_api_tokens = [ "old", MultiCellHelpers::CELL_API_TOKEN ]

      post "/data_drip/cell_api/v1/backfill_runs",
           params: create_payload.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
    end
  end

  describe "target cell echo check" do
    it "refuses requests meant for another cell" do
      post "/data_drip/cell_api/v1/backfill_runs",
           params: create_payload.merge(target_cell_id: "cell-c").to_json,
           headers: headers

      expect(response).to have_http_status(:misdirected_request)
      expect(DataDrip::BackfillRun.count).to eq(0)
    end

    it "refuses requests without a target cell" do
      post "/data_drip/cell_api/v1/backfill_runs",
           params: create_payload.except(:target_cell_id).to_json,
           headers: headers

      expect(response).to have_http_status(:misdirected_request)
    end
  end

  describe "POST /v1/backfill_runs" do
    it "creates a remote-origin run that enqueues locally" do
      expect do
        post "/data_drip/cell_api/v1/backfill_runs",
             params: create_payload.to_json,
             headers: headers
      end.to change(DataDrip::BackfillRun, :count).by(1)

      expect(response).to have_http_status(:created)

      run = DataDrip::BackfillRun.last!
      expect(run.origin).to eq("remote")
      expect(run.cell_id).to eq("cell-a")
      expect(run.group_uuid).to eq("group-1")
      expect(run.origin_cell_id).to eq("cell-b")
      expect(run.options).to eq("age" => 25)
      expect(run.batch_size).to eq(50)
      expect(run.backfiller_id).to eq(backfiller.id)
      expect(run.status).to eq("enqueued")

      body = response.parsed_body
      expect(body["id"]).to eq(run.id)
      expect(body["type"]).to eq("backfill")
      expect(body["status"]).to eq("enqueued")
    end

    it "accepts a backfiller_id that does not exist locally" do
      missing_id = backfiller.id + 999_999

      post "/data_drip/cell_api/v1/backfill_runs",
           params:
             create_payload.merge(
               backfiller_id: missing_id,
               backfiller_name: "Remote Rita"
             ).to_json,
           headers: headers

      expect(response).to have_http_status(:created)

      run = DataDrip::BackfillRun.last!
      expect(run.backfiller_id).to eq(missing_id)
      expect(run.backfiller).to be_nil
      expect(run.backfiller_display_name).to eq("Remote Rita")
    end

    it "returns the existing run for a duplicate delivery" do
      post "/data_drip/cell_api/v1/backfill_runs",
           params: create_payload.to_json,
           headers: headers
      first_id = response.parsed_body["id"]

      expect do
        post "/data_drip/cell_api/v1/backfill_runs",
             params: create_payload.to_json,
             headers: headers
      end.not_to change(DataDrip::BackfillRun, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(first_id)
    end

    it "rejects an unknown backfill class with the validation errors" do
      post "/data_drip/cell_api/v1/backfill_runs",
           params: create_payload.merge(backfill_class_name: "NotDeployedYet").to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"].join).to match(/valid DataDrip backfill class/)
    end

    it "requires a group_uuid" do
      post "/data_drip/cell_api/v1/backfill_runs",
           params: create_payload.merge(group_uuid: nil).to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"].join).to match(/group_uuid/)
    end
  end

  describe "GET /v1/groups/:group_uuid" do
    it "returns this cell's runs for the group" do
      post "/data_drip/cell_api/v1/backfill_runs",
           params: create_payload.to_json,
           headers: headers

      get "/data_drip/cell_api/v1/groups/group-1",
          params: { target_cell_id: "cell-a" },
          headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["cell_id"]).to eq("cell-a")
      expect(body["runs"].size).to eq(1)
      expect(body["runs"].first["type"]).to eq("backfill")
      expect(body["runs"].first).to have_key("progress_percent")
    end

    it "returns an empty list for an unknown group" do
      get "/data_drip/cell_api/v1/groups/never-heard-of-it",
          params: { target_cell_id: "cell-a" },
          headers: headers

      expect(response.parsed_body["runs"]).to eq([])
    end

    it "includes the script output tail in script snapshots" do
      DataDrip::ScriptRun.create!(
        script_class_name: "GreetEmployees",
        inputs: { "greeting" => "Hi", "dry_run" => true },
        backfiller: backfiller,
        group_uuid: "group-s",
        origin: :remote,
        origin_cell_id: "cell-b"
      ).update!(status: :completed, output: "line 1\nline 2")

      get "/data_drip/cell_api/v1/groups/group-s",
          params: { target_cell_id: "cell-a" },
          headers: headers

      snapshot = response.parsed_body["runs"].first
      expect(snapshot["type"]).to eq("script")
      expect(snapshot["output_tail"]).to eq("line 1\nline 2")
      expect(snapshot["output_truncated"]).to be(false)
    end

    # Snapshots travel once per cell on every poll of the coordinator's page, so
    # a large log is trimmed to a readable tail rather than shipped whole.
    it "trims a large script log to its tail" do
      log = (1..5_000).map { |i| "line #{i}" }.join("\n")
      DataDrip::ScriptRun.create!(
        script_class_name: "GreetEmployees",
        inputs: { "greeting" => "Hi", "dry_run" => true },
        backfiller: backfiller,
        group_uuid: "group-big",
        origin: :remote,
        origin_cell_id: "cell-b"
      ).update!(status: :completed, output: log)

      get "/data_drip/cell_api/v1/groups/group-big",
          params: { target_cell_id: "cell-a" },
          headers: headers

      snapshot = response.parsed_body["runs"].first
      expect(snapshot["output_truncated"]).to be(true)
      expect(snapshot["output_tail"].bytesize)
        .to be <= DataDrip::RunSnapshot.output_tail_bytes
      expect(snapshot["output_tail"]).to end_with("line 5000")
      expect(snapshot["output_tail"]).not_to include("line 1\n")
    end
  end

  describe "POST /v1/backfill_runs/:id/stop" do
    let!(:run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: Time.current,
        backfiller: backfiller,
        group_uuid: "group-1",
        origin: :remote
      )
    end

    it "stops a running run for its owner" do
      run.running!

      post "/data_drip/cell_api/v1/backfill_runs/#{run.id}/stop",
           params: {
             target_cell_id: "cell-a",
             acting_backfiller_id: backfiller.id
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(run.reload).to be_stopped
    end

    it "refuses a non-owner" do
      run.running!

      post "/data_drip/cell_api/v1/backfill_runs/#{run.id}/stop",
           params: {
             target_cell_id: "cell-a",
             acting_backfiller_id: backfiller.id + 1
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(run.reload).to be_running
    end

    it "refuses a run that is not running" do
      post "/data_drip/cell_api/v1/backfill_runs/#{run.id}/stop",
           params: {
             target_cell_id: "cell-a",
             acting_backfiller_id: backfiller.id
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:conflict)
    end

    # The Cell API exists to manage this cell's own leg of a fanned-out group. A
    # run somebody created in this cell's UI is not another cell's business,
    # even though the caller holds a valid token.
    it "cannot touch a run created locally in this cell" do
      local =
        DataDrip::BackfillRun.create!(
          backfill_class_name: "AddRoleToEmployee",
          batch_size: 100,
          amount_of_elements: 9,
          start_at: Time.current,
          backfiller: backfiller
        )
      local.running!

      post "/data_drip/cell_api/v1/backfill_runs/#{local.id}/stop",
           params: {
             target_cell_id: "cell-a",
             acting_backfiller_id: backfiller.id
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:not_found)
      expect(local.reload).to be_running
    end

    it "404s for an unknown run" do
      post "/data_drip/cell_api/v1/backfill_runs/999999/stop",
           params: {
             target_cell_id: "cell-a",
             acting_backfiller_id: backfiller.id
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /v1/backfill_runs/:id/retry_failed_batches" do
    let!(:run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: Time.current,
        backfiller: backfiller,
        group_uuid: "group-1",
        origin: :remote
      )
    end

    it "re-enqueues failed batches" do
      run.running!
      batch =
        DataDrip::BackfillRunBatch.create!(
          backfill_run: run,
          status: :failed,
          batch_size: 100,
          start_id: 1,
          finish_id: 100,
          error_message: "boom"
        )
      run.failed!

      post "/data_drip/cell_api/v1/backfill_runs/#{run.id}/retry_failed_batches",
           params: {
             target_cell_id: "cell-a",
             acting_backfiller_id: backfiller.id
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(batch.reload).not_to be_failed
      expect(run.reload).to be_running
    end

    it "refuses when there is nothing to retry" do
      post "/data_drip/cell_api/v1/backfill_runs/#{run.id}/retry_failed_batches",
           params: {
             target_cell_id: "cell-a",
             acting_backfiller_id: backfiller.id
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:conflict)
    end
  end

  describe "DELETE /v1/backfill_runs/:id" do
    let!(:run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.day.from_now,
        backfiller: backfiller,
        group_uuid: "group-1",
        origin: :remote
      )
    end

    it "deletes a not-yet-run run for its owner" do
      delete "/data_drip/cell_api/v1/backfill_runs/#{run.id}",
             params: {
               target_cell_id: "cell-a",
               acting_backfiller_id: backfiller.id
             }.to_json,
             headers: headers

      expect(response).to have_http_status(:no_content)
      expect(DataDrip::BackfillRun.exists?(run.id)).to be(false)
    end

    it "refuses once the run has executed" do
      run.running!

      delete "/data_drip/cell_api/v1/backfill_runs/#{run.id}",
             params: {
               target_cell_id: "cell-a",
               acting_backfiller_id: backfiller.id
             }.to_json,
             headers: headers

      expect(response).to have_http_status(:conflict)
      expect(DataDrip::BackfillRun.exists?(run.id)).to be(true)
    end

    it "refuses a non-owner" do
      delete "/data_drip/cell_api/v1/backfill_runs/#{run.id}",
             params: {
               target_cell_id: "cell-a",
               acting_backfiller_id: backfiller.id + 1
             }.to_json,
             headers: headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /v1/script_runs" do
    let(:script_payload) do
      {
        target_cell_id: "cell-a",
        group_uuid: "group-s",
        origin_cell_id: "cell-b",
        script_class_name: "GreetEmployees",
        inputs: { "greeting" => "Hi", "dry_run" => true },
        start_at: Time.current.utc.iso8601,
        backfiller_id: backfiller.id,
        backfiller_name: "Suzie"
      }
    end

    it "creates a remote-origin script run" do
      expect do
        post "/data_drip/cell_api/v1/script_runs",
             params: script_payload.to_json,
             headers: headers
      end.to change(DataDrip::ScriptRun, :count).by(1)

      expect(response).to have_http_status(:created)

      run = DataDrip::ScriptRun.last!
      expect(run.origin).to eq("remote")
      expect(run.cell_id).to eq("cell-a")
      expect(run.inputs).to eq("greeting" => "Hi", "dry_run" => true)
    end

    it "is idempotent per (group, cell)" do
      2.times do
        post "/data_drip/cell_api/v1/script_runs",
             params: script_payload.to_json,
             headers: headers
      end

      expect(response).to have_http_status(:ok)
      expect(DataDrip::ScriptRun.count).to eq(1)
    end

    it "rejects invalid inputs with the validation errors" do
      post "/data_drip/cell_api/v1/script_runs",
           params: script_payload.merge(inputs: {}).to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to be_present
    end
  end
end
