# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    # Adds the per-run max_parallel_batches column, which lets the new-run form
    # override a backfill's own limit. New installs already get it from the
    # install generator; run this on apps that installed DataDrip earlier:
    #
    #   rails generate data_drip:add_max_parallel_batches
    class AddMaxParallelBatchesGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_migration
        migration_file =
          "db/migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_add_max_parallel_batches_to_data_drip_backfill_runs.rb"

        template "add_max_parallel_batches_migration.rb.erb",
                 migration_file,
                 migration_version: migration_version
        run "rails db:migrate"
        say_status("create", "Added max_parallel_batches column to data_drip_backfill_runs", :green)
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
