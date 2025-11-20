require "spec_helper"

RSpec.describe DataDrip::BackfillRunBatch, type: :model do
  let!(:backfiller) { User.create!(name: "Test User") }
  let!(:employee1) { Employee.create!(name: "John", role: nil, age: 25) }
  let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }
  let!(:employee3) { Employee.create!(name: "Bob", role: nil, age: 25) }
  let!(:employee4) { Employee.create!(name: "Alice", role: "manager", age: 25) }

  describe "#run! with options processing" do
    let(:backfill_run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 10,
        start_at: Time.current + 1.hour,
        backfiller: backfiller,
        options: options
      )
    end

    let(:batch) do
      batch = DataDrip::BackfillRunBatch.new(
        backfill_run: backfill_run,
        batch_size: 10,
        start_id: 1,
        finish_id: 999999,
        status: :pending
      )
      batch.save!(validate: false)
      batch.update_column(:status, 0)
      batch
    end

    context "batch processing with options" do
      let(:options) { { age: "25" } }

      it "only processes filtered records" do
        expect(Employee.where(role: nil, age: 25).count).to eq(2)
        batch.run!

        expect(Employee.where(role: "intern").count).to eq(2)
        expect(Employee.where(role: "intern").pluck(:age)).to all(eq(25))
        expect(employee2.reload.role).to be_nil
      end
    end

    context "batch processing without options" do
      let(:options) { {} }

      it "processes all records in range" do
        expect(Employee.where(role: nil).count).to eq(3)

        batch.run!
        expect(Employee.where(role: "intern").count).to eq(3)
        expect(Employee.where(role: nil).count).to eq(0)
      end
    end

    context "type conversion in batch processing" do
      let(:options) { { age: "25" } }

      it "converts string to integer for filtering" do
        integer_type = instance_double(ActiveModel::Type::Integer)
        allow(backfill_run.backfill_class.backfill_options.attribute_types)
          .to receive(:[]).with("age").and_return(integer_type)
        allow(integer_type).to receive(:cast).with("25").and_return(25)
        batch.run!

        expect(Employee.where(role: "intern").count).to eq(2)
        expect(employee1.reload.role).to eq("intern")
        expect(employee2.reload.role).to be_nil # age 30
        expect(employee3.reload.role).to eq("intern")
        expect(integer_type).to have_received(:cast).with("25").at_least(:once)
      end
    end

    context "multiple options in batch" do
      let(:options) { { age: "25", name: employee1.name } }

      it "applies all filters correctly" do
        batch.run!

        expect(Employee.where(role: "intern").count).to eq(1)
        expect(employee1.reload.role).to eq("intern")
        expect(employee2.reload.role).to be_nil
        expect(employee3.reload.role).to be_nil
      end
    end

    context "with blank option values" do
      let(:options) { { age: "", name: "   ", role: nil } }

      it "ignores blank values and processes all records" do
        batch.run!

        expect(Employee.where(role: "intern").count).to eq(3)
        expect(Employee.where(role: nil).count).to eq(0)
      end
    end

    context "with non-existent attribute in options" do
      let(:options) { { non_existent_field: "some_value" } }

      it "raises an error when trying to filter by non-existent column" do
        expect { batch.run! }.to raise_error(ActiveRecord::StatementInvalid, /no such column/)
      end
    end
    context "ID range filtering" do
      let(:options) { { age: "25" } }

      let(:narrow_batch) do
        batch = DataDrip::BackfillRunBatch.new(
          backfill_run: backfill_run,
          batch_size: 1,
          start_id: employee1.id,
          finish_id: employee1.id,
          status: :pending
        )
        batch.save!(validate: false)
        batch.update_column(:status, 0)
        batch
      end

      it "respects both options filter and ID range" do
        narrow_batch.run!

        expect(Employee.where(role: "intern").count).to eq(1)
        expect(employee1.reload.role).to eq("intern")
        expect(employee3.reload.role).to be_nil
      end
    end
  end
end
