# frozen_string_literal: true

module DataDrip
  module Types
    class Enum < ActiveModel::Type::String
      attr_reader :depends_on

      def initialize(values: [], multiple: true, depends_on: nil, **options)
        @values_source = values
        @multiple = multiple
        @depends_on = depends_on&.to_sym
        super(**options)
      end

      def type
        :enum
      end

      def available_values
        @values_source.respond_to?(:call) ? @values_source.call : @values_source
      end

      def multiple?
        @multiple
      end
    end
  end
end
