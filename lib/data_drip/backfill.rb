# frozen_string_literal: true
# typed: strict

module DataDrip
  class Backfill
    extend DataDrip::SchematizedOptions

    def self.attribute(name, type = nil, default: nil, required: false, **options)
      define_schema_attribute(
        name,
        type,
        default: default,
        required: required,
        reader: :backfill_options,
        **options
      )
    end

    def self.required_option_names
      schema_required_attributes
    end

    # How many children of one run may be enqueued or running at once. nil
    # means unlimited: every batch is enqueued the moment the dripper creates
    # it. A backfill whose batches serialize on one shared resource (a global
    # lock, one external system) overrides this with a small number so the
    # waiting batches stay pending instead of holding worker threads; the
    # finishing child enqueues the next pending one.
    def self.max_parallel_batches
      nil
    end

    def self.backfill_options_class
      schema_options_class
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

    delegate :count, to: :scope

    def explain
      Rails.logger.debug scope.explain
    end

    attr_reader :backfill_options, :sleep_time

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
