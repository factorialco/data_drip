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

    after_commit :enqueue, on: :create
    after_commit :run_hooks

    def enqueue
      return unless pending?
      return unless slot_available?

      DataDrip::DripperChild.perform_later(self)
      enqueued!
    end

    # With a parallelism limit, a batch is only enqueued while fewer than that
    # many siblings are enqueued or running; DripperChild enqueues the next
    # pending batch when one finishes.
    def slot_available?
      limit = backfill_run.backfill_class&.max_parallel_batches
      return true if limit.nil?

      backfill_run.batches.where(status: %i[enqueued running]).count < limit
    end

    def run!
      running!
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
    end

    private

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
