# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::CellDispatch do
  include ActiveJob::TestHelper

  let(:dispatch) do
    described_class.create!(
      group_uuid: "group-1",
      cell_id: "cell-b",
      runnable_type: :backfill,
      status: :failed,
      error_message: "boom",
      payload: { "backfill_class_name" => "AddRoleToEmployee" }
    )
  end

  it "requires a group and a cell" do
    record = described_class.new
    expect(record).not_to be_valid
    expect(record.errors[:group_uuid]).to be_present
    expect(record.errors[:cell_id]).to be_present
  end

  it "enforces one dispatch per (group, cell)" do
    dispatch

    expect do
      described_class.create!(
        group_uuid: "group-1",
        cell_id: "cell-b",
        runnable_type: :backfill
      )
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "#retry!" do
    it "resets to pending, clears the error and re-enqueues the dispatcher" do
      expect { dispatch.retry! }.to have_enqueued_job(
        DataDrip::CellDispatcherJob
      )

      expect(dispatch.reload).to be_pending
      expect(dispatch.error_message).to be_nil
    end
  end
end
