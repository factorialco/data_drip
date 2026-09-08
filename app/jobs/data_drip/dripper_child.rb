# frozen_string_literal: true

module DataDrip
  class DripperChild < DataDrip.base_job_class.safe_constantize
    queue_as { DataDrip.child_queue_name }

    def perform(backfill_run_batch)
      parent = backfill_run_batch.backfill_run
      return unless backfill_run_batch.run!

      backfill_run_batch.complete_execution!
    rescue StandardError => e
      if backfill_run_batch.reload.running?
        backfill_run_batch.update!(status: :failed, error_message: e.message)
      end
      raise
    ensure
      settle_parent(parent) if parent
    end

    private

    def settle_parent(parent)
      parent.enqueue_available_batches!
      parent.finalize_if_batches_finished!
    end
  end
end
