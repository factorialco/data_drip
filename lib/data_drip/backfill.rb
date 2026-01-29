# typed: strict

module DataDrip
  class Backfill
    def self.attribute(name, type = nil, default: nil, **options)
      if instance_methods.include?(name.to_sym)
        raise "Method #{name} already defined in #{self.class.name}"
      end

      backfill_options_class.attribute(name, type, default: default, **options)
      define_method(name) { backfill_options.public_send(name) }
    end

    def self.backfill_options_class
      @backfill_options_class ||=
        Class.new do
          include ActiveModel::API
          include ActiveModel::Attributes
        end
    end

    def initialize(
      batch_size: 100,
      sleep_time: DataDrip.sleep_time,
      backfill_options: {}
    )
      @batch_size = batch_size
      @sleep_time = sleep_time
      @backfill_options =
        self.class.backfill_options_class.new(backfill_options)
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

    attr_reader :backfill_options

    def scope
      raise NotImplementedError
    end

    protected

    def process_batch(batch)
      batch.each { |element| process_element(element) }
    end

    def process_element(element)
      raise NotImplementedError
    end
  end
end
