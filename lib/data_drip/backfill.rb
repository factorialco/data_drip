# frozen_string_literal: true
# typed: strict

module DataDrip
  class Backfill
    def self.attribute(name, type = nil, default: nil, **options)
      raise "Method #{name} already defined in #{self.class.name}" if instance_methods.include?(name.to_sym)

      if type == :enum
        enum_type = DataDrip::Types::Enum.new(values: options.delete(:values) || [])
        backfill_options_class.attribute(name, enum_type, default: default, **options)
      else
        backfill_options_class.attribute(name, type, default: default, **options)
      end

      define_method(name) { backfill_options.public_send(name) }
    end

    def self.backfill_options_class
      @backfill_options_class ||=
        Class.new do
          include ActiveModel::API
          include ActiveModel::Attributes
        end
    end

    # Human-readable summary of what this backfill does. Acts as both setter
    # (`description "..."`) and getter (`description`). Returns nil when unset.
    def self.description(text = nil)
      @description = text unless text.nil?
      @description
    end

    # Introspects the declared attributes for display on the catalog page.
    # Returns an array of { name:, type:, values: } hashes. `values` is only
    # present for enum attributes (it lists their allowed values).
    def self.custom_fields
      backfill_options_class.attribute_types.map do |name, type|
        field = { name: name, type: type.type }
        if type.respond_to?(:available_values)
          # Enum values may be produced by a callable. The catalog renders every
          # backfill at once, so a single failing callable shouldn't break the
          # whole page — degrade to "no values" instead.
          field[:values] = begin
            type.available_values
          rescue StandardError
            nil
          end
        end
        field
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

    delegate :count, to: :scope

    def explain
      Rails.logger.debug scope.explain
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
