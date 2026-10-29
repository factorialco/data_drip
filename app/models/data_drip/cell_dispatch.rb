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
    # `cancelled`: the group was stopped before this dispatch was delivered, so
    # it must never be (re)delivered. A delivery already in flight that lands
    # anyway is stopped by CellDispatcherJob.
    DataDrip.cross_rails_enum(self, :status, %i[pending dispatched failed cancelled])

    # Dispatches whose delivery is still owed: waiting for the job, or failed
    # and waiting for a queue retry or a human.
    UNDELIVERED_STATUSES = %i[pending failed].freeze

    # Recorded when the cell answers but no longer holds the leg: someone
    # deleted it there before it ran. It will never run, so it is as final as
    # any terminal status.
    DELETED_STATUS = "deleted"

    TERMINAL_RUN_STATUSES = [ *%w[completed failed stopped], DELETED_STATUS ].freeze

    # Terminal statuses a backfill leaves again when someone retries its failed
    # batches, from the coordinator or from that cell's own UI.
    REVIVABLE_RUN_STATUSES = %w[failed stopped].freeze

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

    # A leg whose run reached a terminal state: the show page stops polling it.
    def settled?
      dispatched? && TERMINAL_RUN_STATUSES.include?(last_run_status)
    end

    # A settled leg that can never change again, so the coordinator never asks
    # about it again and serves the cached snapshot forever. A failed or stopped
    # backfill is settled but not final: retrying its batches in its own cell
    # brings it back, and only a later poll can tell.
    def final?
      settled? && !(backfill? && REVIVABLE_RUN_STATUSES.include?(last_run_status))
    end

    # Whether this leg may still change, and therefore whether the show page
    # should keep polling. An undelivered dispatch is still in flight; a failed
    # one waits for a human to press "Retry dispatch"; a delivered one is active
    # until we have seen it reach a terminal status.
    def active?
      return true if pending?
      return false if failed? || cancelled?

      !settled?
    end

    # Whether the cell deleted this leg itself (see DELETED_STATUS).
    def deleted_remotely?
      last_run_status == DELETED_STATUS
    end

    # Records what the cell reported for this group. `runs` is the Cell API's
    # snapshot list; a group holds at most one run per cell. A delivered leg the
    # cell no longer reports was deleted there, and is recorded as such: left
    # unrecorded it would look forever unsynced, so the coordinator would keep
    # polling it and the group would never finish.
    def record_snapshot!(snapshot)
      run = Array(snapshot["runs"]).first
      return record_deleted! if run.nil?

      record_run!(run)
    end

    # Records one run snapshot, as the Cell API returns it from its mutations.
    def record_run!(run)
      update!(
        last_status: run["status"],
        last_snapshot: run,
        last_synced_at: Time.current,
        remote_run_id: run["id"] || remote_run_id,
        unreachable_since: nil
      )
    end

    def record_deleted!
      update!(
        last_status: DELETED_STATUS,
        last_synced_at: Time.current,
        unreachable_since: nil
      )
    end

    # Records that the cell could not be reached, without discarding what it
    # last told us — the page keeps rendering the stale snapshot, flagged as
    # stale, instead of blanking out. Every failed attempt touches the row, so
    # the coordinator can back off a cell that keeps not answering (see
    # MultiCellGroup#stale_dispatches) instead of asking on every poll.
    def record_unreachable!
      return touch if unreachable_since.present?

      update!(unreachable_since: Time.current)
    end

    def unreachable?
      unreachable_since.present?
    end
  end
end
