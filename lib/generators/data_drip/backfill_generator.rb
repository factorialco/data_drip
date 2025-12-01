# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    class BackfillGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :sorbet,
                   type: :boolean,
                   default: false,
                   desc:
                     "Include Sorbet type annotations in the generated backfill"

      def create_backfill_file
        backfills_path = Rails.root.join("app/backfills")
        empty_directory(backfills_path)
        @sorbet_enabled = options[:sorbet]
        template "backfill.rb.erb", File.join(backfills_path, "#{file_name}.rb")
      end
    end
  end
end
