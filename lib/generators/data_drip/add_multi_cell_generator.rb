# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    # Adds the multi-cell columns and the cell dispatches table to an existing
    # DataDrip install. New installs already get everything from the install
    # generator; run this on apps that installed DataDrip before multi-cell
    # support existed:
    #
    #   rails generate data_drip:add_multi_cell
    class AddMultiCellGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_columns_migration
        if column_exists?
          say_status(
            "skipped",
            "Multi-cell columns already present on data_drip_backfill_runs",
            :yellow
          )
        else
          migration_file =
            "db/migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_add_multi_cell_to_data_drip_runs.rb"
          template "add_multi_cell_migration.rb.erb",
                   migration_file,
                   migration_version: migration_version
          say_status(
            "create",
            "Added multi-cell columns to data_drip run tables",
            :green
          )
        end
      end

      def create_cell_dispatches_migration
        if Dir.glob(
             Rails.root.join("db/migrate/*_create_data_drip_cell_dispatches.rb")
           ).any?
          say_status(
            "skipped",
            "DataDrip cell dispatches migration already exists",
            :yellow
          )
        else
          migration_file =
            "db/migrate/#{1.second.from_now.utc.strftime("%Y%m%d%H%M%S")}_create_data_drip_cell_dispatches.rb"
          template "cell_dispatch_migration.rb.erb",
                   migration_file,
                   migration_version: migration_version
          say_status(
            "create",
            "Created DataDrip cell dispatches migration",
            :green
          )
        end
      end

      def migrate
        run "rails db:migrate"
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end

      private

      def column_exists?
        Dir.glob(
          Rails.root.join("db/migrate/*_add_multi_cell_to_data_drip_runs.rb")
        ).any?
      end
    end
  end
end
