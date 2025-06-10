module DataDrip
  class BackfillsController < ActionController::Base
    layout "data_drip/layouts/application"
    def index
      @backfills = DataDrip.all
    end

    def run
      run = DataDrip::BackfillRun.new(backfill_class_name: params[:backfill_class_name])
      if run.valid?
        run.save!
        redirect_to backfills_path, notice: "Backfill job for #{params[:backfill_class_name]} has been enqueued."
      else
        flash[:alert] = run.errors.full_messages.join(", ")
        redirect_to backfills_path
      end
    end
  end
end
