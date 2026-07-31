# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::CellStatusFetcher do
  before { configure_multi_cell! }

  it "returns each reachable cell's snapshot" do
    stub_request(
      :get,
      cell_api_url("cell-b", "/v1/groups/g-1?target_cell_id=cell-b")
    ).to_return(
      status: 200,
      body: { cell_id: "cell-b", runs: [ { "id" => 7, "status" => "running" } ] }.to_json
    )
    stub_request(
      :get,
      cell_api_url("cell-c", "/v1/groups/g-1?target_cell_id=cell-c")
    ).to_return(status: 200, body: { cell_id: "cell-c", runs: [] }.to_json)

    result =
      described_class.new(group_uuid: "g-1", cell_ids: %w[cell-b cell-c]).call

    expect(result["cell-b"]["runs"].first["status"]).to eq("running")
    expect(result["cell-c"]["runs"]).to eq([])
  end

  it "marks a cell that responds with an error status as unreachable" do
    stub_request(:get, %r{cell-b\.example\.com}).to_return(status: 502, body: "")

    result = described_class.new(group_uuid: "g-1", cell_ids: %w[cell-b]).call

    expect(result["cell-b"]["unreachable"]).to be(true)
    expect(result["cell-b"]["http_status"]).to eq(502)
  end

  it "marks a cell whose transport errors as unreachable" do
    stub_request(:get, %r{cell-b\.example\.com}).to_timeout

    result = described_class.new(group_uuid: "g-1", cell_ids: %w[cell-b]).call

    expect(result["cell-b"]["unreachable"]).to be(true)
    expect(result["cell-b"]["error"]).to be_present
  end

  it "gives up on cells that miss the shared deadline without failing the others" do
    stub_request(:get, %r{cell-b\.example\.com}).to_return do |_request|
      sleep 2
      { status: 200, body: { cell_id: "cell-b", runs: [] }.to_json }
    end
    stub_request(:get, %r{cell-c\.example\.com}).to_return(
      status: 200,
      body: { cell_id: "cell-c", runs: [] }.to_json
    )

    result =
      described_class.new(
        group_uuid: "g-1",
        cell_ids: %w[cell-b cell-c],
        deadline: 0.2
      ).call

    expect(result["cell-b"]["unreachable"]).to be(true)
    expect(result["cell-b"]["timed_out"]).to be(true)
    expect(result["cell-c"]["runs"]).to eq([])
  end
end
