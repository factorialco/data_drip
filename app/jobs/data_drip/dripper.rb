# frozen_string_literal: true

module DataDrip
  class Dripper < DataDrip.base_job_class.safe_constantize
    queue_as { DataDrip.queue_name }

    def perform(backfill_run)
      backfill_run.with_run_hooks(:running) do
        backfill_run.running!

        new_backfill =
          backfill_run.backfill_class.new(
            batch_size: backfill_run.batch_size,
            sleep_time: 5,
            backfill_options: backfill_run.options || {}
          )
        scope = new_backfill.scope

        if backfill_run.amount_of_elements.present? &&
             backfill_run.amount_of_elements.positive?
          scope = scope.limit(backfill_run.amount_of_elements)
        end

        batch_ids =
          scope
            .find_in_batches(batch_size: backfill_run.batch_size)
            .map do |batch|
              {
                finish_id: batch.last.id,
                start_id: batch.first.id,
                actual_size: batch.size
              }
            end

        backfill_run.update!(total_count: scope.count)

        if backfill_run.amount_of_elements.present? &&
             backfill_run.amount_of_elements < backfill_run.batch_size
          backfill_run.batch_size = backfill_run.amount_of_elements
          backfill_run.save!
        end

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
      end
    rescue StandardError => e
      backfill_run.failed!
      backfill_run.update!(error_message: e.message)
      raise e
    end
  end
end
