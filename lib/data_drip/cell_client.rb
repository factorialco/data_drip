# frozen_string_literal: true

module DataDrip
  # Thin wrapper over the configured cell transport that knows the Cell API's
  # paths. Everything the coordinator says to another cell goes through here.
  #
  # Every request carries the intended `target_cell_id` so the receiving cell
  # can reject requests the routing layer delivered to the wrong place.
  class CellClient
    def initialize(transport: DataDrip.cell_transport)
      raise DataDrip::Error, "No DataDrip.cell_transport configured" if transport.nil?

      @transport = transport
    end

    def create_backfill_run(cell_id:, payload:)
      post(cell_id, "/v1/backfill_runs", payload)
    end

    def create_script_run(cell_id:, payload:)
      post(cell_id, "/v1/script_runs", payload)
    end

    def fetch_group(cell_id:, group_uuid:)
      @transport.call(
        cell_id: cell_id,
        method: :get,
        path: "/v1/groups/#{group_uuid}?target_cell_id=#{ERB::Util.url_encode(cell_id)}"
      )
    end

    def stop_backfill_run(cell_id:, run_id:, acting_backfiller_id:)
      post(
        cell_id,
        "/v1/backfill_runs/#{run_id}/stop",
        { acting_backfiller_id: acting_backfiller_id }
      )
    end

    def retry_failed_batches(cell_id:, run_id:, acting_backfiller_id:)
      post(
        cell_id,
        "/v1/backfill_runs/#{run_id}/retry_failed_batches",
        { acting_backfiller_id: acting_backfiller_id }
      )
    end

    def delete_backfill_run(cell_id:, run_id:, acting_backfiller_id:)
      delete(
        cell_id,
        "/v1/backfill_runs/#{run_id}",
        { acting_backfiller_id: acting_backfiller_id }
      )
    end

    def delete_script_run(cell_id:, run_id:, acting_backfiller_id:)
      delete(
        cell_id,
        "/v1/script_runs/#{run_id}",
        { acting_backfiller_id: acting_backfiller_id }
      )
    end

    private

    def post(cell_id, path, payload)
      @transport.call(
        cell_id: cell_id,
        method: :post,
        path: path,
        body: payload.merge(target_cell_id: cell_id)
      )
    end

    def delete(cell_id, path, payload)
      @transport.call(
        cell_id: cell_id,
        method: :delete,
        path: path,
        body: payload.merge(target_cell_id: cell_id)
      )
    end
  end
end
