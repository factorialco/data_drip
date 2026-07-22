# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::DripperChild, type: :job do
  let!(:backfiller) { User.create!(name: "Test User") }
  let!(:employee1) { Employee.create!(name: "John", role: nil, age: 25) }
  let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 25) }
  let!(:employee3) { Employee.create!(name: "BOOM", role: nil, age: 25) }
  let!(:employee4) { Employee.create!(name: "Bob", role: nil, age: 25) }

  def build_run(backfill_class_name)
    run =
      DataDrip::BackfillRun.new(
        backfill_class_name: backfill_class_name,
        batch_size: 2,
        start_at: 1.hour.from_now,
        backfiller: backfiller,
        options: {}
      )
    run.save!(validate: false)
    run.update_column(:status, DataDrip::BackfillRun.statuses[:running])
    run
  end

  def build_batch(run, start_id:, finish_id:)
    batch =
      DataDrip::BackfillRunBatch.new(
        backfill_run: run,
        batch_size: 2,
        start_id: start_id,
        finish_id: finish_id
      )
    batch.save!(validate: false)
    batch.update_column(:status, DataDrip::BackfillRunBatch.statuses[:pending])
    batch
  end

  context "when all batches complete" do
    let(:run) { build_run("DripperChildSpec::OkBackfill") }
    let!(:batch1) { build_batch(run, start_id: employee1.id, finish_id: employee2.id) }
    let!(:batch2) { build_batch(run, start_id: employee3.id, finish_id: employee4.id) }

    it "marks the run completed only after the last batch finishes" do
      described_class.new.perform(batch1)

      expect(batch1.reload.status).to eq("completed")
      expect(run.reload.status).to eq("running") # batch2 still pending

      described_class.new.perform(batch2)

      expect(batch2.reload.status).to eq("completed")
      expect(run.reload.status).to eq("completed")
      expect(run.processed_count).to eq(4)
    end
  end

  context "when a batch fails" do
    let(:run) { build_run("DripperChildSpec::SelectiveFailBackfill") }
    let!(:ok_batch) { build_batch(run, start_id: employee1.id, finish_id: employee2.id) }
    let!(:failing_batch) { build_batch(run, start_id: employee3.id, finish_id: employee4.id) }

    it "settles the run on failed once every batch is terminal" do
      described_class.new.perform(ok_batch)
      expect(ok_batch.reload.status).to eq("completed")
      expect(run.reload.status).to eq("running") # failing batch still pending

      expect { described_class.new.perform(failing_batch) }.to raise_error(
        StandardError,
        /boom/
      )

      expect(failing_batch.reload.status).to eq("failed")
      expect(run.reload.status).to eq("failed")
      # Only the successful batch contributed to the processed count.
      expect(run.processed_count).to eq(2)
    end
  end

  context "when the same batch is delivered twice" do
    let(:run) { build_run("DripperChildSpec::OkBackfill") }
    let!(:batch) { build_batch(run, start_id: employee1.id, finish_id: employee2.id) }

    it "processes it once and does not double-count processed_count" do
      described_class.new.perform(batch)
      expect(batch.reload.status).to eq("completed")
      expect(run.reload.processed_count).to eq(2)

      # Duplicate delivery of the now-completed batch is a no-op.
      described_class.new.perform(DataDrip::BackfillRunBatch.find(batch.id))

      expect(batch.reload.status).to eq("completed")
      expect(run.reload.processed_count).to eq(2)
    end
  end

  context "when the run was stopped" do
    let(:run) { build_run("DripperChildSpec::OkBackfill") }
    let!(:batch) { build_batch(run, start_id: employee1.id, finish_id: employee2.id) }

    before { run.update_column(:status, DataDrip::BackfillRun.statuses[:stopped]) }

    it "marks the batch stopped and leaves the run stopped" do
      described_class.new.perform(batch)

      expect(batch.reload.status).to eq("stopped")
      expect(run.reload.status).to eq("stopped")
    end
  end
end

module DripperChildSpec
  class OkBackfill < DataDrip::Backfill
    def scope
      Employee.all
    end

    def process_element(element)
      element.update!(role: "done")
    end
  end

  class SelectiveFailBackfill < DataDrip::Backfill
    def scope
      Employee.all
    end

    def process_element(element)
      raise "boom on #{element.name}" if element.name == "BOOM"

      element.update!(role: "done")
    end
  end
end
