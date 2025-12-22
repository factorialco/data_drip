# frozen_string_literal: true

module DataDrip
  class DripperChild < ApplicationJob
    queue_as :data_drip_child

    def perform(backfill_run_batch)
      parent = backfill_run_batch.backfill_run
      if parent.stopped?
        backfill_run_batch.stopped!
        return
      end

      backfill_run_batch.run!
      backfill_run_batch.completed!

      parent.increment!(:processed_count, backfill_run_batch.batch_size)
      parent.completed! if parent.batches.where.not(status: :completed).count.zero?
    rescue StandardError => e
      backfill_run_batch.failed!
      backfill_run_batch.update!(error_message: e.message)
      raise e
    end
  end
end
