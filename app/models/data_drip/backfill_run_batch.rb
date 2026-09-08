# frozen_string_literal: true

module DataDrip
  class BackfillRunBatch < ApplicationRecord
    self.table_name = "data_drip_backfill_run_batches"

    belongs_to :backfill_run, class_name: "DataDrip::BackfillRun"

    validates :start_id, presence: true
    validates :finish_id, presence: true
    validates :batch_size, presence: true, numericality: { greater_than: 0 }

    DataDrip.cross_rails_enum(
      self,
      :status,
      %i[pending enqueued running completed failed stopped]
    )

    after_commit :enqueue,
                 on: :create,
                 unless: :parallel_workers_managed_by_run?
    after_commit :run_hooks

    def enqueue
      return unless pending?

      # The transition MUST commit before the job is enqueued. A worker can pick
      # the job up the instant it is visible; if it runs the batch to completion
      # first, a trailing `enqueued!` would stomp that terminal state and the
      # parent run, seeing a forever-active batch, would never settle.
      enqueued!
      DataDrip::DripperChild.perform_later(self)
    end

    def run!
      return false unless claim_for_execution!

      migration =
        backfill_run.backfill_class.new(
          batch_size: batch_size,
          backfill_options: backfill_run.options
        )

      migration
        .scope
        .in_batches(
          of: batch_size,
          start: start_id,
          finish: finish_id
        ) do |batch|
          migration.send(:process_batch, batch)
          # Throttle between batches using the configured DataDrip.sleep_time
          # (defaults to the migration's sleep_time).
          sleep migration.sleep_time
        end

      true
    end

    def complete_execution!
      backfill_run.with_lock do
        with_lock do
          next false unless running?

          backfill_run.increment!(:processed_count, batch_size)
          completed!
          true
        end
      end
    end

    private

    def claim_for_execution!
      backfill_run.with_lock do
        with_lock do
          next false unless pending? || enqueued?

          if backfill_run.stopped?
            stopped!
            next false
          end

          running!
          true
        end
      end
    end

    def parallel_workers_managed_by_run?
      backfill_run.parallel_workers_limited?
    end

    def run_hooks
      return unless status_previously_changed?

      hook_name = "on_batch_#{status}"
      if backfill_run.backfill_class.respond_to?(hook_name)
        backfill_run.backfill_class.send(hook_name, self)
      elsif DataDrip.hooks_handler_class.present? &&
            DataDrip.hooks_handler_class.respond_to?(hook_name)
        DataDrip.hooks_handler_class.send(hook_name, self)
      end
    end
  end
end
