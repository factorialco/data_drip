# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::BackfillRunBatch, type: :model do
  let!(:backfiller) { User.create!(name: "Test User") }
  let!(:employee1) { Employee.create!(name: "John", role: nil, age: 25) }
  let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }
  let!(:employee3) { Employee.create!(name: "Bob", role: nil, age: 25) }
  let!(:employee4) { Employee.create!(name: "Alice", role: "manager", age: 25) }

  describe "#run!" do
    describe "before_backfill callback" do
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

      it "calls DataDrip.before_backfill before processing" do
        callback_called = false
        original_callback = DataDrip.before_backfill

        DataDrip.before_backfill = -> { callback_called = true }

        batch.run!

        expect(callback_called).to be true
      ensure
        DataDrip.before_backfill = original_callback
      end

      it "calls before_backfill before accessing scope" do
        call_order = []
        original_callback = DataDrip.before_backfill

        DataDrip.before_backfill = -> { call_order << :before_backfill }

        allow_any_instance_of(AddRoleToEmployee).to receive(:scope).and_wrap_original do |original_method|
          call_order << :scope_accessed
          original_method.call
        end

        batch.run!

        expect(call_order).to eq([:before_backfill, :scope_accessed])
      ensure
        DataDrip.before_backfill = original_callback
      end
    end

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
      allow_any_instance_of(AddRoleToEmployee).to receive(:scope).and_return(
        Employee.none
      )

      batch.run!

      expect(batch.reload.status).to eq("running")
    end

    it "passes options to the backfill class" do
      backfill_instance = instance_double(AddRoleToEmployee)
      allow(AddRoleToEmployee).to receive(:new).with(
        batch_size: 10,
        sleep_time: 5,
        backfill_options: {
          "age" => 25
        }
      ).and_return(backfill_instance)
      allow(backfill_instance).to receive(:scope).and_return(Employee.none)

      batch.run!

      expect(AddRoleToEmployee).to have_received(:new).with(
        batch_size: 10,
        sleep_time: 5,
        backfill_options: {
          "age" => 25
        }
      )
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
