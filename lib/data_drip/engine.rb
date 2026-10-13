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
      js_root = root.join("app/javascript")
      app.config.assets.paths << js_root

      # Declare the engine's importmap JS for precompilation. Building the import
      # map (javascript_importmap_tags) resolves every pinned module through
      # asset_path, so a host on a strict Sprockets pipeline
      # (check_precompiled_asset) raises "asset ... was not declared to be
      # precompiled" without this. Register explicit logical-path strings, NOT a
      # Regexp: sprockets-rails runs the precompile list through
      # Sprockets::Manifest#find, which calls start_with? on each entry, so a
      # Regexp raises NoMethodError. JS only — the compiled CSS is served outside
      # the pipeline (DataDrip::AssetsController). Guarded to a real Array so
      # Propshaft hosts, which serve path assets directly, are unaffected.
      precompile = app.config.assets.precompile
      if precompile.is_a?(Array)
        precompile.concat(
          Dir.glob(js_root.join("**/*.js")).map do |path|
            Pathname.new(path).relative_path_from(js_root).to_s
          end
        )
      end
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
