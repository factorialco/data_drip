# frozen_string_literal: true

require "spec_helper"

RSpec.describe "limited parallel backfill workers", type: :job do
  let!(:backfiller) { User.create!(name: "Test User") }
  let!(:employees) do
    5.times.map do |index|
      Employee.create!(name: "Employee #{index}", role: nil, age: 25)
    end
  end

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ParallelWorkersSpec::BlockingBackfill.reset!
    ParallelWorkersSpec::BlockingScopeBackfill.reset!
  end

  def build_run(max_parallel_workers: 2, status: :running)
    run =
      DataDrip::BackfillRun.new(
        backfill_class_name: "ParallelWorkersSpec::BlockingBackfill",
        batch_size: 1,
        start_at: 1.hour.from_now,
        backfiller: backfiller,
        options: {},
        max_parallel_workers: max_parallel_workers
      )
    run.save!(validate: false)
    run.update_column(:status, DataDrip::BackfillRun.statuses.fetch(status))
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    run
  end

  def build_batch(run, employee, status: :pending)
    batch =
      DataDrip::BackfillRunBatch.create!(
        backfill_run: run,
        status: status,
        batch_size: 1,
        start_id: employee.id,
        finish_id: employee.id
      )
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    batch
  end

  def run_concurrently(count, &block)
    ready = Queue.new
    release = Queue.new
    threads =
      count.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            release.pop
            block.call
          end
        end
      end

    count.times { ready.pop }
    count.times { release << true }
    threads.each(&:value)
  end

  def child_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
      job[:job] == DataDrip::DripperChild
    end
  end

  it "serializes concurrent dispatchers and never reserves beyond the limit" do
    run = build_run(max_parallel_workers: 2)
    employees.each { |employee| build_batch(run, employee) }

    run_concurrently(2) do
      DataDrip::BackfillRun.find(run.id).enqueue_available_batches!
    end

    expect(run.batches.enqueued.count).to eq(2)
    expect(run.batches.pending.count).to eq(3)
    expect(child_jobs.count).to eq(2)
  end

  it "releases reserved slots when enqueueing a child job fails" do
    run = build_run(max_parallel_workers: 2)
    employees.first(3).each { |employee| build_batch(run, employee) }
    attempts = 0
    allow(DataDrip::DripperChild).to receive(:perform_later).and_wrap_original do |method, *args|
      attempts += 1
      raise "queue unavailable" if attempts == 1

      method.call(*args)
    end

    expect { run.enqueue_available_batches! }.to raise_error(
      StandardError,
      "queue unavailable"
    )

    expect(run.batches.enqueued.count).to eq(0)
    expect(run.batches.pending.count).to eq(3)

    run.enqueue_available_batches!

    expect(run.batches.enqueued.count).to eq(2)
    expect(run.batches.pending.count).to eq(1)
    expect(child_jobs.count).to eq(2)
  end

  it "keeps limits isolated between different runs" do
    first_run = build_run(max_parallel_workers: 1)
    second_run = build_run(max_parallel_workers: 2)
    employees.first(2).each { |employee| build_batch(first_run, employee) }
    employees.last(3).each { |employee| build_batch(second_run, employee) }

    runs = Queue.new
    runs << first_run.id
    runs << second_run.id
    run_concurrently(2) do
      DataDrip::BackfillRun.find(runs.pop).enqueue_available_batches!
    end

    expect(first_run.batches.enqueued.count).to eq(1)
    expect(first_run.batches.pending.count).to eq(1)
    expect(second_run.batches.enqueued.count).to eq(2)
    expect(second_run.batches.pending.count).to eq(1)
    expect(child_jobs.count).to eq(3)
  end

  it "atomically claims a duplicated parent-job delivery" do
    run =
      DataDrip::BackfillRun.new(
        backfill_class_name: "ParallelWorkersSpec::BlockingScopeBackfill",
        batch_size: 1,
        start_at: 1.hour.from_now,
        backfiller: backfiller,
        options: {},
        max_parallel_workers: 1
      )
    run.save!(validate: false)
    run.update_column(:status, DataDrip::BackfillRun.statuses.fetch(:enqueued))
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    first_delivery =
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          DataDrip::Dripper.new.perform(DataDrip::BackfillRun.find(run.id))
        end
      end

    ParallelWorkersSpec::BlockingScopeBackfill.entered.pop
    DataDrip::Dripper.new.perform(DataDrip::BackfillRun.find(run.id))
    ParallelWorkersSpec::BlockingScopeBackfill.release << true
    first_delivery.value

    expect(run.reload.batches.count).to eq(employees.count)
    expect(run.batches.enqueued.count).to eq(1)
    expect(run.batches.pending.count).to eq(employees.count - 1)
    expect(child_jobs.count).to eq(1)
  end

  it "does not execute a duplicated batch delivery twice" do
    run = build_run(max_parallel_workers: 1)
    batch = build_batch(run, employees.first, status: :enqueued)

    first_delivery =
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          DataDrip::DripperChild.new.perform(
            DataDrip::BackfillRunBatch.find(batch.id)
          )
        end
      end

    expect(ParallelWorkersSpec::BlockingBackfill.entered.pop).to eq(
      employees.first.id
    )

    DataDrip::DripperChild.new.perform(
      DataDrip::BackfillRunBatch.find(batch.id)
    )
    ParallelWorkersSpec::BlockingBackfill.release << true
    first_delivery.value

    expect(ParallelWorkersSpec::BlockingBackfill.processed_ids).to eq(
      [ employees.first.id ]
    )
    expect(batch.reload.status).to eq("completed")
    expect(run.reload.processed_count).to eq(1)
  end

  it "lets concurrent completions enqueue the next batch only once" do
    run = build_run(max_parallel_workers: 2)
    first_batch = build_batch(run, employees.first, status: :enqueued)
    second_batch = build_batch(run, employees.second, status: :enqueued)
    next_batch = build_batch(run, employees.third)

    workers =
      [ first_batch, second_batch ].map do |batch|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            DataDrip::DripperChild.new.perform(
              DataDrip::BackfillRunBatch.find(batch.id)
            )
          end
        end
      end

    2.times { ParallelWorkersSpec::BlockingBackfill.entered.pop }
    2.times { ParallelWorkersSpec::BlockingBackfill.release << true }
    workers.each(&:value)

    expect(next_batch.reload.status).to eq("enqueued")
    expect(child_jobs.count).to eq(1)
    expect(run.batches.where(status: %i[enqueued running]).count).to be <= 2
  end

  it "releases a slot and dispatches the next batch when a worker fails" do
    run = build_run(max_parallel_workers: 1)
    run.update_column(
      :backfill_class_name,
      "ParallelWorkersSpec::SelectiveFailBackfill"
    )
    failing_batch = build_batch(run, employees.first, status: :enqueued)
    next_batch = build_batch(run, employees.second)

    expect do
      DataDrip::DripperChild.new.perform(failing_batch)
    end.to raise_error(StandardError, "boom on #{employees.first.id}")

    expect(failing_batch.reload.status).to eq("failed")
    expect(failing_batch.error_message).to eq("boom on #{employees.first.id}")
    expect(next_batch.reload.status).to eq("enqueued")
    expect(child_jobs.count).to eq(1)
    expect(run.reload.status).to eq("running")

    DataDrip::DripperChild.new.perform(next_batch)

    expect(next_batch.reload.status).to eq("completed")
    expect(run.reload.status).to eq("failed")
  end

  it "serializes concurrent retries and still respects the limit" do
    run = build_run(max_parallel_workers: 2, status: :stopped)
    employees.first(3).each do |employee|
      build_batch(run, employee, status: :failed)
    end

    run_concurrently(2) do
      DataDrip::BackfillRun.find(run.id).retry_failed_batches!
    end

    expect(run.reload.status).to eq("running")
    expect(run.batches.enqueued.count).to eq(2)
    expect(run.batches.pending.count).to eq(1)
    expect(child_jobs.count).to eq(2)
  end

  it "cannot dispatch work after a concurrent stop wins" do
    run = build_run(max_parallel_workers: 2)
    employees.each { |employee| build_batch(run, employee) }

    actions = [
      -> { DataDrip::BackfillRun.find(run.id).stop! },
      -> { DataDrip::BackfillRun.find(run.id).enqueue_available_batches! }
    ]
    run_concurrently(2) { actions.shift.call }

    expect(run.reload.status).to eq("stopped")
    expect(run.batches.pending.count).to eq(0)
    expect(run.batches.where(status: %i[enqueued running]).count).to be <= 2

    run.batches.enqueued.find_each do |batch|
      DataDrip::DripperChild.new.perform(batch)
    end
    expect(run.batches.reload.pluck(:status).uniq).to eq([ "stopped" ])
  end
end

module ParallelWorkersSpec
  class BlockingBackfill < DataDrip::Backfill
    class << self
      attr_accessor :entered, :release, :processed_ids

      def reset!
        self.entered = Queue.new
        self.release = Queue.new
        self.processed_ids = []
      end
    end

    def scope
      Employee.all
    end

    def process_element(element)
      self.class.entered << element.id
      self.class.release.pop
      self.class.processed_ids << element.id
    end
  end

  class BlockingScopeBackfill < DataDrip::Backfill
    class << self
      attr_accessor :entered, :release

      def reset!
        self.entered = Queue.new
        self.release = Queue.new
      end
    end

    def scope
      self.class.entered << true
      self.class.release.pop
      Employee.all
    end

    def process_element(_element); end
  end

  class SelectiveFailBackfill < DataDrip::Backfill
    def scope
      Employee.all
    end

    def process_element(element)
      raise "boom on #{element.id}" if element.id == Employee.minimum(:id)
    end
  end
end
