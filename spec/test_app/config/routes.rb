Rails.application.routes.draw do
  mount DataDrip::Engine => "/data_drip"

  root to: redirect("/data_drip")
end
