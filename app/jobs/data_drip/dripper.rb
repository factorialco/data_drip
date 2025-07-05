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

      BackfillRun.transaction do
        batch_ids.each do |batch|
          BackfillRunBatch.create!(
            backfill_run: backfill_run,
            status: :pending,
            batch_size: backfill_run.batch_size,
            start_id: batch[:start_id],
            finish_id: batch[:finish_id]
          )
        end
      end
    rescue StandardError => e
      backfill_run.failed!
      backfill_run.update(error_message: e.message)
      raise e
    end
  end
end
