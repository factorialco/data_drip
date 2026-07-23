# frozen_string_literal: true
# typed: strict

module DataDrip
  class Script
    extend DataDrip::SchematizedOptions

    def self.input(name, type = nil, default: nil, required: false, **options)
      define_schema_attribute(
        name,
        type,
        default: default,
        required: required,
        reader: :inputs,
        **options
      )
    end

    def self.inputs_class
      schema_options_class
    end

    def self.required_inputs
      schema_required_attributes.map(&:to_s)
    end

    def self.description(text = nil)
      @description = text unless text.nil?
      @description
    end

    attr_reader :inputs

    def initialize(inputs: {}, logger: nil)
      @inputs = self.class.inputs_class.new(inputs)
      @logger = logger
    end

    def call
      raise NotImplementedError
    end

    def log(message)
      line = "[#{Time.current.utc.iso8601}] #{message}"
      if @logger
        @logger.call(line)
      else
        Rails.logger.info(line)
      end
    end
  end
end
