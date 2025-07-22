module DataDrip
  class Engine < ::Rails::Engine
    isolate_namespace DataDrip

    initializer "data_drip.assets.precompile" do |app|
      unless Rails.env.test?
        if app.config.respond_to?(:assets)
          app.config.assets.precompile += %w[data_drip/application.css]
        end
      end
    end

    initializer "data_drip.eager_load" do |app|
      if !app.config.eager_load && Dir.exist?(Rails.root.join("app/backfills"))
        app.config.to_prepare do
          Rails.autoloaders.main.eager_load_dir("#{Rails.root}/app/backfills")
        end
      end
    end
  end
end

