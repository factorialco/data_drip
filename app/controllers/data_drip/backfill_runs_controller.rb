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
      if params[:backfill_run][:start_at].present? && params[:user_timezone].present?
        user_time_zone = params[:user_timezone]
        Time.use_zone(user_time_zone) do
          local_time = Time.zone.parse(params[:backfill_run][:start_at])
          params[:backfill_run][:start_at] = local_time.utc if local_time
        end
      end
      @run = DataDrip::BackfillRun.new(backfill_run_params)
      if @run.valid?
        @run.save!
        user_time_zone = params[:user_timezone] || "UTC"
        local_time = @run.start_at.in_time_zone(user_time_zone)
        redirect_to backfill_runs_path,
                    notice: "Backfill job for #{@run.backfill_class_name} has been enqueued. Will run at #{local_time.strftime("%d-%m-%Y, %H:%M:%S %Z")}."
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
