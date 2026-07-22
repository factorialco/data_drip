# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    # Adds the backfiller_name column to an existing DataDrip install. New
    # installs already get the column from the install generator; run this on
    # apps that installed DataDrip before the column existed:
    #
    #   rails generate data_drip:add_backfiller_name
    class AddBackfillerNameGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_migration
        migration_file =
          "db/migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_add_backfiller_name_to_data_drip_backfill_runs.rb"

        template "add_backfiller_name_migration.rb.erb",
                 migration_file,
                 migration_version: migration_version
        run "rails db:migrate"
        say_status("create", "Added backfiller_name column to data_drip_backfill_runs", :green)
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
