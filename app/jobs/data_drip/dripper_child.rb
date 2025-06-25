module DataDrip
  class DripperChild < ActiveJob::Base
    queue_as :data_drip_child

    def perform(backfill_run, start_id, finish_id)
      new_backfill_child = backfill_run.backfill_class.new(batch_size: backfill_run.batch_size, sleep_time: 5)
      new_backfill_child.call(start_id: start_id, finish_id: finish_id)
    end
  end
end
