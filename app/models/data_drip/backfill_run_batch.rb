module DataDrip
  class BackfillRunBatch < ApplicationRecord
    self.table_name = "data_drip_backfill_run_batches"

    belongs_to :backfill_run, class_name: "DataDrip::BackfillRun"

    validates :start_id, presence: true
    validates :finish_id, presence: true
    validates :batch_size, presence: true, numericality: { greater_than: 0 }

    DataDrip.cross_rails_enum(
      self,
      :status,
      %i[pending enqueued running completed failed stopped]
    )

    after_commit :enqueue, on: :create

    def enqueue
      return unless pending?

      DataDrip::DripperChild.perform_later(self)
      enqueued!
    end

    def run!
      running!
      migration =
        backfill_run.backfill_class.new(
          batch_size: batch_size,
          sleep_time: 5,
          options: backfill_run.options
        )

      # Apply options as dynamic filters to the scope
      filtered_scope = migration.scope
      if backfill_run.options.present?
        backfill_run.options.each do |key, value|
          next unless value.present?

          # Convert value to correct type based on attribute definition
          if backfill_run.backfill_class.backfill_options.attribute_types[
               key.to_s
             ]
            attribute_type =
              backfill_run.backfill_class.backfill_options.attribute_types[
                key.to_s
              ]
            converted_value = attribute_type.cast(value)
            filtered_scope = filtered_scope.where(key => converted_value)
          else
            filtered_scope = filtered_scope.where(key => value)
          end
        end
      end

      # Process only the filtered records within the ID range
      filtered_scope.in_batches(
        of: batch_size,
        start: start_id,
        finish: finish_id
      ) do |batch|
        migration.send(:process_batch, batch)
        sleep 5
      end
    end
  end
end
