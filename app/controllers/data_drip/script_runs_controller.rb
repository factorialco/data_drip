# frozen_string_literal: true

module DataDrip
  class ScriptRunsController < DataDrip.base_controller_class.constantize
    include DataDrip::Paginatable
    include DataDrip::BackfillerContext
    include DataDrip::MultiCellContext

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
      @groups = DataDrip::MultiCellGroup.preload_for(@script_runs)
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

      if DataDrip::GroupCreator.call(
        run: @script_run,
        remote_cell_ids: selected_remote_cell_ids
      )
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
      load_cell_fanout(@script_run)
    end

    def destroy
      @script_run = DataDrip::ScriptRun.find(params[:id])
      # Only the run's author may delete it, and only before it has started
      # running — once it has run we keep it as history.
      if !@script_run.manageable_by?(find_current_backfiller)
        flash[:alert] = "You can only delete script runs you created."
        return redirect_to script_runs_path(tab: params[:tab] || "my_runs")
      end
      if !@script_run.not_yet_run?
        flash[:alert] = "Script run can only be deleted before it has run."
        return redirect_to script_runs_path(tab: params[:tab] || "my_runs")
      end

      fanout = delete_remote_legs(@script_run)

      # A leg we could not reach is still scheduled to run in its own cell.
      # Destroying the coordinator's run and its dispatch records would erase
      # the only place that leg is visible or stoppable from, so the deletion is
      # refused until every cell has answered.
      unless fanout.all_ok?
        flash[:alert] =
          "Script run not deleted — its remote legs are still scheduled. #{fanout.message}"
        return redirect_to script_run_path(@script_run)
      end

      @script_run.dispatches.destroy_all
      @script_run.destroy!
      flash[:notice] = [ "Script run has been deleted.", fanout.message ].compact.join(" ")
      redirect_to script_runs_path(tab: params[:tab] || "my_runs")
    end

    # Re-delivers a failed dispatch to its cell (e.g. after the target cell
    # caught up on a deploy).
    def retry_dispatch
      @script_run = DataDrip::ScriptRun.find(params[:id])
      dispatch = @script_run.dispatches.failed.find_by(cell_id: params[:cell_id])

      if !@script_run.manageable_by?(find_current_backfiller)
        flash[:alert] = "You can only retry dispatches of runs you created."
      elsif dispatch.nil?
        flash[:alert] = "No failed dispatch for that cell."
      else
        dispatch.retry!
        flash[:notice] = "Dispatch to #{dispatch.cell_id} re-enqueued."
      end

      redirect_to script_run_path(@script_run)
    end

    def updates
      @script_run = DataDrip::ScriptRun.find(params[:id])
      load_cell_fanout(@script_run)

      cells_html =
        if @dispatches.any?
          render_to_string(
            partial: "data_drip/shared/cells",
            locals: {
              run: @script_run,
              dispatches: @dispatches
            },
            formats: [ :html ]
          )
        end

      render json: {
               status: @group.status,
               active: @cells_active,
               cells_html: cells_html,
               status_html: helpers.status_tag(@group.status),
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

    # Deleting the coordinator's run also asks each dispatched cell to delete
    # its leg. A leg that already ran (409) is refused there and stays in that
    # cell's own history, which counts as answered: it will not run again.
    def delete_remote_legs(run)
      fanout_to_dispatched(run.dispatches) do |dispatch|
        response =
          cell_client.delete_script_run(
            cell_id: dispatch.cell_id,
            run_id: dispatch.remote_run_id,
            acting_backfiller_id: run.backfiller_id
          )
        ok = response.success? || response.status == 404 || response.status == 409
        [ ok, delete_detail(response) ]
      end
    end

    # What to relay about a delete a cell acknowledged. A leg that had already
    # run is refused there and stays in that cell's history — worth saying, but
    # not a failure: it will not run again either way.
    def delete_detail(response)
      return "already ran — kept as history in that cell" if response.status == 409
      return nil if response.success? || response.status == 404

      cell_api_error_detail(response)
    end

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
