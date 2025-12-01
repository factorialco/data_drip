# frozen_string_literal: true

require "importmap-rails"
require "turbo-rails"
require "stimulus-rails"

module DataDrip
  class Engine < ::Rails::Engine
    isolate_namespace DataDrip

    initializer "data_drip.assets" do |app|
      app.config.assets.paths << root.join("app/assets/stylesheets")
      app.config.assets.paths << root.join("app/javascript")
      app.config.assets.precompile << "data_drip_manifest.js"
    end

    initializer "data_drip.importmap", after: "importmap" do |_app|
      DataDrip.importmap.draw(root.join("config/importmap.rb"))
      DataDrip.importmap.cache_sweeper(watches: root.join("app/javascript"))

      ActiveSupport.on_load(:action_controller_base) do
        before_action { DataDrip.importmap.cache_sweeper.execute_if_updated }
      end
    end

    initializer "data_drip.eager_load" do |app|
      if !app.config.eager_load && Rails.root.join("app/backfills").exist?
        app.config.to_prepare do
          Rails.autoloaders.main.eager_load_dir("#{Rails.root}/app/backfills")
        end
      end
    end
  end
end
