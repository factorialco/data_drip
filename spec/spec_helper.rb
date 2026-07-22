# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require "simplecov"
SimpleCov.start do
  enable_coverage :branch

  # Only measure the engine's own code, not the dummy test app or the suite.
  root File.expand_path("..", __dir__)
  skip "/spec/"
  skip "/lib/data_drip/version.rb"

  group "Controllers", "app/controllers"
  group "Models", "app/models"
  group "Jobs", "app/jobs"
  group "Helpers", "app/helpers"
  group "Library", "lib"
  group "Generators", "lib/generators"
end

Dir.chdir(File.join(__dir__, "test_app")) do
  require_relative "test_app/config/environment"
end

ActiveRecord::Migrator.migrations_paths = [
  File.expand_path("../spec/test_app/db/migrate", __dir__)
]
ActiveRecord::Migrator.migrations_paths << File.expand_path(
  "../db/migrate",
  __dir__
)

require "rspec/rails"

ActiveRecord::Migration.maintain_test_schema!

# Backfills pause DataDrip.sleep_time (default 5s in production) between
# batches. The suite runs the real batching loop, so drop it to 0 to stay fast.
DataDrip.sleep_time = 0

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :each do
    if defined?(DataDrip::BackfillRunBatch)
      DataDrip::BackfillRunBatch.delete_all
    end
    DataDrip::BackfillRun.delete_all if defined?(DataDrip::BackfillRun)
    Employee.delete_all if defined?(Employee)
    User.delete_all if defined?(User)
    HookNotifier.instance.clear

    if ActiveRecord::Base.connection.adapter_name == "SQLite"
      ActiveRecord::Base.connection.execute(
        "DELETE FROM sqlite_sequence WHERE name IN ('users', 'employees', 'data_drip_backfill_runs', 'data_drip_backfill_run_batches')"
      )
    end
  end
end
