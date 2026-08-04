# frozen_string_literal: true

module DataDrip
  class Dripper < DataDrip.base_job_class.safe_constantize
    queue_as { DataDrip.queue_name }

    def perform(backfill_run)
      # Idempotency guard: a run only transitions enqueued -> running once.
      # A duplicate delivery (at-least-once queues, accidental re-enqueue) finds
      # the run already running/terminal and is a no-op, so we never build a
      # second set of batches for the same run.
      return unless backfill_run.enqueued?

      backfill_run.running!

      new_backfill =
        backfill_run.backfill_class.new(
          batch_size: backfill_run.batch_size,
          backfill_options: backfill_run.options || {}
        )
      scope = new_backfill.scope

      if backfill_run.amount_of_elements.present? &&
           backfill_run.amount_of_elements.positive?
        scope = scope.limit(backfill_run.amount_of_elements)
      end

      # Only the id bounds and size of each batch are needed; pluck the ids
      # instead of instantiating every record across the whole table.
      batch_ids =
        scope
          .in_batches(of: backfill_run.batch_size)
          .map do |relation|
            ids = relation.pluck(:id)
            start_id, finish_id = ids.minmax
            { start_id: start_id, finish_id: finish_id, actual_size: ids.size }
          end

      # Sum the sizes already plucked above rather than issuing a second count
      # query, which on a large table is the expensive scan we avoid on create.
      backfill_run.update!(
        total_count: batch_ids.sum { |batch| batch[:actual_size] }
      )

      BackfillRun.transaction do
        batch_ids.each do |batch|
          BackfillRunBatch.create!(
            backfill_run: backfill_run,
            status: :pending,
            batch_size: batch[:actual_size],
            start_id: batch[:start_id],
            finish_id: batch[:finish_id]
          )
        end
      end

      # An empty scope yields no batches, so no DripperChild will ever run to
      # settle this run and it would sit in `running` forever. Finalizing here
      # completes it immediately; when batches *were* created they are still
      # active (pending/enqueued) and this is a no-op, leaving the children to
      # settle the run as usual.
      backfill_run.finalize_if_batches_finished!
    rescue StandardError => e
      backfill_run.failed!
      backfill_run.update!(error_message: e.message)
      raise e
    end
  end
end
