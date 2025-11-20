module DataDrip
  class Dripper < ActiveJob::Base
    queue_as :data_drip

    def perform(backfill_run)
      backfill_run.running!

      new_backfill =
        backfill_run.backfill_class.new(
          batch_size: backfill_run.batch_size,
          sleep_time: 5,
          options: backfill_run.options || {}
        )
      scope = new_backfill.scope
      
      # Apply options as dynamic filters to the scope for efficient batch creation
      if backfill_run.options.present?
        backfill_run.options.each do |key, value|
          next unless value.present?
          
          if backfill_run.backfill_class.backfill_options.attribute_types[key.to_s]
            attribute_type = backfill_run.backfill_class.backfill_options.attribute_types[key.to_s]
            converted_value = attribute_type.cast(value)
            scope = scope.where(key => converted_value)
          else
            scope = scope.where(key => value)
          end
        end
      end

      scope =
        scope.limit(
          backfill_run.amount_of_elements
        ) if backfill_run.amount_of_elements.present? &&
        backfill_run.amount_of_elements > 0

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

      backfill_run.update(total_count: scope.count)

      if backfill_run.amount_of_elements.present? &&
           backfill_run.amount_of_elements < backfill_run.batch_size
        backfill_run.batch_size = backfill_run.amount_of_elements
        backfill_run.save
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
    rescue StandardError => e
      backfill_run.failed!
      backfill_run.update(error_message: e.message)
      raise e
    end
  end
end
