# frozen_string_literal: true

module DataDrip
  # A run and its remote legs, seen as one thing.
  #
  # The coordinator's run row only ever describes what happened in the
  # coordinator's own cell, so reading it alone reports a group as "completed"
  # while another cell is still working or has failed outright. This object owns
  # the group-level questions instead: what is the group's status, may it still
  # change, and what does each cell currently look like.
  #
  # It is built either from the cached dispatch rows alone (the run lists, which
  # must not make network calls) or refreshed against the cells first (the show
  # page and its polling endpoint).
  class MultiCellGroup
    # Ordered least to most demanding of attention. A group reports the worst
    # state any of its legs is in, so a failure or an unfinished cell can never
    # hide behind a coordinator run that happens to have completed.
    STATUS_SEVERITY = {
      "completed" => 0,
      "stopped" => 1,
      "pending" => 2,
      "enqueued" => 3,
      "running" => 4,
      "failed" => 5
    }.freeze

    ACTIVE_STATUSES = %w[pending enqueued running].freeze

    attr_reader :run, :dispatches

    # Loads the groups for a page of runs in one query, so rendering a list of
    # runs costs a fixed number of queries rather than two per row.
    def self.preload_for(runs)
      group_uuids = runs.filter_map { |run| run.group_uuid.presence if run.local? }
      return {} if group_uuids.empty?

      by_group =
        DataDrip::CellDispatch
          .where(group_uuid: group_uuids)
          .order(:cell_id)
          .group_by(&:group_uuid)

      runs.each_with_object({}) do |run, acc|
        dispatches = by_group[run.group_uuid]
        acc[run.id] = new(run: run, dispatches: dispatches) if dispatches.present?
      end
    end

    def initialize(run:, dispatches: nil)
      @run = run
      @dispatches = dispatches || (run.group_uuid.present? ? run.dispatches.to_a : [])
    end

    def multi_cell?
      run.local? && dispatches.any?
    end

    # Total cells the group spans, the coordinator included.
    def cells_count
      dispatches.size + 1
    end

    # The group's status: the worst of the coordinator's own run and every leg
    # we know about. A leg whose dispatch failed never ran at all, so it counts
    # as a failure of the group.
    def status
      statuses = [ run.status.to_s ]
      statuses += dispatches.map { |dispatch| dispatch_status(dispatch) }
      statuses.compact.max_by { |status| STATUS_SEVERITY.fetch(status, 0) }
    end

    # Whether anything in the group may still change. Drives both the polling
    # decision and whether the group is safe to treat as finished.
    def active?
      return true if ACTIVE_STATUSES.include?(run.status.to_s)

      dispatches.any?(&:active?)
    end

    # True when every leg's state is known — i.e. no cell is merely unreachable.
    # An unreachable leg is not a failure, but it does mean the group's reported
    # status is provisional.
    def complete_picture?
      dispatches.none? { |dispatch| dispatch.dispatched? && dispatch.last_run_status.nil? } &&
        dispatches.none?(&:unreachable?)
    end

    # Refreshes every leg that can still change and caches what it reports.
    # Settled legs are served from cache: their run reached a terminal state, so
    # there is nothing left to ask, and the group's page stays readable even
    # after those cells are decommissioned.
    def refresh!(client: DataDrip::CellClient.new, deadline: DataDrip::CellFanout::DEFAULT_DEADLINE_SECONDS)
      stale = dispatches.select { |dispatch| dispatch.dispatched? && !dispatch.settled? }
      return self if stale.empty?

      by_cell = stale.index_by(&:cell_id)
      results =
        DataDrip::CellFanout.call(by_cell.keys, deadline: deadline) do |cell_id|
          client.fetch_group(cell_id: cell_id, group_uuid: run.group_uuid)
        end

      results.each { |cell_id, result| apply(by_cell.fetch(cell_id), result) }
      self
    end

    private

    def apply(dispatch, result)
      if result.is_a?(Exception) || !result.success?
        dispatch.record_unreachable!
      else
        dispatch.record_snapshot!(result.body)
      end
    end

    # What a leg contributes to the group status. A leg we have never reached
    # contributes nothing (it cannot lower the group's status, and `active?`
    # already keeps the group unfinished).
    def dispatch_status(dispatch)
      return "failed" if dispatch.failed?
      return "pending" if dispatch.pending?

      dispatch.last_run_status
    end
  end
end
