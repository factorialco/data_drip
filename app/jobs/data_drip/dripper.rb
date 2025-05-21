module DataDrip
	class Dripper < ActiveJob::Base
		queue_as :data_drip

		def perform(backfill_class_name)
			backfill_class = DataDrip.all.find { |klass| klass.name == backfill_class_name }

			raise "Backfill class not found: #{backfill_class_name}" unless backfill_class

			backfill_class.new.call
		end
	end
end