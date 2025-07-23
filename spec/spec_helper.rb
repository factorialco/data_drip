# frozen_string_literal: true

require "data_drip"

ENV["RAILS_ENV"] ||= "test"

require "rails"
require "test_app/config/environment"
require "rspec/rails"

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :each do
    User.delete_all
    Employee.delete_all
    DataDrip::BackfillRunBatch.delete_all
    DataDrip::BackfillRun.delete_all
  end
end
