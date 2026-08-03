# frozen_string_literal: true

require "importmap-rails"
require "turbo-rails"
require "stimulus-rails"
require_relative "concerns/paginatable"
require_relative "concerns/backfiller_context"

module DataDrip
  class Engine < ::Rails::Engine
    isolate_namespace DataDrip

    initializer "data_drip.assets" do |app|
      app.config.assets.paths << root.join("app/javascript")

      # Declare the engine's importmap JS for precompilation. Building the import
      # map (javascript_importmap_tags) calls asset_path for every pinned module,
      # so a host on a strict Sprockets pipeline (check_precompiled_asset) raises
      # "asset was not declared to be precompiled" without this. JS only — never
      # sweep the compiled CSS in (it is served outside the pipeline; see
      # DataDrip::AssetsController). Guarded to a real Array so Propshaft hosts,
      # which serve path assets directly, are unaffected.
      precompile = app.config.assets.precompile
      precompile << %r{\Adata_drip/.+\.js\z} if precompile.is_a?(Array)
    end

    initializer "data_drip.importmap", after: "importmap" do |_app|
      DataDrip.importmap.draw(root.join("config/importmap.rb"))
      DataDrip.importmap.cache_sweeper(watches: root.join("app/javascript"))

      ActiveSupport.on_load(:action_controller_base) do
        before_action { DataDrip.importmap.cache_sweeper.execute_if_updated }
      end
    end

    initializer "data_drip.eager_load" do |app|
      unless app.config.eager_load
        %w[app/backfills app/scripts].each do |dir|
          next unless Rails.root.join(dir).exist?

          app.config.to_prepare do
            Rails.autoloaders.main.eager_load_dir("#{Rails.root}/#{dir}")
          end
        end
      end
    end
  end
end
