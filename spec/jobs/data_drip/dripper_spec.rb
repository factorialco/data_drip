# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::Dripper, type: :job do
  let!(:backfiller) { User.create!(name: "Test User") }
  let!(:employee1) { Employee.create!(name: "John", role: nil, age: 25) }
  let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }
  let!(:employee3) { Employee.create!(name: "Bob", role: nil, age: 25) }
  let!(:employee4) { Employee.create!(name: "Alice", role: "manager", age: 25) }

  describe "#perform" do
    let(:backfill_run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 2,
        start_at: 1.hour.from_now,
        backfiller: backfiller,
        options: {
          age: 25
        }
      )
    end

    it "creates batches based on the backfill class scope" do
      expect { described_class.new.perform(backfill_run) }.to change(
        DataDrip::BackfillRunBatch,
        :count
      )

      backfill_run.reload
      expect(backfill_run.total_count).to eq(2) # 2 employees with age 25 and role nil
      expect(backfill_run.batches.count).to eq(1) # 1 batch for 2 records with batch_size 2
      expect(backfill_run.batches.first.batch_size).to eq(2)
    end

    it "sets the backfill run to running status" do
      described_class.new.perform(backfill_run)
      expect(backfill_run.reload.status).to eq("running")
    end

    it "is idempotent: a duplicate delivery does not create a second set of batches" do
      described_class.new.perform(backfill_run)
      batch_count = backfill_run.reload.batches.count
      expect(batch_count).to be_positive

      # Same run delivered again (e.g. at-least-once queue) — now running.
      expect do
        described_class.new.perform(DataDrip::BackfillRun.find(backfill_run.id))
      end.not_to change(DataDrip::BackfillRunBatch, :count)

      expect(backfill_run.reload.batches.count).to eq(batch_count)
    end

    it "handles amount_of_elements limit" do
      backfill_run.update!(amount_of_elements: 1)

      expect { described_class.new.perform(backfill_run) }.to change(
        DataDrip::BackfillRunBatch,
        :count
      )

      backfill_run.reload
      expect(backfill_run.total_count).to eq(1)
      expect(backfill_run.batches.count).to eq(1)
      expect(backfill_run.batches.first.batch_size).to eq(1)
    end

    it "handles errors and sets failed status" do
      run =
        DataDrip::BackfillRun.new(
          backfill_class_name: "DripperSpec::BoomBackfill",
          batch_size: 2,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          options: {}
        )
      run.save!(validate: false)
      run.update_column(:status, DataDrip::BackfillRun.statuses[:enqueued])

      expect { described_class.new.perform(run) }.to raise_error(
        StandardError,
        "Boom"
      )

      run.reload
      expect(run.status).to eq("failed")
      expect(run.error_message).to eq("Boom")
    end

    context "with no options" do
      let(:backfill_run) do
        DataDrip::BackfillRun.create!(
          backfill_class_name: "AddRoleToEmployee",
          batch_size: 2,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          options: {}
        )
      end

      it "processes all records in base scope" do
        expect { described_class.new.perform(backfill_run) }.to change(
          DataDrip::BackfillRunBatch,
          :count
        )

        backfill_run.reload
        expect(backfill_run.total_count).to eq(3) # 3 employees with role nil
        expect(backfill_run.batches.count).to eq(2) # 2 batches: [2, 1]
      end
    end
  end
end

module DripperSpec
  class BoomBackfill < DataDrip::Backfill
    def scope
      raise StandardError, "Boom"
    end

    def process_element(_element); end
  end
end
