# frozen_string_literal: true

module DataDrip
  module ScriptRunsHelper
    include DataDrip::BackfillRunsHelper

    def script_input_fields(script_run)
      script_class = script_run.script_class
      return "" unless script_class

      typed_option_inputs(
        options_class: script_class.inputs_class,
        values: script_run.inputs,
        field_prefix: "script_run[inputs]",
        title: "Inputs · #{script_run.script_class_name}",
        required_attributes: script_class.required_inputs,
        description: script_class.description
      )
    end
  end
end
