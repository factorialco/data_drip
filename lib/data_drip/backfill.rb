# frozen_string_literal: true
# typed: strict

module DataDrip
  class Backfill
    def self.attribute(name, type = nil, default: nil, required: false, **options)
      raise "Method #{name} already defined in #{self.class.name}" if instance_methods.include?(name.to_sym)

      if type == :enum
        enum_type = DataDrip::Types::Enum.new(values: options.delete(:values) || [])
        backfill_options_class.attribute(name, enum_type, default: default, **options)

        # Reject submitted values (a comma-separated list) that aren't part of
        # the declared set, so a crafted request can't persist arbitrary values.
        attribute_name = name.to_sym
        backfill_options_class.validate do
          raw = public_send(attribute_name)
          if raw.present?
            allowed =
              enum_type.available_values.map { |value| (value.is_a?(Array) ? value.last : value).to_s }
            unless (raw.to_s.split(",") - allowed).empty?
              errors.add(attribute_name, "is not included in the list")
            end
          end
        end
      else
        backfill_options_class.attribute(name, type, default: default, **options)
      end

      if required
        required_option_names << name.to_sym

        if type == :boolean
          # presence: true would reject a legitimate `false`.
          backfill_options_class.validates name,
                                           inclusion: {
                                             in: [ true, false ],
                                             message: "can't be blank"
                                           }
        else
          backfill_options_class.validates name, presence: true
        end
      end

      define_method(name) { backfill_options.public_send(name) }
    end

    def self.required_option_names
      @required_option_names ||= []
    end

    def self.backfill_options_class
      @backfill_options_class ||=
        Class.new do
          include ActiveModel::API
          include ActiveModel::Attributes

          # The class is anonymous; i18n lookups (e.g. validation messages)
          # need a model name to resolve against.
          def self.model_name
            ActiveModel::Name.new(self, nil, "BackfillOptions")
          end
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
