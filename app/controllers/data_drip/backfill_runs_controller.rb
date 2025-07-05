module DataDrip
  class BackfillRunsController < ActionController::Base
    layout "data_drip/layouts/application"
    helper_method :backfill_class_names
    helper DataDrip::BackfillRunsHelper
    def index
      @backfill_runs = DataDrip::BackfillRun.all
    end

    def new
      @run = DataDrip::BackfillRun.new
    end

    def create
      @run = DataDrip::BackfillRun.new(backfill_run_params)
      if @run.valid?
        @run.save!
        redirect_to backfill_runs_path,
                    notice: "Backfill job for #{@run.backfill_class_name} has been enqueued. Will run at #{@run.start_at}."
      else
        flash.now[:alert] = "Error creating backfill run"
        render :new
      end
    end

    def show
      @backfill_run = DataDrip::BackfillRun.find(params[:id])
    end

    private

    def backfill_run_params
      params.require(:backfill_run).permit(:backfill_class_name, :batch_size, :start_at)
    end

    def backfill_class_names
      @backfill_class_names = DataDrip.all.map(&:name)
      @backfill_class_names.sort!
      @backfill_class_names.unshift("Select a backfill class")
      @backfill_class_names.uniq!
      @backfill_class_names
    end
  end
end
