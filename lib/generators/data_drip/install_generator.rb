# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def mount_engine_route
        route_config = 'mount DataDrip::Engine => "/data_drip"'

        routes_file = Rails.root.join("config/routes.rb")
        if File
             .readlines(routes_file)
             .any? { |line| line.include?(route_config) }
          say_status(
            "skipped",
            "DataDrip route already present in routes.rb",
            :yellow
          )
        else
          say_status("info", "Adding DataDrip mount route to routes.rb", :blue)
          route route_config
        end
      end

      def create_backfills_directory
        empty_directory "app/backfills"
        say_status("create", "Created app/backfills directory", :green)
      end

      def create_backfill_run_migration
        migration_file =
          "db/migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_create_data_drip_backfill_runs.rb"
        if File.exist?(migration_file)
          say_status(
            "skipped",
            "DataDrip backfill run migration already exists",
            :yellow
          )
        else
          template "backfill_run_migration.rb.erb",
                   migration_file,
                   migration_version: migration_version
          run "rails db:migrate"
          say_status(
            "create",
            "Created DataDrip backfill run migration",
            :green
          )
        end
      end

      def create_backfill_run_batch_migration
        migration_file =
          "db/migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S").to_i + 1}_create_data_drip_backfill_run_batches.rb"
        if File.exist?(migration_file)
          say_status(
            "skipped",
            "DataDrip backfill run batch migration already exists",
            :yellow
          )
        else
          template "backfill_run_batch_migration.rb.erb",
                   migration_file,
                   migration_version: migration_version
          run "rails db:migrate"
          say_status(
            "create",
            "Created DataDrip backfill run batch migration",
            :green
          )
        end
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
