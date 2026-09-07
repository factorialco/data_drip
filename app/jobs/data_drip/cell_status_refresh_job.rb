# frozen_string_literal: true

module DataDrip
  # Refreshes a group's per-cell snapshots in the background.
  #
  # The coordinator's show page renders from the snapshots cached on the dispatch
  # rows and enqueues this job when they go stale, rather than fanning out inside
  # the request. Two reasons: a page must not wait on other cells to answer (or
  # hold a web worker while they don't), and rendering a page is a read — hosts
  # routinely send GETs to a read replica where writing is forbidden, so the
  # caching a refresh does cannot happen there.
  class CellStatusRefreshJob < DataDrip.base_job_class.safe_constantize
    queue_as { DataDrip.queue_name }

    discard_on ActiveJob::DeserializationError

    def perform(group_uuid)
      run = coordinator_run(group_uuid)
      return if run.nil?

      DataDrip::MultiCellGroup.new(run: run).refresh!
    end

    private

    def coordinator_run(group_uuid)
      DataDrip::BackfillRun.local.find_by(group_uuid: group_uuid) ||
        DataDrip::ScriptRun.local.find_by(group_uuid: group_uuid)
    end
  end
end
