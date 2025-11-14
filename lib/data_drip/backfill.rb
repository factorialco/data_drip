# typed: strict

module DataDrip
  class Backfill
    def self.attribute(
      name,
      type = nil,
      default: (no_default = true),
      **options
    )
      backfill_options.attribute(name, type, default: default, **options)
    end

    def self.backfill_options
      @backfill_options ||=
        Class.new do
          include ActiveModel::API
          include ActiveModel::Attributes
        end
    end

    def initialize(
      batch_size: 100,
      sleep_time: DataDrip.sleep_time,
      options: {}
    )
      @batch_size = batch_size
      @sleep_time = sleep_time
      @options = options
    end

    def call(start_id: nil, finish_id: nil)
      DataDrip.before_backfill&.call
      scope.in_batches(
        of: @batch_size,
        start: start_id,
        finish: finish_id
      ) do |batch|
        process_batch(batch)
        sleep @sleep_time
      end
    end

    def count
      scope.count
    end

    def explain
      pp scope.explain
    end

    attr_reader :options

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
