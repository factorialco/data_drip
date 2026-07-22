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

    describe "no_active_run_for_same_class" do
      it "is invalid when an identical active run (same class and options) already exists" do
        DataDrip::BackfillRun.create!(valid_attributes.merge(options: { age: 25 }))

        duplicate =
          DataDrip::BackfillRun.new(valid_attributes.merge(options: { age: 25 }))

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:base].join).to match(
          /already.*pending or in progress/
        )
      end

      it "is valid when an active run of the same class has different options" do
        DataDrip::BackfillRun.create!(valid_attributes.merge(options: { age: 25 }))

        # Same class, different options -> different target records -> allowed.
        other =
          DataDrip::BackfillRun.new(valid_attributes.merge(options: { age: 30 }))

        expect(other).to be_valid
      end

      it "is valid when an active run of the same class has a different element limit" do
        DataDrip::BackfillRun.create!(
          valid_attributes.merge(options: { age: 25 }, amount_of_elements: 1)
        )

        other =
          DataDrip::BackfillRun.new(valid_attributes.merge(options: { age: 25 }))

        expect(other).to be_valid
      end

      it "is valid when the existing identical run is terminal" do
        existing =
          DataDrip::BackfillRun.create!(
            valid_attributes.merge(options: { age: 25 })
          )
        existing.update_column(
          :status,
          DataDrip::BackfillRun.statuses[:completed]
        )

        duplicate =
          DataDrip::BackfillRun.new(valid_attributes.merge(options: { age: 25 }))

        expect(duplicate).to be_valid
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

  describe "backfiller name" do
    let(:valid_attributes) do
      {
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller,
        options: {
          age: 25
        }
      }
    end

    it "snapshots the backfiller's name onto the row at creation" do
      run = DataDrip::BackfillRun.create!(valid_attributes)

      expect(run.backfiller_name).to eq("Test User")
      expect(run.backfiller_display_name).to eq("Test User")
    end

    it "retains the name for display after the backfiller record is deleted" do
      run = DataDrip::BackfillRun.create!(valid_attributes)
      backfiller.delete
      run.reload

      expect(run.backfiller).to be_nil
      expect { run.backfiller_display_name }.not_to raise_error
      expect(run.backfiller_display_name).to eq("Test User")
    end

    it "falls back to the live association for rows without a snapshot" do
      run = DataDrip::BackfillRun.create!(valid_attributes)
      run.update_column(:backfiller_name, nil)
      run.reload

      expect(run.backfiller_display_name).to eq("Test User")
    end

    it "falls back to a placeholder when neither snapshot nor backfiller exist" do
      run = DataDrip::BackfillRun.create!(valid_attributes)
      run.update_column(:backfiller_name, nil)
      backfiller.delete
      run.reload

      expect(run.backfiller_display_name).to eq("Deleted user")
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

  describe "#terminal?" do
    def run_with(status)
      run =
        DataDrip::BackfillRun.new(
          backfill_class_name: "AddRoleToEmployee",
          batch_size: 100,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          options: { age: 25 }
        )
      run.save!(validate: false)
      run.update_column(:status, DataDrip::BackfillRun.statuses[status])
      run.reload
    end

    it "is true for completed, failed and stopped runs" do
      expect(run_with(:completed)).to be_terminal
      expect(run_with(:failed)).to be_terminal
      expect(run_with(:stopped)).to be_terminal
    end

    it "is false for pending, enqueued and running runs" do
      expect(run_with(:pending)).not_to be_terminal
      expect(run_with(:enqueued)).not_to be_terminal
      expect(run_with(:running)).not_to be_terminal
    end
  end

  describe "progress and timing metrics" do
    let(:run) do
      run =
        DataDrip::BackfillRun.new(
          backfill_class_name: "AddRoleToEmployee",
          batch_size: 100,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          options: { age: 25 }
        )
      run.save!(validate: false)
      run
    end

    def add_batch(created_at:, updated_at:, status: :completed)
      batch =
        DataDrip::BackfillRunBatch.new(
          backfill_run: run,
          batch_size: 100,
          start_id: 1,
          finish_id: 100
        )
      batch.save!(validate: false)
      batch.update_columns(
        status: DataDrip::BackfillRunBatch.statuses[status],
        created_at: created_at,
        updated_at: updated_at
      )
      batch
    end

    describe "#progress_percent" do
      it "is 100 once the run is completed, regardless of counts" do
        run.update_columns(
          status: DataDrip::BackfillRun.statuses[:completed],
          total_count: 0,
          processed_count: 0
        )

        expect(run.reload.progress_percent).to eq(100)
      end

      it "is 0 when nothing is known yet" do
        run.update_columns(total_count: 0, processed_count: 0)

        expect(run.reload.progress_percent).to eq(0)
      end

      it "floors the processed/total ratio" do
        run.update_columns(total_count: 3, processed_count: 2)

        # 2/3 = 66.6% -> floored to 66
        expect(run.reload.progress_percent).to eq(66)
      end

      it "never reports more than 100" do
        run.update_columns(total_count: 10, processed_count: 15)

        expect(run.reload.progress_percent).to eq(100)
      end
    end

    describe "#processing_started_at and #last_activity_at" do
      it "return nil before any batch exists" do
        expect(run.processing_started_at).to be_nil
        expect(run.last_activity_at).to be_nil
      end

      it "track the earliest creation and latest update across batches" do
        first = Time.utc(2030, 1, 1, 10, 0, 0)
        last = Time.utc(2030, 1, 1, 10, 5, 0)
        add_batch(created_at: first, updated_at: first)
        add_batch(created_at: last, updated_at: last)

        expect(run.processing_started_at).to be_within(1.second).of(first)
        expect(run.last_activity_at).to be_within(1.second).of(last)
      end
    end

    describe "#elapsed_seconds" do
      it "is nil until processing has started" do
        expect(run.elapsed_seconds).to be_nil
      end

      it "measures wall-clock between first and last batch for terminal runs" do
        started = Time.utc(2030, 1, 1, 10, 0, 0)
        finished = Time.utc(2030, 1, 1, 10, 2, 0)
        add_batch(created_at: started, updated_at: finished)
        run.update_column(:status, DataDrip::BackfillRun.statuses[:completed])

        expect(run.reload.elapsed_seconds).to be_within(1).of(120)
      end

      it "measures from the first batch until now for active runs" do
        started = 30.seconds.ago
        add_batch(created_at: started, updated_at: started, status: :running)
        run.update_column(:status, DataDrip::BackfillRun.statuses[:running])

        expect(run.reload.elapsed_seconds).to be >= 29
      end
    end

    describe "#throughput_per_minute" do
      it "is nil when no time has elapsed" do
        expect(run.throughput_per_minute).to be_nil
      end

      it "is nil when nothing has been processed" do
        started = Time.utc(2030, 1, 1, 10, 0, 0)
        finished = Time.utc(2030, 1, 1, 10, 2, 0)
        add_batch(created_at: started, updated_at: finished)
        run.update_columns(
          status: DataDrip::BackfillRun.statuses[:completed],
          processed_count: 0
        )

        expect(run.reload.throughput_per_minute).to be_nil
      end

      it "computes records per minute" do
        started = Time.utc(2030, 1, 1, 10, 0, 0)
        finished = Time.utc(2030, 1, 1, 10, 2, 0)
        add_batch(created_at: started, updated_at: finished)
        run.update_columns(
          status: DataDrip::BackfillRun.statuses[:completed],
          processed_count: 300
        )

        # 300 records over 120s -> 150 records/min
        expect(run.reload.throughput_per_minute).to be_within(1).of(150)
      end
    end

    describe "#eta_seconds" do
      it "is nil unless the run is running with a known total" do
        run.update_columns(
          status: DataDrip::BackfillRun.statuses[:completed],
          total_count: 100
        )
        expect(run.reload.eta_seconds).to be_nil
      end

      it "is nil when throughput cannot be computed yet" do
        run.update_columns(
          status: DataDrip::BackfillRun.statuses[:running],
          total_count: 100,
          processed_count: 0
        )
        expect(run.reload.eta_seconds).to be_nil
      end

      it "estimates the remaining seconds from the current throughput" do
        started = 60.seconds.ago
        add_batch(
          created_at: started,
          updated_at: 1.second.ago,
          status: :completed
        )
        run.update_columns(
          status: DataDrip::BackfillRun.statuses[:running],
          total_count: 100,
          processed_count: 50
        )

        # ~50 records/min, 50 remaining -> ~60s
        expect(run.reload.eta_seconds).to be_within(15).of(60)
      end

      it "is nil when more records were processed than the total" do
        started = 60.seconds.ago
        add_batch(
          created_at: started,
          updated_at: 1.second.ago,
          status: :completed
        )
        run.update_columns(
          status: DataDrip::BackfillRun.statuses[:running],
          total_count: 50,
          processed_count: 60
        )

        expect(run.reload.eta_seconds).to be_nil
      end
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

  describe "required options" do
    let(:attributes) do
      {
        backfill_class_name: "BackfillRunSpec::RequiredOptionBackfill",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller
      }
    end

    it "tracks required option names on the backfill class" do
      expect(
        BackfillRunSpec::RequiredOptionBackfill.required_option_names
      ).to eq(%i[target_role])
      expect(
        BackfillRunSpec::RequiredOptionBackfill.backfill_options_class.new
      ).not_to be_valid
    end

    it "is invalid when a required option is missing" do
      backfill_run = DataDrip::BackfillRun.new(attributes.merge(options: {}))

      expect(backfill_run).not_to be_valid
      expect(backfill_run.errors[:options]).to include(
        "target_role can't be blank"
      )
    end

    it "is invalid when a required option is blank" do
      backfill_run =
        DataDrip::BackfillRun.new(
          attributes.merge(options: { "target_role" => "" })
        )

      expect(backfill_run).not_to be_valid
      expect(backfill_run.errors[:options]).to include(
        "target_role can't be blank"
      )
    end

    it "is valid when the required option is provided" do
      backfill_run =
        DataDrip::BackfillRun.new(
          attributes.merge(options: { "target_role" => "intern" })
        )

      expect(backfill_run).to be_valid
    end

    it "accepts false for a required boolean option" do
      backfill_run =
        DataDrip::BackfillRun.new(
          attributes.merge(
            backfill_class_name: "BackfillRunSpec::RequiredBooleanBackfill",
            options: {
              "confirmed" => "0"
            }
          )
        )

      expect(backfill_run).to be_valid
    end

    it "skips scope validation instead of crashing when a required option the scope depends on is missing" do
      backfill_run =
        DataDrip::BackfillRun.new(
          attributes.merge(
            backfill_class_name: "BackfillRunSpec::ScopeNeedsOptionBackfill",
            options: {}
          )
        )

      expect { backfill_run.valid? }.not_to raise_error
      expect(backfill_run.errors[:options]).to include(
        "minimum_age can't be blank"
      )
    end

    it "still reports unknown option keys" do
      backfill_run =
        DataDrip::BackfillRun.new(
          attributes.merge(
            options: {
              "target_role" => "intern",
              "bogus" => "1"
            }
          )
        )

      expect(backfill_run).not_to be_valid
      expect(backfill_run.errors[:options].join).to include("unknown attributes")
    end
  end
end

module BackfillRunSpec
  class RequiredOptionBackfill < DataDrip::Backfill
    attribute :target_role, :string, required: true

    def scope
      Employee.all
    end

    def process_element(_element); end
  end

  class RequiredBooleanBackfill < DataDrip::Backfill
    attribute :confirmed, :boolean, required: true

    def scope
      Employee.all
    end

    def process_element(_element); end
  end

  class ScopeNeedsOptionBackfill < DataDrip::Backfill
    attribute :minimum_age, :integer, required: true

    def scope
      # Blows up if minimum_age is nil — exactly what the guard protects against.
      Employee.where("age >= ?", Integer(minimum_age))
    end

    def process_element(_element); end
  end
end
