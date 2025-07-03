# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

namespace :test_app do
  desc "Recreate the test application for specs"
  task :rebuild do
    require "fileutils"

    test_app_path = File.expand_path("test_app", Dir.pwd)

    if Dir.exist?(test_app_path)
      puts "Removing existing test_app..."
      FileUtils.rm_rf(test_app_path)
    end

    puts "Creating new test_app..."
    system("RAILS_ENV=development bundle exec rails new test_app -m lib/rails_template.rb")

    puts "Done!"
  end
end
