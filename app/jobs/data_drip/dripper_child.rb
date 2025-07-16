module DataDrip
  class DripperChild < ActiveJob::Base
    queue_as :data_drip_child

    def perform(backfill_run_batch)
      backfill_run_batch.run!
      backfill_run_batch.completed!

      parent = backfill_run_batch.backfill_run
      parent.increment!(:processed_count, backfill_run_batch.batch_size)
      parent.completed! if parent.batches.where.not(status: :completed).count == 0
    rescue StandardError => e
      backfill_run_batch.failed!
      backfill_run_batch.update(error_message: e.message)
      raise e
    end
  end
end
