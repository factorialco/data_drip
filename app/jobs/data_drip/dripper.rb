module DataDrip
  class Dripper < ActiveJob::Base
    queue_as :data_drip

    def perform(backfill_run)
      backfill_run.running!

      new_backfill = backfill_run.backfill_class.new(batch_size: backfill_run.batch_size, sleep_time: 5)

      batch_ids = new_backfill.scope.find_in_batches(batch_size: backfill_run.batch_size).map do |batch|
        { finish_id: batch.last.id,
          start_id: batch.first.id }
      end

      backfill_run.update(total_count: new_backfill.count)

      batch_ids.each do |batch|
        DripperChild.perform_later(backfill_run, batch[:start_id], batch[:finish_id])
      end
    rescue StandardError => e
      backfill_run.failed!
      backfill_run.update(error_message: e.message)
      raise e
    end
  end
end
