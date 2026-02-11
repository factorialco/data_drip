# frozen_string_literal: true

module DataDrip
  class DripperChild < DataDrip.base_job_class.safe_constantize
    queue_as { DataDrip.queue_name }

    def perform(backfill_run_batch)
      parent = backfill_run_batch.backfill_run
      if parent.stopped?
        backfill_run_batch.stopped!
        return
      end

      backfill_run_batch.run!
      backfill_run_batch.completed!

      parent.increment!(:processed_count, backfill_run_batch.batch_size)
      if parent.batches.where.not(status: :completed).count.zero?
        parent.completed!
      end
    rescue StandardError => e
      backfill_run_batch.failed!
      backfill_run_batch.update!(error_message: e.message)
      raise e
    end
  end
end
