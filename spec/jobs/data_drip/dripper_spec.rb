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
      # Skip validation to allow creation, then mock the error
      backfill_run.save!(validate: false)
      allow_any_instance_of(AddRoleToEmployee).to receive(:scope).and_raise(
        StandardError,
        "Test error"
      )

      expect { described_class.new.perform(backfill_run) }.to raise_error(
        StandardError
      )

      backfill_run.reload
      expect(backfill_run.status).to eq("failed")
      expect(backfill_run.error_message).to eq("Test error")
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
