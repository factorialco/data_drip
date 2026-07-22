# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    # Adds the performance indexes to an existing DataDrip install. New installs
    # already get them from the install generator; run this on apps that
    # installed DataDrip earlier:
    #
    #   rails generate data_drip:add_performance_indexes
    class AddPerformanceIndexesGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_migration
        migration_file =
          "db/migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_add_data_drip_performance_indexes.rb"

        template "add_performance_indexes_migration.rb.erb",
                 migration_file,
                 migration_version: migration_version
        run "rails db:migrate"
        say_status("create", "Added DataDrip performance indexes", :green)
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
