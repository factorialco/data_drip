# frozen_string_literal: true

module DataDrip
  module Types
    class Enum < ActiveModel::Type::String
      def initialize(values: [], multiple: true, **options)
        @values_source = values
        @multiple = multiple
        super(**options)
      end

      def type
        :enum
      end

      def available_values
        @values_source.respond_to?(:call) ? @values_source.call : @values_source
      end

      # Whether several values can be picked (a comma-separated list) or just one.
      def multiple?
        @multiple
      end
    end
  end
end
