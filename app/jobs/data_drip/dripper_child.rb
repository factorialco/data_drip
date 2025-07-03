module DataDrip
  class DripperChild < ActiveJob::Base
    queue_as :data_drip_child

    def perform(backfill_run_batch)
      backfill_run_batch.run!
      backfill_run_batch.completed!
    rescue StandardError => e
      backfill_run_batch.failed!
      backfill_run_batch.update(error_message: e.message)
      raise e
    end
  end
end
