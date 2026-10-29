# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    # Widens `data_drip_script_runs.output` so long script logs fit. On MySQL
    # the original `text` column holds only 64KB, and a chatty script dies
    # mid-run with "Data too long for column 'output'". New installs get the
    # wider column from the install generator; run this on older installs:
    #
    #   rails generate data_drip:widen_script_run_output
    class WidenScriptRunOutputGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_migration
        migration_file =
          "db/migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_widen_data_drip_script_run_output.rb"

        template "widen_script_run_output_migration.rb.erb",
                 migration_file,
                 migration_version: migration_version
        run "rails db:migrate"
        say_status("create", "Widened DataDrip script run output column", :green)
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
