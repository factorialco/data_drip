# frozen_string_literal: true

module DataDrip
  class BackfillRunsController < DataDrip.base_controller_class.constantize
    include DataDrip::Paginatable
    include DataDrip::BackfillerContext

    layout "data_drip/layouts/application"
    helper_method :backfill_class_names
    helper DataDrip::BackfillRunsHelper

    def index
      @current_tab = params[:tab] || "my_runs"
      @query = params[:q].to_s.strip
      @status_filter =
        params[:status].presence_in(DataDrip::BackfillRun.statuses.keys)

      runs = DataDrip::BackfillRun.all
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
      if @query.present?
        base_scope =
          base_scope.where(
            "backfill_class_name LIKE ?",
            "%#{DataDrip::BackfillRun.sanitize_sql_like(@query)}%"
          )
      end
      base_scope = base_scope.where(status: @status_filter) if @status_filter

      pagination_data =
        paginate_collection(base_scope.order(created_at: :desc), per_page: 10)

      @backfill_runs = pagination_data[:collection]
      @pagination = pagination_data
    end

    def new
      @run = DataDrip::BackfillRun.new
      @recent_backfill_class_names = recent_backfill_class_names
    end

    def create
      if params[:backfill_run][:start_at].present?
        user_timezone = params[:user_timezone].presence || @user_timezone

        if user_timezone.present?
          Time.use_zone(user_timezone) do
            local_time = Time.zone.parse(params[:backfill_run][:start_at])
            params[:backfill_run][:start_at] = local_time.utc if local_time
          end
        end
      else
        # "Run immediately" — the schedule field is disabled and not submitted.
        params[:backfill_run][:start_at] = Time.current
      end

      @run =
        DataDrip::BackfillRun.new(
          backfill_run_params.merge(backfiller: find_current_backfiller)
        )

      if @run.save
        notice =
          if @run.start_at <= 1.minute.from_now
            "Backfill job for #{@run.backfill_class_name} has been enqueued and will start shortly."
          else
            local_time = @run.start_at.in_time_zone(@user_timezone)
            "Backfill job for #{@run.backfill_class_name} has been enqueued. Will run at #{local_time.strftime("%d-%m-%Y, %H:%M:%S %Z")}."
          end

        redirect_to backfill_runs_path(tab: "my_runs"), notice: notice
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @backfill_run = DataDrip::BackfillRun.find(params[:id])

      batch_scope = @backfill_run.batches
      batch_scope = batch_scope.failed if params[:batch_status] == "failed"

      batch_pagination_data =
        paginate_collection(
          batch_scope.order(created_at: :desc),
          per_page: 20,
          page_param: :batch_page
        )

      @batches = batch_pagination_data[:collection]
      @batch_pagination = batch_pagination_data
    end

    def destroy
      @backfill_run = DataDrip::BackfillRun.find(params[:id])
      # Deletable when not in flight: still-enqueued, or finished (completed/
      # failed/stopped) so old runs can be cleaned up.
      if @backfill_run.enqueued? || @backfill_run.terminal?
        @backfill_run.destroy!
        flash[:notice] = "Backfill run has been deleted."
      else
        flash[
          :alert
        ] = "Backfill run cannot be deleted while it is pending or running."
      end
      redirect_to backfill_runs_path(tab: params[:tab] || "my_runs")
    end

    def stop
      @backfill_run = DataDrip::BackfillRun.find(params[:id])
      if @backfill_run.running?
        @backfill_run.stopped!
        flash[:notice] = "Backfill run has been stopped."
      else
        flash[:alert] = "Backfill run is not currently running."
      end

      redirect_to backfill_run_path(@backfill_run)
    end

    def retry_failed_batches
      @backfill_run = DataDrip::BackfillRun.find(params[:id])
      failed_batches = @backfill_run.batches.failed

      if failed_batches.none?
        flash[:alert] = "This run has no failed batches to retry."
      else
        count = 0
        failed_batches.find_each do |batch|
          batch.update!(status: :pending, error_message: nil)
          batch.enqueue
          count += 1
        end
        @backfill_run.running! unless @backfill_run.running?
        flash[
          :notice
        ] = "Re-enqueued #{count} failed #{count == 1 ? "batch" : "batches"}."
      end

      redirect_to backfill_run_path(@backfill_run)
    end

    def updates
      @backfill_run = DataDrip::BackfillRun.find(params[:id])

      batches =
        @backfill_run.batches.order(created_at: :desc).limit(20)

      render json: {
               status: @backfill_run.status,
               terminal: @backfill_run.terminal?,
               status_html: helpers.status_tag(@backfill_run.status),
               progress_html:
                 render_to_string(
                   partial: "progress",
                   locals: {
                     backfill_run: @backfill_run
                   },
                   formats: [ :html ]
                 ),
               batches_meta_html:
                 render_to_string(
                   partial: "batches_meta",
                   locals: {
                     backfill_run: @backfill_run,
                     batch_status: nil
                   },
                   formats: [ :html ]
                 ),
               batches_html:
                 render_to_string(
                   partial: "batches_table",
                   locals: {
                     batches: batches
                   },
                   formats: [ :html ]
                 )
             }
    end

    def set_timezone
      session[:user_timezone] = params[:timezone] if params[:timezone].present?
      respond_to do |format|
        format.json { render json: { success: true } }
        format.html { redirect_back_or_to(backfill_runs_path) }
      end
    end

    def backfill_options
      backfill_class_name = params[:backfill_class_name]

      if backfill_class_name.blank?
        render json: { html: "" }
        return
      end

      backfill_class =
        DataDrip.all.find { |klass| klass.name == backfill_class_name }

      if backfill_class.nil?
        render json: { html: "" }
        return
      end

      # Create a temporary backfill run to use with the helper
      temp_run =
        DataDrip::BackfillRun.new(
          backfill_class_name: backfill_class_name,
          options: {}
        )

      html = helpers.backfill_option_inputs(temp_run)

      render json: { html: html }
    end

    private

    def backfill_run_params
      params.require(:backfill_run).permit(
        :backfill_class_name,
        :batch_size,
        :start_at,
        :amount_of_elements,
        options: {}
      )
    end

    def backfill_class_names
      # compact drops anonymous backfill subclasses (nil name), which would
      # otherwise blow up the sort.
      @backfill_class_names ||= DataDrip.all.map(&:name).compact.uniq.sort
    end

    # The current user's most-recently-run classes (that still exist), surfaced
    # at the top of the class picker for quick reselection.
    def recent_backfill_class_names(limit: 6)
      available = backfill_class_names
      DataDrip::BackfillRun
        .where(backfiller: find_current_backfiller)
        .group(:backfill_class_name)
        .maximum(:created_at)
        .sort_by { |_name, run_at| -run_at.to_i }
        .map(&:first)
        .select { |name| available.include?(name) }
        .first(limit)
    end
  end
end
