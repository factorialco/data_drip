# frozen_string_literal: true

module DataDrip
  # Machine-to-machine API used by cells to coordinate multi-cell runs. It is a
  # separate engine from the human UI so hosts can mount it under different
  # route constraints (the UI typically sits behind an admin/staff gate that
  # would reject cell-to-cell requests):
  #
  #   mount DataDrip::Engine => "/data_drip"                 # human UI
  #   mount DataDrip::CellApi::Engine => "/data_drip/cell_api"
  #
  # Requests authenticate with a bearer token checked against
  # DataDrip.cell_api_tokens; with no tokens configured the API rejects
  # everything, so mounting it in a single-cell app is harmless.
  module CellApi
    class Engine < ::Rails::Engine
      isolate_namespace DataDrip::CellApi

      # This engine shares the gem's root with DataDrip::Engine, which already
      # registers the app/* directories; contributing them twice would clash.
      # It only exists to carry its own route set.
      config.paths["config/routes.rb"] = "config/cell_api_routes.rb"
      %w[app app/assets app/controllers app/helpers app/models app/views].each do |name|
        path = config.paths[name]
        next if path.nil?

        path.skip_load_path!
        path.skip_eager_load!
        path.skip_autoload!
      end
    end
  end
end
