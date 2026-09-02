# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    class AddMaxParallelWorkersGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_migration
        migration_file =
          "db/migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_add_max_parallel_workers_to_data_drip_backfill_runs.rb"

        template "add_max_parallel_workers_migration.rb.erb",
                 migration_file,
                 migration_version: migration_version
        run "rails db:migrate"
        say_status(
          "create",
          "Added max_parallel_workers column to data_drip_backfill_runs",
          :green
        )
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
