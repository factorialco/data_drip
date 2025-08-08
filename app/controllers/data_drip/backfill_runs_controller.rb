module DataDrip
  class BackfillRunsController < DataDrip.base_controller_class.constantize
    layout "data_drip/layouts/application"
    helper_method :backfill_class_names, :find_current_backfiller
    helper DataDrip::BackfillRunsHelper

    before_action :set_user_timezone

    def index
      @backfill_runs = DataDrip::BackfillRun.all
    end

    def new
      @run = DataDrip::BackfillRun.new
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
      end

      @run =
        DataDrip::BackfillRun.new(
          backfill_run_params.merge(backfiller: find_current_backfiller)
        )

      if @run.valid?
        @run.save!
        local_time = @run.start_at.in_time_zone(@user_timezone)
        redirect_to backfill_runs_path,
          notice:
            "Backfill job for #{@run.backfill_class_name} has been enqueued. Will run at #{local_time.strftime("%d-%m-%Y, %H:%M:%S %Z")}."
      else
        flash.now[:alert] = "Error creating backfill run"
        render :new
      end
    end

    def show
      @backfill_run = DataDrip::BackfillRun.find(params[:id])
    end

    def destroy
      @backfill_run = DataDrip::BackfillRun.find(params[:id])
      if @backfill_run.enqueued?
        @backfill_run.destroy!
        flash[:notice] = "Backfill run has been deleted."
      else
        flash[
          :alert
        ] = "Backfill run cannot be deleted as it is not in an enqueued state."
      end
      redirect_to backfill_runs_path
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

    def updates
      @backfill_run = DataDrip::BackfillRun.find(params[:id])

      render json: {
        status: @backfill_run.status,
        status_html: render_to_string(partial: 'status_tag', locals: { status: @backfill_run.status }, formats: [:html]),
        processed_count: @backfill_run.processed_count,
        total_count: @backfill_run.total_count,
        batches_html: render_to_string(partial: 'batches_table', locals: { backfill_run: @backfill_run }, formats: [:html])
      }
    end

    def stream
      @backfill_run = DataDrip::BackfillRun.find(params[:id])

      response.headers['Content-Type'] = 'text/event-stream'
      response.headers['Cache-Control'] = 'no-cache'
      response.headers['Connection'] = 'keep-alive'
      response.headers['X-Accel-Buffering'] = 'no'

      send_initial_data
      monitor_backfill_run
    rescue IOError, ActionController::Live::ClientDisconnected
      Rails.logger.info "SSE client disconnected for backfill run #{@backfill_run.id}"
    rescue => e
      Rails.logger.error "SSE error for backfill run #{@backfill_run.id}: #{e.message}"
    ensure
      response.stream.close if response.stream
    end

    def set_timezone
      session[:user_timezone] = params[:timezone] if params[:timezone].present?
      respond_to do |format|
        format.json { render json: { success: true } }
        format.html { redirect_back(fallback_location: backfill_runs_path) }
      end
    end

    private

    def send_initial_data
      data = {
        status: @backfill_run.status,
        status_html: render_to_string(partial: 'status_tag', locals: { status: @backfill_run.status }, formats: [:html]),
        processed_count: @backfill_run.processed_count,
        total_count: @backfill_run.total_count,
        batches_html: render_to_string(partial: "batches_table", locals: { backfill_run: @backfill_run }, formats: [:html])
      }

      response.stream.write("data: #{data.to_json}\n\n")
    rescue => e
      Rails.logger.error "Error sending initial SSE data: #{e.message}"
      response.stream.write("data: {\"error\": \"Failed to send initial data\"}\n\n")
    end

    def monitor_backfill_run
      last_processed_count = @backfill_run.processed_count
      last_status = @backfill_run.status
      timeout = 30.minutes.from_now

      loop do
        break if Time.current > timeout

        begin
          @backfill_run.reload

          if @backfill_run.processed_count != last_processed_count ||
             @backfill_run.status != last_status

            data = {
              status: @backfill_run.status,
              status_html: render_to_string(partial: 'status_tag', locals: { status: @backfill_run.status }, formats: [:html]),
              processed_count: @backfill_run.processed_count,
              total_count: @backfill_run.total_count,
              batches_html: render_to_string(partial: "batches_table", locals: { backfill_run: @backfill_run }, formats: [:html])
            }

            response.stream.write("data: #{data.to_json}\n\n")
            last_processed_count = @backfill_run.processed_count
            last_status = @backfill_run.status

            break if %w[completed failed stopped].include?(@backfill_run.status)
          end

          sleep 1
        rescue => e
          Rails.logger.error "Error in SSE monitoring loop: #{e.message}"
          response.stream.write("data: {\"error\": \"Monitoring error\"}\n\n")
          break
        end
      end
    end

    def set_user_timezone
      @user_timezone = params[:user_timezone].presence || session[:user_timezone] || "UTC"
      session[:user_timezone] = @user_timezone if params[:user_timezone].present?
    end

    def backfill_run_params
      params.require(:backfill_run).permit(
        :backfill_class_name,
        :batch_size,
        :start_at,
        :amount_of_elements
      )
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
