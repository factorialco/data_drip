module DataDrip
    module Hello
        def self.included(base)
           puts "Hello from DataDrip::Hello"
           puts base.inspect
        end
    end
end

