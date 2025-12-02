# frozen_string_literal: true

require "data_drip"

original_dir = Dir.pwd
test_app_dir = File.join(__dir__, "test_app")
Dir.chdir(test_app_dir)

ENV["RAILS_ENV"] = "test"
require File.join(test_app_dir, "config", "environment")

require "rspec/rails"

ActiveRecord::Migration.maintain_test_schema!

Dir.chdir(original_dir)

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

    if ActiveRecord::Base.connection.adapter_name == "SQLite"
      ActiveRecord::Base.connection.execute(
        "DELETE FROM sqlite_sequence WHERE name IN ('users', 'employees', 'data_drip_backfill_runs', 'data_drip_backfill_run_batches')"
      )
    end
  end
end
