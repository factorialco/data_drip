# frozen_string_literal: true

module DataDrip
  class DripperChild < DataDrip.base_job_class.safe_constantize
    queue_as { DataDrip.child_queue_name }

    def perform(backfill_run_batch)
      # Idempotency guard: a batch is only processed once. A duplicate delivery
      # finds it already running/terminal and is a no-op, so records are not
      # re-processed and processed_count is not double-counted. Runs before the
      # stopped check so an already-finished batch is never flipped to stopped.
      return unless backfill_run_batch.pending? || backfill_run_batch.enqueued?

      parent = backfill_run_batch.backfill_run
      if parent.stopped?
        backfill_run_batch.stopped!
        return
      end

      backfill_run_batch.run!
      backfill_run_batch.completed!

      parent.increment!(:processed_count, backfill_run_batch.batch_size)
      parent.finalize_if_batches_finished!
    rescue StandardError => e
      backfill_run_batch.failed!
      backfill_run_batch.update!(error_message: e.message)
      parent.finalize_if_batches_finished!
      raise e
    end
  end
end
