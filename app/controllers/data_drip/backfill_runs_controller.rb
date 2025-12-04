# frozen_string_literal: true

module DataDrip
  class BackfillRunsController < DataDrip.base_controller_class.constantize
    include DataDrip::Paginatable

    layout "data_drip/layouts/application"
    helper_method :backfill_class_names, :find_current_backfiller
    helper DataDrip::BackfillRunsHelper

    before_action :set_user_timezone

    def index
      pagination_data =
        paginate_collection(
          DataDrip::BackfillRun.order(created_at: :desc),
          per_page: 10
        )

      @backfill_runs = pagination_data[:collection]
      @pagination = pagination_data
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

      if @run.save
        local_time = @run.start_at.in_time_zone(@user_timezone)
        redirect_to backfill_runs_path,
                    notice:
                      "Backfill job for #{@run.backfill_class_name} has been enqueued. Will run at #{local_time.strftime("%d-%m-%Y, %H:%M:%S %Z")}."
      else
        render :new
      end
    end

    def show
      @backfill_run = DataDrip::BackfillRun.find(params[:id])

      batch_pagination_data =
        paginate_collection(
          @backfill_run.batches.order(created_at: :desc),
          per_page: 20,
          page_param: :batch_page
        )

      @batches = batch_pagination_data[:collection]
      @batch_pagination = batch_pagination_data
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
               status_html:
                 render_to_string(
                   partial: "status_tag",
                   locals: {
                     status: @backfill_run.status
                   },
                   formats: [ :html ]
                 ),
               processed_count: @backfill_run.processed_count,
               total_count: @backfill_run.total_count,
               batches_html:
                 render_to_string(
                   partial: "batches_table",
                   locals: {
                     backfill_run: @backfill_run
                   },
                   formats: [ :html ]
                 )
             }
    end

    def stream
      @backfill_run = DataDrip::BackfillRun.find(params[:id])

      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["Connection"] = "keep-alive"
      response.headers["X-Accel-Buffering"] = "no"

      send_initial_data
      monitor_backfill_run
    rescue IOError, ActionController::Live::ClientDisconnected
      Rails.logger.info "SSE client disconnected for backfill run #{@backfill_run&.id}"
    rescue StandardError => e
      Rails.logger.error "SSE error for backfill run #{@backfill_run&.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    ensure
      begin
        response.stream.close if response.stream.respond_to?(:close)
      rescue StandardError => e
        Rails.logger.error "Error closing SSE stream: #{e.message}"
      end
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

      if backfill_class_name.blank? ||
           backfill_class_name == "Select a backfill class"
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

    def find_current_backfiller
      if DataDrip.current_backfiller_method.blank?
        raise "Missing DataDrip.current_backfiller_method, please set it in an initializer (like DataDrip.current_backfiller_method = :current_user"
      end
      unless respond_to?(DataDrip.current_backfiller_method, true)
        raise "Invalid DataDrip.current_backfiller_method: #{DataDrip.current_backfiller_method}. Maybe you need to change the `base_controller_class` for DataDrip (currently: #{DataDrip.base_controller_class})?"
      end

      send(DataDrip.current_backfiller_method)
    end

    private

    def send_initial_data
      data = {
        status: @backfill_run.status,
        status_html:
          render_to_string(
            partial: "status_tag",
            locals: {
              status: @backfill_run.status
            },
            formats: [ :html ]
          ),
        processed_count: @backfill_run.processed_count,
        total_count: @backfill_run.total_count,
        batches_html:
          render_to_string(
            partial: "batches_table",
            locals: {
              backfill_run: @backfill_run
            },
            formats: [ :html ]
          )
      }

      response.stream.write("data: #{data.to_json}\n\n")
    rescue StandardError => e
      Rails.logger.error "Error sending initial SSE data: #{e.message}"
      response.stream.write(
        "data: {\"error\": \"Failed to send initial data\"}\n\n"
      )
    end

    def monitor_backfill_run
      last_processed_count = @backfill_run.processed_count
      last_status = @backfill_run.status
      timeout = 5.minutes.from_now

      loop do
        break if Time.current > timeout

        # More aggressive client connection check
        begin
          # Try to write data - this will fail if client disconnected
          response.stream.write("event: ping\ndata: {}\n\n")
          response.stream.flush if response.stream.respond_to?(:flush)
        rescue IOError,
               ActionController::Live::ClientDisconnected,
               Errno::EPIPE,
               Errno::ECONNRESET
          Rails.logger.info "SSE client disconnected during monitoring for backfill run #{@backfill_run.id}"
          break
        rescue StandardError => e
          Rails.logger.error "SSE connection error: #{e.class} - #{e.message}"
          break
        end

        begin
          @backfill_run.reload

          if @backfill_run.processed_count != last_processed_count ||
               @backfill_run.status != last_status
            data = {
              status: @backfill_run.status,
              status_html:
                render_to_string(
                  partial: "status_tag",
                  locals: {
                    status: @backfill_run.status
                  },
                  formats: [ :html ]
                ),
              processed_count: @backfill_run.processed_count,
              total_count: @backfill_run.total_count,
              batches_html:
                render_to_string(
                  partial: "batches_table",
                  locals: {
                    backfill_run: @backfill_run
                  },
                  formats: [ :html ]
                )
            }

            response.stream.write("data: #{data.to_json}\n\n")
            last_processed_count = @backfill_run.processed_count
            last_status = @backfill_run.status

            break if %w[completed failed stopped].include?(@backfill_run.status)
          end

          sleep 2
        rescue StandardError => e
          Rails.logger.error "Error in SSE monitoring loop: #{e.message}"
          response.stream.write("data: {\"error\": \"Monitoring error\"}\n\n")
          break
        end
      end
    end

    def set_user_timezone
      @user_timezone =
        params[:user_timezone].presence || session[:user_timezone] || "UTC"
      session[:user_timezone] = @user_timezone if params[
        :user_timezone
      ].present?
    end

    def backfill_run_params
      params.expect(
        backfill_run: [
          :backfill_class_name,
          :batch_size,
          :start_at,
          :amount_of_elements,
          { options: {} }
        ]
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
