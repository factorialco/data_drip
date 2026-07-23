# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    class ScriptGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :sorbet,
                   type: :boolean,
                   default: false,
                   desc:
                     "Include Sorbet type annotations in the generated script"

      def create_script_file
        scripts_path = Rails.root.join("app/scripts")
        empty_directory(scripts_path)
        @sorbet_enabled = options[:sorbet]
        template "script.rb.erb", File.join(scripts_path, "#{file_name}.rb")
      end
    end
  end
end
