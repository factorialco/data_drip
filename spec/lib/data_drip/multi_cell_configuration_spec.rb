# frozen_string_literal: true

require "spec_helper"

RSpec.describe "DataDrip multi-cell configuration" do
  it "is single-cell by default" do
    expect(DataDrip.multi_cell?).to be(false)
    expect(DataDrip.resolved_current_cell_id).to be_nil
    expect(DataDrip.resolved_cell_ids).to eq([])
    expect(DataDrip.resolved_cell_api_tokens).to eq([])
  end

  it "is multi-cell once a current cell, a transport and other cells exist" do
    configure_multi_cell!

    expect(DataDrip.multi_cell?).to be(true)
    expect(DataDrip.resolved_current_cell_id).to eq("cell-a")
    expect(DataDrip.remote_cell_ids).to eq(%w[cell-b cell-c])
  end

  it "stays single-cell when this is the only cell" do
    configure_multi_cell!(cells: %w[cell-a])

    expect(DataDrip.multi_cell?).to be(false)
    expect(DataDrip.remote_cell_ids).to eq([])
  end

  it "stays single-cell without a transport" do
    configure_multi_cell!
    DataDrip.cell_transport = nil

    expect(DataDrip.multi_cell?).to be(false)
  end

  it "resolves callables lazily" do
    cells = %w[cell-a]
    DataDrip.current_cell_id = -> { "cell-a" }
    DataDrip.cell_ids = -> { cells }
    DataDrip.cell_api_tokens = -> { [ "tok" ] }

    expect(DataDrip.resolved_current_cell_id).to eq("cell-a")
    expect(DataDrip.resolved_cell_ids).to eq(%w[cell-a])
    expect(DataDrip.resolved_cell_api_tokens).to eq(%w[tok])

    cells << "cell-b"
    expect(DataDrip.resolved_cell_ids).to eq(%w[cell-a cell-b])
  end

  it "drops blanks and duplicates from the cell list" do
    DataDrip.cell_ids = [ "cell-a", "", "cell-a", nil, "cell-b" ]

    expect(DataDrip.resolved_cell_ids).to eq(%w[cell-a cell-b])
  end

  describe "the cross-cell jobs' queue" do
    it "defaults to DataDrip.queue_name" do
      expect(DataDrip::CellDispatcherJob.new.queue_name).to eq(DataDrip.queue_name.to_s)
      expect(DataDrip::CellStatusRefreshJob.new.queue_name).to eq(DataDrip.queue_name.to_s)
    end

    it "uses DataDrip.cell_queue_name when set" do
      DataDrip.cell_queue_name = -> { :data_drip_cells }

      expect(DataDrip::CellDispatcherJob.new.queue_name).to eq("data_drip_cells")
      expect(DataDrip::CellStatusRefreshJob.new.queue_name).to eq("data_drip_cells")
      expect(DataDrip::Dripper.new.queue_name).to eq(DataDrip.queue_name.to_s)
    end
  end
end
