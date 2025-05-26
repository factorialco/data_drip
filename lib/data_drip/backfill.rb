# typed: strict

require 'ruby-progressbar'

module DataDrip
	class Backfill
		def initialize(batch_size: 100, sleep_time: 0.1)
			@batch_size = batch_size
			@sleep_time = sleep_time
		end

		def call
			count = scope.count

			progressbar = ProgressBar.create(title: "Backfilling #{self.class.name}", total: count)

			scope.in_batches(of: @batch_size) do |batch|
				process_batch(batch)
				sleep @sleep_time
				progressbar.increment
			end
		end

		def explain
			pp scope.explain # rubocop:disable Rails/Output
		end

		def self.from_data_migration
			if Rails.env.local?
				new.call
			else
				Rails.logger.info(
					"Skipping backfilling #{name} since we are in production. Run this manually. with `bin/backfill --class=#{name}`"
				)
			end
		end

		protected

		def process_batch(batch)
			batch.each { |element| process_element(element) }
		end

		def process_element(element)
			raise NotImplementedError
		end

		def scope
			raise NotImplementedError
		end

	end
end