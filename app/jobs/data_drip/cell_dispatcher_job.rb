# frozen_string_literal: true

module DataDrip
  # Delivers one CellDispatch: asks the target cell's Cell API to create its
  # copy of the run. Delivery is idempotent — the receiving cell keys runs by
  # (group_uuid, cell_id) — so duplicate deliveries and retries are safe.
  class CellDispatcherJob < DataDrip.base_job_class.safe_constantize
    queue_as { DataDrip.queue_name }

    discard_on ActiveJob::DeserializationError

    def perform(dispatch)
      return if dispatch.dispatched?

      response = deliver(dispatch)

      if response.success?
        dispatch.update!(
          status: :dispatched,
          remote_run_id: response.body["id"],
          error_message: nil
        )
      else
        dispatch.update!(status: :failed, error_message: failure_message(response))
        # A 4xx is a considered rejection (validation, unknown class after a
        # deploy lag…) that needs a human and the "Retry dispatch" button; a
        # 5xx is worth going through the queue's normal retry policy.
        if response.status >= 500
          raise DataDrip::CellTransport::Error,
                "Cell #{dispatch.cell_id} responded with HTTP #{response.status}"
        end
      end
    rescue DataDrip::CellTransport::Error => e
      # Mark the failure before re-raising so the UI shows it even while the
      # queue keeps retrying (a later success flips it back to dispatched).
      # Recorded on every attempt, not just the first: the operator deciding
      # whether to press "Retry dispatch" needs the latest reason, not the one
      # from an attempt several backoffs ago.
      dispatch.update!(status: :failed, error_message: e.message) unless dispatch.dispatched?
      raise
    end

    private

    def deliver(dispatch)
      client = DataDrip::CellClient.new

      if dispatch.script?
        client.create_script_run(cell_id: dispatch.cell_id, payload: dispatch.payload)
      else
        client.create_backfill_run(cell_id: dispatch.cell_id, payload: dispatch.payload)
      end
    end

    def failure_message(response)
      errors = response.body["errors"] if response.body.is_a?(Hash)
      details = Array(errors).join(", ")
      details.presence || "Cell responded with HTTP #{response.status}"
    end
  end
end
