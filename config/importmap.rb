pin "application", to: "data_drip/application.js", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from DataDrip::Engine.root.join("app/javascript/data_drip/controllers"), under: "controllers", to: "data_drip/controllers"
