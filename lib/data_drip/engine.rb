module DataDrip
    class Engine < ::Rails::Engine
        isolate_namespace DataDrip
        puts "DataDrip::Engine loaded"
    end
end