Rails.application.routes.draw do
  mount DataDrip::Engine => "/data_drip"
  mount DataDrip::CellApi::Engine => "/data_drip/cell_api"

  root to: redirect("/data_drip")
end
