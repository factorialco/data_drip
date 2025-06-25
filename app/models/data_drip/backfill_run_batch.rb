module DataDrip
  class BackfillRunBatch < ApplicationRecord
    self.table_name = "data_drip_backfill_run_batches"

    belongs_to :run, class_name: "DataDrip::BackfillRun"

    def enqueue
      return unless pending?

      DataDrip::DripperChild.set(wait_until: start_at).perform_later(self)
      enqueued!
    end
  end
end
