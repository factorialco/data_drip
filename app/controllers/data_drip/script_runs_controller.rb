# frozen_string_literal: true

module DataDrip
  class ScriptRunsController < DataDrip.base_controller_class.constantize
    include DataDrip::Paginatable
    include DataDrip::BackfillerContext

    layout "data_drip/layouts/application"
    helper_method :script_class_names
    helper DataDrip::BackfillRunsHelper
    helper DataDrip::ScriptRunsHelper

    def index
      @current_tab = params[:tab] || "my_runs"

      runs = DataDrip::ScriptRun.all
      my_runs = runs.where(backfiller: find_current_backfiller)

      @my_runs_count = my_runs.count
      @all_runs_count = runs.count

      @stats = {
        running: runs.running.count,
        enqueued: runs.enqueued.count,
        failed_recently: runs.failed.where(updated_at: 7.days.ago..).count,
        completed_recently: runs.completed.where(updated_at: 7.days.ago..).count
      }

      base_scope = @current_tab == "my_runs" ? my_runs : runs

      pagination_data =
        paginate_collection(base_scope.order(created_at: :desc), per_page: 10)

      @script_runs = pagination_data[:collection]
      @pagination = pagination_data
    end

    def new
      @script_run = DataDrip::ScriptRun.new
      @recent_script_class_names = recent_script_class_names
    end

    def create
      if params[:script_run][:start_at].present?
        user_timezone = params[:user_timezone].presence || @user_timezone

        if user_timezone.present?
          Time.use_zone(user_timezone) do
            local_time = Time.zone.parse(params[:script_run][:start_at])
            params[:script_run][:start_at] = local_time.utc if local_time
          end
        end
      end

      @script_run =
        DataDrip::ScriptRun.new(
          script_run_params.merge(backfiller: find_current_backfiller)
        )

      if @script_run.save
        local_time = @script_run.start_at.in_time_zone(@user_timezone)
        notice =
          if @script_run.start_at <= 1.minute.from_now
            "Script run for #{@script_run.script_class_name} has been enqueued and will start shortly."
          else
            "Script run for #{@script_run.script_class_name} has been enqueued. Will run at #{local_time.strftime("%d-%m-%Y, %H:%M:%S %Z")}."
          end

        redirect_to script_runs_path(tab: "my_runs"), notice: notice
      else
        @recent_script_class_names = recent_script_class_names
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @script_run = DataDrip::ScriptRun.find(params[:id])
    end

    def destroy
      @script_run = DataDrip::ScriptRun.find(params[:id])
      if @script_run.enqueued?
        @script_run.destroy!
        flash[:notice] = "Script run has been deleted."
      else
        flash[
          :alert
        ] = "Script run cannot be deleted as it is not in an enqueued state."
      end
      redirect_to script_runs_path(tab: params[:tab] || "my_runs")
    end

    def updates
      @script_run = DataDrip::ScriptRun.find(params[:id])

      render json: {
               status: @script_run.status,
               terminal: @script_run.completed? || @script_run.failed?,
               status_html: helpers.status_tag(@script_run.status),
               output: @script_run.output.to_s,
               error_message: @script_run.error_message.to_s,
               error_backtrace: @script_run.error_backtrace.to_s,
               started_at:
                 helpers.format_datetime_in_user_timezone(
                   @script_run.started_at,
                   @user_timezone
                 ),
               finished_at:
                 helpers.format_datetime_in_user_timezone(
                   @script_run.finished_at,
                   @user_timezone
                 )
             }
    end

    def script_inputs
      script_class_name = params[:script_class_name]

      if script_class_name.blank?
        render json: { html: "" }
        return
      end

      script_class =
        DataDrip.scripts.find { |klass| klass.name == script_class_name }

      if script_class.nil?
        render json: { html: "" }
        return
      end

      temp_run =
        DataDrip::ScriptRun.new(
          script_class_name: script_class_name,
          inputs: {}
        )

      render json: { html: helpers.script_input_fields(temp_run) }
    end

    private

    def script_run_params
      params.require(:script_run).permit(
        :script_class_name,
        :start_at,
        inputs: {}
      )
    end

    def script_class_names
      @script_class_names ||= DataDrip.scripts.map(&:name).compact.uniq.sort
    end

    # The current user's most-recently-run scripts (that still exist), surfaced
    # at the top of the class picker for quick reselection.
    def recent_script_class_names(limit: 6)
      available = script_class_names
      DataDrip::ScriptRun
        .where(backfiller: find_current_backfiller)
        .group(:script_class_name)
        .maximum(:created_at)
        .sort_by { |_name, run_at| -run_at.to_i }
        .map(&:first)
        .select { |name| available.include?(name) }
        .first(limit)
    end
  end
end
