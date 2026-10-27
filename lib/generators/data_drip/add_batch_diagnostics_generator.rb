# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    # Adds the failure diagnostics (exception class, backtrace, failing record)
    # and the log output columns to the batches table. New installs already get
    # them from the install generator; run this on apps that installed DataDrip
    # earlier:
    #
    #   rails generate data_drip:add_batch_diagnostics
    class AddBatchDiagnosticsGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_migration
        migration_file =
          "db/migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_add_diagnostics_to_data_drip_backfill_run_batches.rb"

        template "add_batch_diagnostics_migration.rb.erb",
                 migration_file,
                 migration_version: migration_version
        run "rails db:migrate"
        say_status("create", "Added diagnostics columns to DataDrip batches", :green)
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
