# frozen_string_literal: true

require "rails/generators/base"

module DataDrip
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("../templates", __dir__)

      def mount_engine_route
        route_config = 'mount DataDrip::Engine => "/data_drip"'

        routes_file = Rails.root.join("config/routes.rb")
        if File.readlines(routes_file).any? { |line| line.include?(route_config) }
          say_status("skipped", "DataDrip route already present in routes.rb", :yellow)
        else
          say_status("info", "Adding DataDrip mount route to routes.rb", :blue)
          route route_config
        end
      end

      def create_backfills_directory
        empty_directory "app/backfills"
        say_status("create", "Created app/backfills directory", :green)
      end
    end
  end
end
