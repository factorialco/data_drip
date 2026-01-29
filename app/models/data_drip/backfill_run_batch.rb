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
          backfill_options: backfill_run.options
        )

      migration
        .scope
        .in_batches(
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
