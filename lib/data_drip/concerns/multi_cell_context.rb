# frozen_string_literal: true

module DataDrip
  # Shared controller behavior for the multi-cell UI: resolving which cells a
  # new run targets, loading a group's per-cell state for the show pages, and
  # talking to remote cells for fan-out actions.
  module MultiCellContext
    extend ActiveSupport::Concern

    # Outcome of applying one action across a group's remote legs. Callers that
    # can undo (delete) check `all_ok?` before committing; callers that cannot
    # (stop) just report.
    Fanout =
      Struct.new(:outcomes, keyword_init: true) do
        def any?
          outcomes.any?
        end

        def failures
          outcomes.reject { |outcome| outcome[:ok] }
        end

        def all_ok?
          failures.empty?
        end

        def message
          return nil if outcomes.empty?

          if all_ok?
            [ "All #{outcomes.size} remote #{"cell".pluralize(outcomes.size)} acknowledged.", notes ]
              .compact
              .join(" ")
          else
            "Some cells did not acknowledge — #{detail_list(failures)}."
          end
        end

        # Details a cell reported while still acknowledging — a leg that had
        # already run, say. Worth showing even on the happy path.
        def notes
          noted = outcomes.select { |outcome| outcome[:ok] && outcome[:detail].present? }
          return nil if noted.empty?

          "#{detail_list(noted)}."
        end

        def detail_list(entries)
          entries.map { |outcome| "#{outcome[:cell_id]}: #{outcome[:detail]}" }.join("; ")
        end
      end

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

    # Loads everything the per-cell cards need, entirely from the snapshots
    # cached on the dispatch rows, and asks a background job to catch up any leg
    # that has gone stale. The page therefore renders immediately, never waits on
    # another cell, and never writes — which also keeps it safe on hosts that
    # send GETs to a read replica.
    def load_cell_fanout(run)
      @group = run.group
      @group.refresh_later
      @dispatches = @group.dispatches
      @cells_active = @group.active?
    end

    def cell_client
      @cell_client ||= DataDrip::CellClient.new
    end

    def find_dispatched_dispatch(run, cell_id)
      run.dispatches.dispatched.find_by(cell_id: cell_id)
    end

    # Applies an action to every dispatched cell concurrently, against one
    # shared deadline. Sequential delivery would multiply an unreachable cell's
    # timeout by the number of cells and hold a web worker for minutes.
    #
    # The block gets (dispatch) and returns [ok, detail]; transport errors and
    # cells that miss the deadline count as failures.
    def fanout_to_dispatched(dispatches, &)
      fanout_to(dispatches.select(&:dispatched?), &)
    end

    # Deleting the coordinator's run also asks every target cell to delete its
    # leg. A leg that already ran (409) is refused there and stays in that
    # cell's own history, which counts as answered: it will not run again.
    #
    # Not only confirmed deliveries: a dispatch marked failed may still have
    # landed (a read timeout after the cell committed the run), and a pending
    # one may be landing right now. Neither knows the remote run's id, so the
    # cell is asked what it holds for the group, and its answer is what gets
    # deleted. Assuming "nothing there" would leave a leg scheduled in that
    # cell with nothing left to see or stop it from.
    def delete_remote_legs(run)
      fanout_to(run.dispatches.to_a) do |dispatch|
        remote_run_id = dispatch.remote_run_id.presence || landed_run_id(run, dispatch)
        next [ true, nil ] if remote_run_id.nil?

        response = delete_remote_run(dispatch, remote_run_id, run.backfiller_id)
        ok = response.success? || response.status == 404 || response.status == 409
        [ ok, delete_detail(response) ]
      end
    end

    # The id of the run a cell holds for this group, or nil when it holds none.
    # Raises when the cell cannot answer: "could not ask" is not "nothing there".
    def landed_run_id(run, dispatch)
      response = cell_client.fetch_group(cell_id: dispatch.cell_id, group_uuid: run.group_uuid)
      unless response.success?
        raise DataDrip::CellTransport::Error,
              "could not confirm it holds no copy (#{cell_api_error_detail(response)})"
      end

      Array(response.body["runs"]).first&.dig("id")
    end

    def delete_remote_run(dispatch, remote_run_id, acting_backfiller_id)
      delete = dispatch.script? ? :delete_script_run : :delete_backfill_run
      cell_client.public_send(
        delete,
        cell_id: dispatch.cell_id,
        run_id: remote_run_id,
        acting_backfiller_id: acting_backfiller_id
      )
    end

    # What to relay about a delete a cell acknowledged. A leg that had already
    # run is refused there and stays in that cell's history — worth saying, but
    # not a failure: it will not run again either way.
    def delete_detail(response)
      return "already ran — kept as history in that cell" if response.status == 409
      return nil if response.success? || response.status == 404

      cell_api_error_detail(response)
    end

    def fanout_to(dispatches)
      by_cell = dispatches.index_by(&:cell_id)

      results =
        DataDrip::CellFanout.call(by_cell.keys) do |cell_id|
          yield(by_cell.fetch(cell_id))
        end

      outcomes =
        by_cell.keys.map do |cell_id|
          result = results[cell_id]
          ok, detail =
            if result.is_a?(Exception)
              [ false, result.message ]
            else
              result
            end
          { cell_id: cell_id, ok: ok, detail: detail }
        end

      Fanout.new(outcomes: outcomes)
    end

    def cell_api_error_detail(response)
      error = response.body.is_a?(Hash) ? response.body["error"] : nil
      error.presence || "HTTP #{response.status}"
    end
  end
end
