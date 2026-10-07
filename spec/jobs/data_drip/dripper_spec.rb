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

    it "leaves the run running while its batches are still outstanding" do
      described_class.new.perform(backfill_run)

      backfill_run.reload
      expect(backfill_run.batches.count).to be_positive
      expect(backfill_run.status).to eq("running")
      expect(backfill_run).not_to be_terminal
    end

    context "when the scope matches no records" do
      let(:backfill_run) do
        DataDrip::BackfillRun.create!(
          backfill_class_name: "AddRoleToEmployee",
          batch_size: 2,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          options: {
            age: 999
          }
        )
      end

      it "completes the run instead of leaving it stuck in running" do
        expect { described_class.new.perform(backfill_run) }.not_to change(
          DataDrip::BackfillRunBatch,
          :count
        )

        backfill_run.reload
        expect(backfill_run.batches.count).to eq(0)
        expect(backfill_run.total_count).to eq(0)
        expect(backfill_run.status).to eq("completed")
        expect(backfill_run).to be_terminal
      end

      it "fires the on_run_completed hook" do
        described_class.new.perform(backfill_run)

        expect(
          HookNotifier.instance.get("AddRoleToEmployee_run_completed")
        ).to eq(backfill_run.id)
      end

      it "no longer blocks a later identical run from being created" do
        described_class.new.perform(backfill_run)

        expect do
          DataDrip::BackfillRun.create!(
            backfill_class_name: "AddRoleToEmployee",
            batch_size: 2,
            start_at: 1.hour.from_now,
            backfiller: backfiller,
            options: {
              age: 999
            }
          )
        end.to change(DataDrip::BackfillRun, :count).by(1)
      end
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

  describe "planning in pages" do
    # Small pages so a handful of records spans several planning queries.
    before { stub_const("DataDrip::Dripper::PLANNING_PAGE_SIZE", 4) }

    # Like Sidekiq::Shutdown on a deploy: not a StandardError, so the dripper
    # does not mark the run failed and the job is retried.
    let(:worker_killed) { Class.new(Exception) } # rubocop:disable Lint/InheritException

    def create_run(**attributes)
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 2,
        start_at: 1.hour.from_now,
        backfiller: backfiller,
        options: {},
        **attributes
      )
    end

    # The scope's ids each batch covers, in planning order.
    def ids_per_batch(run)
      run.batches.order(:id).map do |batch|
        Employee.where(role: nil, id: batch.start_id..batch.finish_id).pluck(:id)
      end
    end

    def employee_queries(&block)
      queries = []
      callback = lambda do |*, payload|
        queries << payload[:sql] if payload[:sql].include?("employees")
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
      queries
    end

    # Kills the worker on the nth batch it creates, rolling back that page.
    def kill_worker_on_batch(number)
      created = 0
      allow(DataDrip::BackfillRunBatch).to receive(:create!).and_wrap_original do |original, **attributes|
        created += 1
        raise worker_killed if created == number

        original.call(**attributes)
      end
    end

    context "with a large scope" do
      # 3 matching employees from the outer let! plus 10 more.
      before { 10.times { |i| Employee.create!(name: "Extra #{i}", role: nil) } }

      let(:scoped_ids) { Employee.where(role: nil).order(:id).pluck(:id) }

      it "reads ids one page at a time and cuts each page into exact batches" do
        run = create_run

        queries = employee_queries { described_class.new.perform(run) }

        run.reload
        expect(run.total_count).to eq(13)
        expect(run.batches.order(:id).pluck(:batch_size)).to eq([ 2, 2, 2, 2, 2, 2, 1 ])
        expect(ids_per_batch(run)).to eq(scoped_ids.each_slice(2).to_a)
        # Pages of 4, 4, 4 and 1 ids: one query each, not two per batch.
        expect(queries.size).to eq(4)
      end

      it "enqueues the children of each page as soon as it is planned" do
        run = create_run

        expect { described_class.new.perform(run) }.to have_enqueued_job(
          DataDrip::DripperChild
        ).exactly(7).times
        expect(run.batches.pluck(:status).uniq).to eq([ "enqueued" ])
      end

      it "respects amount_of_elements across pages" do
        run = create_run(amount_of_elements: 5)

        described_class.new.perform(run)

        run.reload
        expect(run.total_count).to eq(5)
        expect(run.batches.order(:id).pluck(:batch_size)).to eq([ 2, 2, 1 ])
        expect(ids_per_batch(run).flatten).to eq(scoped_ids.first(5))
      end

      it "stops planning when amount_of_elements is a whole number of pages" do
        run = create_run(amount_of_elements: 4)

        queries = employee_queries { described_class.new.perform(run) }

        run.reload
        expect(run.total_count).to eq(4)
        expect(ids_per_batch(run).flatten).to eq(scoped_ids.first(4))
        expect(queries.size).to eq(1)
      end

      context "when the worker is killed mid-planning" do
        let(:run) { create_run }

        before do
          kill_worker_on_batch(3) # first batch of the second page
          expect { described_class.new.perform(run) }.to raise_error(worker_killed)
          RSpec::Mocks.space.proxy_for(DataDrip::BackfillRunBatch).reset
        end

        it "leaves the run running with the committed pages only" do
          run.reload
          expect(run.status).to eq("running")
          expect(run).to be_planning
          expect(run.total_count).to be_nil
          expect(ids_per_batch(run)).to eq(scoped_ids.first(4).each_slice(2).to_a)
          expect(run.batches.pluck(:status).uniq).to eq([ "enqueued" ])
        end

        it "resumes after the last planned batch on retry without duplicating batches" do
          described_class.new.perform(DataDrip::BackfillRun.find(run.id))

          run.reload
          expect(run.total_count).to eq(13)
          expect(ids_per_batch(run)).to eq(scoped_ids.each_slice(2).to_a)
          expect(run.batches.group(:start_id).count.values.uniq).to eq([ 1 ])
        end

        it "does not let finished children settle the run before planning ends" do
          run.batches.each { |batch| DataDrip::DripperChild.new.perform(batch) }
          expect(run.reload.status).to eq("running")

          described_class.new.perform(DataDrip::BackfillRun.find(run.id))
          expect(run.reload.status).to eq("running")

          run.batches.enqueued.each { |batch| DataDrip::DripperChild.new.perform(batch) }
          run.reload
          expect(run.status).to eq("completed")
          expect(run.processed_count).to eq(13)
        end

        it "completes a run whose children all finished while it was planning" do
          run.batches.each { |batch| DataDrip::DripperChild.new.perform(batch) }
          # Nothing left to plan after the first page.
          Employee.where(role: nil).update_all(role: "manager")

          described_class.new.perform(DataDrip::BackfillRun.find(run.id))

          run.reload
          expect(run.status).to eq("completed")
          expect(run.total_count).to eq(4)
        end

        it "does not plan any further once the run was stopped" do
          run.reload.stopped!

          expect do
            described_class.new.perform(DataDrip::BackfillRun.find(run.id))
          end.not_to change(DataDrip::BackfillRunBatch, :count)
          expect(run.reload.status).to eq("stopped")
        end
      end
    end

    context "with a sparse scope" do
      before do
        Employee.where(role: nil).update_all(role: "manager")
        # Matching ids scattered between long runs of non-matching ones.
        3.times do |i|
          Employee.create!(name: "Match #{i}", role: nil)
          25.times { Employee.create!(name: "Other", role: "manager") }
        end
      end

      it "only creates batches around matching ids" do
        run = create_run
        matching = Employee.where(role: nil).order(:id).pluck(:id)

        described_class.new.perform(run)

        run.reload
        expect(run.total_count).to eq(3)
        expect(run.batches.order(:id).pluck(:start_id, :finish_id)).to eq(
          [ [ matching[0], matching[1] ], [ matching[2], matching[2] ] ]
        )
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
