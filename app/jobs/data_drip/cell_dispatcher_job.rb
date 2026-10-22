# frozen_string_literal: true

module DataDrip
  # Delivers one CellDispatch: asks the target cell's Cell API to create its
  # copy of the run. Delivery is idempotent — the receiving cell keys runs by
  # (group_uuid, cell_id) — so duplicate deliveries and retries are safe.
  class CellDispatcherJob < DataDrip.base_job_class.safe_constantize
    queue_as { DataDrip.resolved_cell_queue_name }

    discard_on ActiveJob::DeserializationError

    def perform(dispatch)
      return unless dispatch.pending? || dispatch.failed?

      response = deliver(dispatch)

      if response.success?
        remote_run_id = response.body["id"]
        # Only a delivery still owed becomes "dispatched". The row may have
        # changed while the request was in flight: deleted with the
        # coordinator's run, or cancelled by a group stop. Either way the leg
        # just created is withdrawn here, since whatever acted on the group
        # could not see a leg that did not exist yet.
        delivered =
          owed(dispatch).update_all(
            status: DataDrip::CellDispatch.statuses[:dispatched],
            remote_run_id: remote_run_id,
            error_message: nil,
            updated_at: Time.current
          )
        withdraw(dispatch, remote_run_id) if delivered.zero?
      else
        mark_failed(dispatch, failure_message(response))
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
      mark_failed(dispatch, e.message)
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

    def owed(dispatch)
      DataDrip::CellDispatch.where(
        id: dispatch.id,
        status: DataDrip::CellDispatch::UNDELIVERED_STATUSES
      )
    end

    # Conditional for the same reason as the delivery: a cancelled dispatch
    # must stay cancelled, or "Retry dispatch" would offer to deliver it again.
    def mark_failed(dispatch, message)
      owed(dispatch).update_all(
        status: DataDrip::CellDispatch.statuses[:failed],
        error_message: message,
        updated_at: Time.current
      )
    end

    # A leg whose dispatch row is gone (its run was deleted) is deleted too; one
    # whose dispatch was cancelled is stopped, which keeps it in that cell's
    # history and on the coordinator's page as a stopped leg.
    def withdraw(dispatch, remote_run_id)
      return if remote_run_id.nil?

      current = DataDrip::CellDispatch.find_by(id: dispatch.id)
      return stop_cancelled(current, remote_run_id) if current&.cancelled? && current.backfill?

      client = DataDrip::CellClient.new
      delete = dispatch.script? ? :delete_script_run : :delete_backfill_run
      response =
        client.public_send(
          delete,
          cell_id: dispatch.cell_id,
          run_id: remote_run_id,
          acting_backfiller_id: dispatch.payload["backfiller_id"]
        )
      return if response.success? || response.status == 404

      log_orphan(dispatch, remote_run_id, "HTTP #{response.status}")
    rescue DataDrip::CellTransport::Error => e
      # The dispatch row is gone or no longer owed, so a queue retry would not
      # deliver it again. Say loudly where the leg is instead.
      log_orphan(dispatch, remote_run_id, e.message)
    end

    def stop_cancelled(dispatch, remote_run_id)
      response =
        DataDrip::CellClient.new.stop_backfill_run(
          cell_id: dispatch.cell_id,
          run_id: remote_run_id,
          acting_backfiller_id: dispatch.payload["backfiller_id"]
        )
      return log_orphan(dispatch, remote_run_id, "HTTP #{response.status}") unless response.success?

      dispatch.update!(status: :dispatched, remote_run_id: remote_run_id)
      dispatch.record_run!(response.body)
    end

    def log_orphan(dispatch, remote_run_id, reason)
      Rails.logger.error(
        {
          event: "data_drip.cell_dispatch.orphaned_leg",
          group_uuid: dispatch.group_uuid,
          cell_id: dispatch.cell_id,
          remote_run_id: remote_run_id,
          reason: reason
        }.to_json
      )
    end

    def failure_message(response)
      errors = response.body["errors"] if response.body.is_a?(Hash)
      details = Array(errors).join(", ")
      details.presence || "Cell responded with HTTP #{response.status}"
    end
  end
end
