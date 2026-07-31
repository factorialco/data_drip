# frozen_string_literal: true

module DataDrip
  # Shared controller behavior for the multi-cell UI: resolving which cells a
  # new run targets, loading a group's per-cell state for the show pages, and
  # talking to remote cells for fan-out actions.
  module MultiCellContext
    extend ActiveSupport::Concern

    private

    # Which remote cells the create form selected. The current cell is always
    # part of the run (it is where the run is being created) and is therefore
    # never in this list.
    def selected_remote_cell_ids
      return [] unless DataDrip.multi_cell?

      case params[:cell_scope]
      when "local"
        []
      when "custom"
        Array(params[:target_cell_ids]).map(&:to_s)
      else
        DataDrip.remote_cell_ids
      end
    end

    # Loads everything the per-cell cards need: the dispatch records and a live
    # status snapshot from each dispatched cell (bounded by the fetcher's
    # shared deadline; unreachable cells render as such).
    def load_cell_fanout(run)
      @dispatches = run.multi_cell_group? ? run.dispatches.to_a : []
      @cell_statuses = fetch_cell_statuses(run, @dispatches)
      @cells_active = cells_active?(@dispatches, @cell_statuses)
    end

    def fetch_cell_statuses(run, dispatches)
      cells = dispatches.select(&:dispatched?).map(&:cell_id)
      return {} if cells.empty?

      DataDrip::CellStatusFetcher.new(
        group_uuid: run.group_uuid,
        cell_ids: cells
      ).call
    end

    # Whether any remote leg may still change: drives the show page's polling.
    # An unreachable cell counts as active (we don't know, keep looking); a
    # failed dispatch does not (it waits for a human to hit "Retry dispatch").
    def cells_active?(dispatches, statuses)
      dispatches.any? do |dispatch|
        next true if dispatch.pending?
        next false unless dispatch.dispatched?

        snapshot = statuses[dispatch.cell_id]
        next true if snapshot.nil? || snapshot["unreachable"]

        runs = snapshot["runs"] || []
        runs.empty? || runs.any? { |run| !run["terminal"] }
      end
    end

    def cell_client
      @cell_client ||= DataDrip::CellClient.new
    end

    def find_dispatched_dispatch(run, cell_id)
      run.dispatches.dispatched.find_by(cell_id: cell_id)
    end

    # Fans an action out to every dispatched cell and reports per-cell
    # outcomes. The block gets (dispatch) and returns [ok, detail]; transport
    # errors count as failures.
    def fanout_to_dispatched(dispatches)
      outcomes =
        dispatches.select(&:dispatched?).map do |dispatch|
          ok, detail =
            begin
              yield(dispatch)
            rescue DataDrip::CellTransport::Error => e
              [ false, e.message ]
            end
          [ dispatch.cell_id, ok, detail ]
        end

      failures = outcomes.reject { |_cell, ok, _detail| ok }
      return nil if outcomes.empty?

      if failures.empty?
        "All #{outcomes.size} remote #{outcomes.size == 1 ? "cell" : "cells"} acknowledged."
      else
        details =
          failures.map { |cell, _ok, detail| "#{cell}: #{detail}" }.join("; ")
        "Some cells did not acknowledge — #{details}."
      end
    end

    def cell_api_error_detail(response)
      error = response.body.is_a?(Hash) ? response.body["error"] : nil
      error.presence || "HTTP #{response.status}"
    end
  end
end
