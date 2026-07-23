# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    # Upgrade path for applications that installed DataDrip before the
    # scripts feature existed. Fresh installs get all of this from
    # data_drip:install.
    class InstallScriptsGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_scripts_directory
        empty_directory "app/scripts"
        say_status("create", "Created app/scripts directory", :green)
      end

      def create_script_run_migration
        if Dir.glob(
             Rails.root.join("db/migrate/*_create_data_drip_script_runs.rb")
           ).any?
          say_status(
            "skipped",
            "DataDrip script run migration already exists",
            :yellow
          )
        else
          migration_file =
            "db/migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_create_data_drip_script_runs.rb"
          template "script_run_migration.rb.erb",
                   migration_file,
                   migration_version: migration_version
          run "rails db:migrate"
          say_status("create", "Created DataDrip script run migration", :green)
        end
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
