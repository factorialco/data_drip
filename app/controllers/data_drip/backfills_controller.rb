module DataDrip
  class BackfillsController < ActionController::Base
		layout "data_drip/layouts/application"
    def index
			@backfills = DataDrip.all
    end

		def run
			backfill_class = DataDrip.all.find { |klass| klass.name == params[:backfill] }

			if backfill_class
				DataDrip::Dripper.perform_later(backfill_class.name)
				redirect_to backfills_path, notice: "Backfill job for #{backfill_class.name} has been enqueued."
				return
			else
				redirect_to backfills_path, alert: "Backfill class not found."
				return
			end
		rescue StandardError => e
			redirect_to backfills_path, alert: "Error: #{e.message}"
			return
		end
  end
end