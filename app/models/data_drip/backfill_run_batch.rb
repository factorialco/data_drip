module DataDrip
  class BackfillRunBatch < ApplicationRecord
    self.table_name = "data_drip_backfill_run_batches"

    belongs_to :backfill_run, class_name: "DataDrip::BackfillRun"

    validates :start_id, presence: true
    validates :finish_id, presence: true
    validates :batch_size, presence: true, numericality: { greater_than: 0 }

    enum :status, %i[pending enqueued running completed failed stopped], validate: true, default: :pending

    after_commit :enqueue, on: :create

    def enqueue
      return unless pending?

      DataDrip::DripperChild.perform_later(self)
      enqueued!
    end

    def run!
      running!
      backfill = backfill_run.backfill_class.new(batch_size: batch_size, sleep_time: 5)
      backfill.call(start_id: start_id, finish_id: finish_id)
    end
  end
end
