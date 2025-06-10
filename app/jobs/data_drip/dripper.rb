module DataDrip
  class Dripper < ActiveJob::Base
    queue_as :data_drip

    def perform(backfill_run)
      backfill_run.running!
      backfill_run.backfill_class.new.call
      backfill_run.completed!
    rescue StandardError => e
      backfill_run.failed!
      raise e
    end
  end
end
