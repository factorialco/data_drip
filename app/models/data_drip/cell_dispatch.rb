# frozen_string_literal: true

module DataDrip
  # Coordinator-side record of "this group must also run in that cell". One row
  # per (group, remote cell), created together with the local run and delivered
  # by CellDispatcherJob. The unique (group_uuid, cell_id) index — mirrored on
  # the run tables of the receiving cells — makes delivery retries idempotent.
  class CellDispatch < ApplicationRecord
    self.table_name = "data_drip_cell_dispatches"

    validates :group_uuid, presence: true
    validates :cell_id, presence: true

    DataDrip.cross_rails_enum(self, :runnable_type, %i[backfill script])
    DataDrip.cross_rails_enum(self, :status, %i[pending dispatched failed])

    def enqueue
      DataDrip::CellDispatcherJob.perform_later(self)
    end

    # Re-deliver a failed dispatch with the payload frozen at creation time
    # (e.g. after the target cell caught up on a deploy).
    def retry!
      update!(status: :pending, error_message: nil)
      enqueue
    end
  end
end
