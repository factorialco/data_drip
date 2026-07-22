# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

namespace :data_drip do
  desc "Compile the engine's Tailwind CSS (one-shot)"
  task :css do
    sh "npm install --no-audit --no-fund" unless File.directory?("node_modules")
    sh "npm run build:css"
  end

  desc "Fail if the checked-in tailwind.css is stale relative to the views/helpers"
  task css_check: :css do
    sh "git diff --exit-code app/assets/stylesheets/data_drip/tailwind.css" do |ok, _|
      unless ok
        abort "tailwind.css is out of date. Run `bundle exec rake data_drip:css` and commit the result."
      end
    end
  end
end

task default: %i[spec]
