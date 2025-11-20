require "spec_helper"

RSpec.describe DataDrip::Dripper, type: :job do
  let!(:backfiller) { User.create!(name: "Test User") }
  let!(:employee1) { Employee.create!(name: "John", role: nil, age: 25) }
  let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }
  let!(:employee3) { Employee.create!(name: "Bob", role: nil, age: 25) }
  let!(:employee4) { Employee.create!(name: "Alice", role: "manager", age: 25) }

  describe "#perform with and without options filtering" do
    let(:base_backfill_run_attributes) do
      {
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 2,
        start_at: Time.current + 1.hour,
        backfiller: backfiller
      }
    end

    context "no options" do
      it "processes all records in base scope" do
        backfill_run = DataDrip::BackfillRun.create!(
          base_backfill_run_attributes.merge(options: {})
        )

        expect { described_class.new.perform(backfill_run) }
          .to change(DataDrip::BackfillRunBatch, :count)

        backfill_run.reload
        expect(backfill_run.total_count).to eq(3)
        expect(backfill_run.batches.count).to eq(2)
      end
    end

    context "with integer option" do
      it "filters scope correctly with type conversion" do
        backfill_run = DataDrip::BackfillRun.create!(
          base_backfill_run_attributes.merge(options: { age: "25" })
        )

        expect { described_class.new.perform(backfill_run) }
          .to change(DataDrip::BackfillRunBatch, :count)

        backfill_run.reload
        expect(backfill_run.total_count).to eq(2)
        expect(backfill_run.batches.count).to eq(1)
        expect(backfill_run.batches.first.batch_size).to eq(2)
      end
    end

    context "with string option" do
      it "filters scope correctly" do
        Employee.where(id: employee1.id).update_all(name: "UniqueTestName")
        backfill_run = DataDrip::BackfillRun.create!(
          base_backfill_run_attributes.merge(options: { name: "UniqueTestName" })
        )

        expect { described_class.new.perform(backfill_run) }
          .to change(DataDrip::BackfillRunBatch, :count)

        backfill_run.reload
        expect(backfill_run.total_count).to eq(1)
        expect(backfill_run.batches.count).to eq(1)
      end
    end

    context "with multiple options" do
      it "applies all filters (AND condition)" do
        backfill_run = DataDrip::BackfillRun.create!(
          base_backfill_run_attributes.merge(options:
          {
            age: "25",
            name: employee1.name
          })
        )

        expect { described_class.new.perform(backfill_run) }
          .to change(DataDrip::BackfillRunBatch, :count)

        backfill_run.reload
        expect(backfill_run.total_count).to eq(1)
        expect(backfill_run.batches.count).to eq(1)
      end
    end

    context "with blank/empty option values" do
      it "ignores blank values" do
        backfill_run = DataDrip::BackfillRun.create!(
          base_backfill_run_attributes.merge(options:
          {
            age: "",
            name: "   ",
            role: nil
          })
        )

        expect { described_class.new.perform(backfill_run) }
          .to change(DataDrip::BackfillRunBatch, :count)

        backfill_run.reload
        expect(backfill_run.total_count).to eq(3)
        expect(backfill_run.batches.count).to eq(2)
      end
    end

    context "type conversion" do
      it "converts string '25' to integer 25 for integer attributes" do
        backfill_run = DataDrip::BackfillRun.create!(
          base_backfill_run_attributes.merge(options: { age: "25" })
        )
        integer_type = instance_double(ActiveModel::Type::Integer)
        allow(backfill_run.backfill_class.backfill_options.attribute_types)
          .to receive(:[]).with("age").and_return(integer_type)
        allow(integer_type).to receive(:cast).with("25").and_return(25)

        described_class.new.perform(backfill_run)

        backfill_run.reload
        expect(backfill_run.total_count).to eq(2)
        expect(integer_type).to have_received(:cast).with("25")
      end
    end

    context "with amount_of_elements limit" do
      it "respects amount_of_elements even with options" do
        backfill_run = DataDrip::BackfillRun.create!(
          base_backfill_run_attributes.merge(
            options: { age: "25" },
            amount_of_elements: 1
          )
        )

        expect { described_class.new.perform(backfill_run) }
          .to change(DataDrip::BackfillRunBatch, :count)

        backfill_run.reload
        expect(backfill_run.total_count).to eq(1)
        expect(backfill_run.batches.count).to eq(1)
        expect(backfill_run.batches.first.batch_size).to eq(1)
      end
    end
  end
end
