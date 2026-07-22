# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::BackfillRunBatch, type: :model do
  let!(:backfiller) { User.create!(name: "Test User") }
  let!(:employee1) { Employee.create!(name: "John", role: nil, age: 25) }
  let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }
  let!(:employee3) { Employee.create!(name: "Bob", role: nil, age: 25) }
  let!(:employee4) { Employee.create!(name: "Alice", role: "manager", age: 25) }

  describe "#run!" do
    let(:backfill_run) do
      # Skip validation to allow creation for testing
      backfill_run =
        DataDrip::BackfillRun.new(
          backfill_class_name: "AddRoleToEmployee",
          batch_size: 10,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          options: {
            age: 25
          }
        )
      backfill_run.save!(validate: false)
      backfill_run
    end

    let(:batch) do
      batch =
        DataDrip::BackfillRunBatch.new(
          backfill_run: backfill_run,
          batch_size: 10,
          start_id: employee1.id,
          finish_id: employee3.id,
          status: :pending
        )
      batch.save!(validate: false)
      batch.update_column(:status, 0)
      batch
    end

    it "processes records using the backfill class scope" do
      expect(Employee.where(role: nil, age: 25).count).to eq(2)

      batch.run!

      expect(Employee.where(role: "intern").count).to eq(2)
      expect(Employee.where(role: "intern").pluck(:age)).to all(eq(25))
      expect(employee2.reload.role).to be_nil
    end

    it "sets status to running during execution" do
      empty_run =
        DataDrip::BackfillRun.new(
          backfill_class_name: "BackfillRunBatchSpec::EmptyScopeBackfill",
          batch_size: 10,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          options: {}
        )
      empty_run.save!(validate: false)

      empty_batch =
        DataDrip::BackfillRunBatch.new(
          backfill_run: empty_run,
          batch_size: 10,
          start_id: 1,
          finish_id: 100
        )
      empty_batch.save!(validate: false)
      empty_batch.update_column(:status, 0)

      empty_batch.run!

      expect(empty_batch.reload.status).to eq("running")
    end

    it "passes the run's options through to the backfill instance" do
      run =
        DataDrip::BackfillRun.new(
          backfill_class_name: "BackfillRunBatchSpec::EchoRoleBackfill",
          batch_size: 10,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          options: {
            "role" => "custom_role"
          }
        )
      run.save!(validate: false)

      echo_batch =
        DataDrip::BackfillRunBatch.new(
          backfill_run: run,
          batch_size: 10,
          start_id: employee1.id,
          finish_id: employee3.id
        )
      echo_batch.save!(validate: false)
      echo_batch.update_column(:status, 0)

      echo_batch.run!

      expect(
        Employee.where(
          id: [ employee1.id, employee2.id, employee3.id ]
        ).pluck(:role)
      ).to all(eq("custom_role"))
    end

    context "with no options" do
      let(:backfill_run) do
        backfill_run =
          DataDrip::BackfillRun.new(
            backfill_class_name: "AddRoleToEmployee",
            batch_size: 10,
            start_at: 1.hour.from_now,
            backfiller: backfiller,
            options: {}
          )
        backfill_run.save!(validate: false)
        backfill_run
      end

      let(:batch) do
        batch =
          DataDrip::BackfillRunBatch.new(
            backfill_run: backfill_run,
            batch_size: 10,
            start_id: employee1.id,
            finish_id: employee3.id,
            status: :pending
          )
        batch.save!(validate: false)
        batch.update_column(:status, 0)
        batch
      end

      it "processes records using the backfill class scope within ID range" do
        expect(Employee.where(role: nil).count).to eq(3)

        batch.run!

        expect(Employee.where(role: "intern").count).to eq(3)
        expect(Employee.where(role: nil).count).to eq(0)
      end
    end
  end

  describe "validations" do
    let(:test_backfill_run) do
      backfill_run =
        DataDrip::BackfillRun.new(
          backfill_class_name: "AddRoleToEmployee",
          batch_size: 10,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          options: {}
        )
      backfill_run.save!(validate: false)
      backfill_run
    end

    let(:valid_batch_attributes) do
      {
        backfill_run: test_backfill_run,
        start_id: 1,
        finish_id: 10,
        batch_size: 5,
        status: :pending
      }
    end

    it "validates presence of start_id" do
      batch =
        DataDrip::BackfillRunBatch.new(valid_batch_attributes.except(:start_id))
      expect(batch).not_to be_valid
      expect(batch.errors[:start_id]).to include("can't be blank")
    end

    it "validates presence of finish_id" do
      batch =
        DataDrip::BackfillRunBatch.new(
          valid_batch_attributes.except(:finish_id)
        )
      expect(batch).not_to be_valid
      expect(batch.errors[:finish_id]).to include("can't be blank")
    end

    it "validates presence of batch_size" do
      batch =
        DataDrip::BackfillRunBatch.new(
          valid_batch_attributes.merge(batch_size: nil)
        )
      expect(batch).not_to be_valid
      expect(batch.errors[:batch_size]).to include("can't be blank")
    end

    it "validates batch_size is greater than 0" do
      batch =
        DataDrip::BackfillRunBatch.new(
          valid_batch_attributes.merge(batch_size: 0)
        )
      expect(batch).not_to be_valid
      expect(batch.errors[:batch_size]).to include("must be greater than 0")
    end
  end
end

module BackfillRunBatchSpec
  # Writes the received `role` option onto every processed record, so a test
  # can assert the run's options reached the backfill instance.
  class EchoRoleBackfill < DataDrip::Backfill
    attribute :role, :string

    def scope
      Employee.all
    end

    def process_element(element)
      element.update!(role: role)
    end
  end

  class EmptyScopeBackfill < DataDrip::Backfill
    def scope
      Employee.none
    end

    def process_element(_element); end
  end
end
