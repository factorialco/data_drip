module DataDrip
  class BackfillsController < ActionController::Base
    layout "data_drip/layouts/application"
    def index
      @backfills = DataDrip.all
    end

    def run
      backfill_class = DataDrip.all.find { |klass| klass.name == params[:backfill] }

      if backfill_class.nil?
        redirect_to backfills_path, alert: "Backfill class not found."
        return
      end

      unless backfill_class.instance_methods(false).include?(:scope)
        redirect_to backfills_path, alert: "Backfill class #{backfill_class.name} must implement #scope"
        return
      end
      unless backfill_class.instance_methods(false).include?(:process_element)
        redirect_to backfills_path, alert: "Backfill class #{backfill_class.name} must implement #process_element"
        return
      end
      if backfill_class.instance_methods(false).include?(:process_batch) && !(backfill_class.instance_method(:process_batch).arity == 1)
        redirect_to backfills_path, alert: "#process_batch should accept exactly one argument (the batch)"
        return
      end

      backfill = backfill_class.new
      scope = backfill.scope
      if scope.respond_to?(:count) && scope.count == 0
        redirect_to backfills_path, notice: "No records to process for #{backfill_class.name}. No jobs enqueued."
        return
      end

      DataDrip::Dripper.perform_later(backfill_class.name)
      redirect_to backfills_path, notice: "Backfill job for #{backfill_class.name} has been enqueued."
    rescue StandardError => e
      redirect_to backfills_path, alert: "Error: #{e.message}"
      nil
    end
  end
end
