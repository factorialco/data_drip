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
    def fanout_to_dispatched(dispatches)
      by_cell = dispatches.select(&:dispatched?).index_by(&:cell_id)

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
