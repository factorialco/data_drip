# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::CellTransport::Http do
  subject(:transport) do
    described_class.new(
      url: ->(cell_id) { "https://#{cell_id}.example.com/data_drip/cell_api" },
      query: ->(cell_id) { { cell_id: cell_id } },
      headers: -> { { "Authorization" => "Bearer sekret" } }
    )
  end

  it "sends a JSON POST with the configured url, query and headers" do
    stub =
      stub_request(
        :post,
        "https://cell-b.example.com/data_drip/cell_api/v1/backfill_runs?cell_id=cell-b"
      )
        .with(
          headers: {
            "Authorization" => "Bearer sekret",
            "Content-Type" => "application/json"
          },
          body: { "group_uuid" => "abc" }
        )
        .to_return(
          status: 201,
          body: { id: 42 }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

    response =
      transport.call(
        cell_id: "cell-b",
        method: :post,
        path: "/v1/backfill_runs",
        body: { group_uuid: "abc" }
      )

    expect(stub).to have_been_requested
    expect(response.status).to eq(201)
    expect(response).to be_success
    expect(response.body).to eq("id" => 42)
  end

  it "merges the extra query params with ones already in the path" do
    stub =
      stub_request(
        :get,
        "https://cell-b.example.com/data_drip/cell_api/v1/groups/xyz?target_cell_id=cell-b&cell_id=cell-b"
      ).to_return(status: 200, body: { runs: [] }.to_json)

    response =
      transport.call(
        cell_id: "cell-b",
        method: :get,
        path: "/v1/groups/xyz?target_cell_id=cell-b"
      )

    expect(stub).to have_been_requested
    expect(response.body).to eq("runs" => [])
  end

  it "accepts plain values for url, query and headers" do
    plain =
      described_class.new(
        url: "https://static.example.com/api/",
        query: { token: "t" },
        headers: { "X-Thing" => "1" }
      )

    stub =
      stub_request(:get, "https://static.example.com/api/v1/groups/g?token=t")
        .with(headers: { "X-Thing" => "1" })
        .to_return(status: 200, body: "")

    response = plain.call(cell_id: "cell-b", method: :get, path: "/v1/groups/g")

    expect(stub).to have_been_requested
    expect(response.body).to eq({})
  end

  it "returns an empty body hash when the response is not JSON" do
    stub_request(:post, %r{cell-b\.example\.com}).to_return(
      status: 500,
      body: "<html>boom</html>"
    )

    response =
      transport.call(cell_id: "cell-b", method: :post, path: "/v1/backfill_runs", body: {})

    expect(response.status).to eq(500)
    expect(response).not_to be_success
    expect(response.body).to eq({})
  end

  it "wraps network failures in CellTransport::Error" do
    stub_request(:post, %r{cell-b\.example\.com}).to_timeout

    expect do
      transport.call(cell_id: "cell-b", method: :post, path: "/v1/backfill_runs", body: {})
    end.to raise_error(DataDrip::CellTransport::Error)
  end

  it "wraps connection refusals in CellTransport::Error" do
    stub_request(:get, %r{cell-b\.example\.com}).to_raise(Errno::ECONNREFUSED)

    expect do
      transport.call(cell_id: "cell-b", method: :get, path: "/v1/groups/g")
    end.to raise_error(DataDrip::CellTransport::Error)
  end

  it "rejects unsupported HTTP methods" do
    expect do
      transport.call(cell_id: "cell-b", method: :patch, path: "/v1/whatever")
    end.to raise_error(ArgumentError, /Unsupported HTTP method/)
  end
  # Hosts resolve cell urls from their own registry, which may refuse a cell
  # (unknown, or reachable only over plaintext). That has to reach the caller as
  # this cell's failure, not as an exception nothing is prepared for.
  it "reports a cell it cannot address as a transport error" do
    transport =
      described_class.new(
        url: ->(cell_id) { raise "cell=#{cell_id} has no api_url configured" }
      )

    expect { transport.call(cell_id: "cell-b", method: :get, path: "/v1/ping") }
      .to raise_error(DataDrip::CellTransport::Error, /Could not address cell cell-b/)
  end
end
