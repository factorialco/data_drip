# frozen_string_literal: true

module DataDrip
  # Coordinator-side record of "this group must also run in that cell". One row
  # per (group, remote cell), created together with the local run and delivered
  # by CellDispatcherJob. The unique (group_uuid, cell_id) index — mirrored on
  # the run tables of the receiving cells — makes delivery retries idempotent.
  #
  # It also caches the leg's last known state (`last_status`, `last_snapshot`),
  # refreshed whenever the coordinator polls that cell. That cache is what lets
  # the run lists show a group's real worst-of status without fanning out, and
  # what keeps a finished group's page readable after its cells are gone.
  class CellDispatch < ApplicationRecord
    self.table_name = "data_drip_cell_dispatches"

    validates :group_uuid, presence: true
    validates :cell_id, presence: true

    DataDrip.cross_rails_enum(self, :runnable_type, %i[backfill script])
    DataDrip.cross_rails_enum(self, :status, %i[pending dispatched failed])

    TERMINAL_RUN_STATUSES = %w[completed failed stopped].freeze

    def enqueue
      DataDrip::CellDispatcherJob.perform_later(self)
    end

    # Re-deliver a failed dispatch with the payload frozen at creation time
    # (e.g. after the target cell caught up on a deploy).
    def retry!
      update!(status: :pending, error_message: nil)
      enqueue
    end

    # The leg's own run status as of the last successful poll, or nil if we have
    # never reached the cell.
    def last_run_status
      last_status.presence
    end

    # A leg whose run reached a terminal state can never change again, so the
    # coordinator stops polling it and serves the cached snapshot forever.
    def settled?
      dispatched? && TERMINAL_RUN_STATUSES.include?(last_run_status)
    end

    # Whether this leg may still change, and therefore whether the show page
    # should keep polling. An undelivered dispatch is still in flight; a failed
    # one waits for a human to press "Retry dispatch"; a delivered one is active
    # until we have seen it reach a terminal status.
    def active?
      return true if pending?
      return false if failed?

      !settled?
    end

    # Records what the cell reported for this group. `runs` is the Cell API's
    # snapshot list; a group holds at most one run per cell.
    def record_snapshot!(snapshot)
      run = Array(snapshot["runs"]).first
      return if run.nil?

      update!(
        last_status: run["status"],
        last_snapshot: run,
        last_synced_at: Time.current,
        remote_run_id: run["id"] || remote_run_id,
        unreachable_since: nil
      )
    end

    # Records that the cell could not be reached, without discarding what it
    # last told us — the page keeps rendering the stale snapshot, flagged as
    # stale, instead of blanking out.
    def record_unreachable!
      return if unreachable_since.present?

      update!(unreachable_since: Time.current)
    end

    def unreachable?
      unreachable_since.present?
    end
  end
end
