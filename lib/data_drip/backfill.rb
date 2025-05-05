# typed: strict

require 'ruby-progressbar'

module DataDrip
	class Backfill
		extend T::Sig
		extend T::Helpers
		extend T::Generic
		abstract!

		Elem = type_member
		RelationType = type_member

		sig { params(batch_size: Integer, sleep_time: Float).void }
		def initialize(batch_size: 100, sleep_time: 0.1)
			@batch_size = batch_size
			@sleep_time = sleep_time
		end

		sig { void }
		def call
			local_scope = T.cast(scope, ActiveRecord::Relation)
			count = local_scope.count

			progressbar = ProgressBar.create(title: "Backfilling #{self.class.name}", total: count)

			local_scope.in_batches(of: @batch_size) do |batch|
				process_batch(batch)
				sleep @sleep_time
				progressbar.increment
			end
		end

		sig { void }
		def explain
			ap T.cast(scope, ActiveRecord::Relation).explain # rubocop:disable Rails/Output
		end

		sig { void }
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

		sig { overridable.params(batch: RelationType).void }
		def process_batch(batch)
			T.cast(batch, ActiveRecord::Relation).each { |element| process_element(element) }
		end

		sig { overridable.params(element: Elem).void }
		def process_element(element)
			raise NotImplementedError
		end

		sig { abstract.returns(RelationType) }
		def scope
		end

	end
end