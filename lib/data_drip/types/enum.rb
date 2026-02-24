# frozen_string_literal: true

module DataDrip
  module Types
    class Enum < ActiveModel::Type::String
      attr_reader :values_source

      def initialize(values: [], **options)
        @values_source = values
        super(**options)
      end

      def type
        :enum
      end

      def available_values
        @values_source.respond_to?(:call) ? @values_source.call : @values_source
      end
    end
  end
end

ActiveModel::Type.register(:enum, DataDrip::Types::Enum)
