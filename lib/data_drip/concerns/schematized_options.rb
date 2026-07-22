# frozen_string_literal: true

module DataDrip
  # Class-level machinery shared by Backfill and Script to declare typed
  # options backed by an anonymous ActiveModel class. Extend this module and
  # call `define_schema_attribute` from your own macro (`attribute`, `input`).
  module SchematizedOptions
    def schema_options_class
      @schema_options_class ||=
        Class.new do
          include ActiveModel::API
          include ActiveModel::Attributes

          # Anonymous classes have no name, which breaks validation message
          # generation (i18n lookup requires a model name).
          def self.model_name
            ActiveModel::Name.new(self, nil, "SchemaOptions")
          end
        end
    end

    # Declaration-ordered list of the names (symbols) marked `required: true`.
    def schema_required_attributes
      @schema_required_attributes ||= []
    end

    def define_schema_attribute(name, type = nil, default: nil, required: false, reader:, **options)
      raise "Method #{name} already defined in #{self.class.name}" if instance_methods.include?(name.to_sym)

      if type == :enum
        enum_type = DataDrip::Types::Enum.new(values: options.delete(:values) || [])
        schema_options_class.attribute(name, enum_type, default: default, **options)

        # Reject submitted values (a comma-separated list) that aren't part of
        # the declared set, so a crafted request can't persist arbitrary values.
        attribute_name = name.to_sym
        schema_options_class.validate do
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
        schema_options_class.attribute(name, type, default: default, **options)
      end

      add_required_validation(name, type) if required

      holder = reader
      define_method(name) { public_send(holder).public_send(name) }
    end

    private

    def add_required_validation(name, type)
      schema_required_attributes << name.to_sym

      # `presence` would reject a legitimate `false`, so required booleans
      # validate inclusion in the true/false set instead.
      if type == :boolean
        schema_options_class.validates name,
                                       inclusion: {
                                         in: [ true, false ],
                                         message: "can't be blank"
                                       }
      else
        schema_options_class.validates name, presence: true
      end
    end
  end
end
