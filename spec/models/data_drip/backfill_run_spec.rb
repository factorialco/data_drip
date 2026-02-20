# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::BackfillRun, type: :model do
  let!(:backfiller) { User.create!(name: "Test User") }
  let!(:employee1) { Employee.create!(name: "John", role: nil, age: 25) }
  let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }

  describe "validations" do
    let(:valid_attributes) do
      {
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller
      }
    end

    describe "validate_scope" do
      describe "before_backfill callback" do
        it "calls DataDrip.before_backfill during validation" do
          callback_called = false
          original_callback = DataDrip.before_backfill

          DataDrip.before_backfill = -> { callback_called = true }

          backfill_run =
            DataDrip::BackfillRun.new(
              valid_attributes.merge(options: { age: 25 })
            )
          backfill_run.valid?

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

          backfill_run =
            DataDrip::BackfillRun.new(
              valid_attributes.merge(options: { age: 25 })
            )
          backfill_run.valid?

          expect(call_order).to eq([:before_backfill, :scope_accessed])
        ensure
          DataDrip.before_backfill = original_callback
        end
      end

      context "when scope has records" do
        it "is valid" do
          backfill_run =
            DataDrip::BackfillRun.new(
              valid_attributes.merge(options: { age: 25 })
            )

          expect(backfill_run).to be_valid
        end
      end

      context "when scope has no records" do
        it "is invalid with appropriate error message" do
          backfill_run =
            DataDrip::BackfillRun.new(
              valid_attributes.merge(options: { age: 999 })
            )

          expect(backfill_run).not_to be_valid
          expect(backfill_run.errors[:base]).to include(
            "No records to process with the current configuration. Please adjust your options or select a different backfill class."
          )
        end
      end

      context "when base scope has no records" do
        before { Employee.update_all(role: "existing") }

        it "is invalid" do
          backfill_run =
            DataDrip::BackfillRun.new(valid_attributes.merge(options: {}))

          expect(backfill_run).not_to be_valid
          expect(backfill_run.errors[:base]).to include(
            "No records to process with the current configuration. Please adjust your options or select a different backfill class."
          )
        end
      end

      context "with amount_of_elements limit" do
        it "is valid when limited scope has records" do
          backfill_run =
            DataDrip::BackfillRun.new(
              valid_attributes.merge(
                options: {
                  age: 25
                },
                amount_of_elements: 1
              )
            )

          expect(backfill_run).to be_valid
        end
      end
    end

    describe "other validations" do
      it "validates presence of backfill_class_name" do
        backfill_run =
          DataDrip::BackfillRun.new(
            start_at: 1.hour.from_now,
            batch_size: 100,
            backfiller: backfiller
          )
        expect(backfill_run).not_to be_valid
        expect(backfill_run.errors[:backfill_class_name]).to include(
          "can't be blank"
        )
      end

      it "validates presence of start_at" do
        backfill_run =
          DataDrip::BackfillRun.new(
            backfill_class_name: "AddRoleToEmployee",
            batch_size: 100,
            backfiller: backfiller
          )
        expect(backfill_run).not_to be_valid
        expect(backfill_run.errors[:start_at]).to include("can't be blank")
      end

      it "validates presence of batch_size" do
        backfill_run =
          DataDrip::BackfillRun.new(
            backfill_class_name: "AddRoleToEmployee",
            start_at: 1.hour.from_now,
            backfiller: backfiller,
            batch_size: nil
          )
        expect(backfill_run).not_to be_valid
        expect(backfill_run.errors[:batch_size]).to include("can't be blank")
      end

      it "validates batch_size is greater than 0" do
        backfill_run =
          DataDrip::BackfillRun.new(valid_attributes.merge(batch_size: 0))
        expect(backfill_run).not_to be_valid
        expect(backfill_run.errors[:batch_size]).to include(
          "must be greater than 0"
        )
      end

      it "validates backfill_class exists" do
        backfill_run =
          DataDrip::BackfillRun.new(
            valid_attributes.merge(backfill_class_name: "NonExistentClass")
          )
        expect(backfill_run).not_to be_valid
        expect(backfill_run.errors[:backfill_class_name]).to include(
          "must be a valid DataDrip backfill class"
        )
      end
    end
  end

  describe "#backfill_class" do
    it "returns the correct backfill class" do
      backfill_run =
        DataDrip::BackfillRun.new(backfill_class_name: "AddRoleToEmployee")
      expect(backfill_run.backfill_class).to eq(AddRoleToEmployee)
    end

    it "returns nil for invalid class name" do
      backfill_run =
        DataDrip::BackfillRun.new(backfill_class_name: "NonExistentClass")
      expect(backfill_run.backfill_class).to be_nil
    end
  end

  describe "status enum" do
    it "has the correct status values" do
      backfill_run = DataDrip::BackfillRun.allocate
      backfill_run.send(:initialize)
      backfill_run.assign_attributes(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller,
        options: {}
      )

      expect(backfill_run.status).to eq("pending")

      backfill_run.enqueued!
      expect(backfill_run.status).to eq("enqueued")

      backfill_run.running!
      expect(backfill_run.status).to eq("running")

      backfill_run.completed!
      expect(backfill_run.status).to eq("completed")
    end
  end
end
