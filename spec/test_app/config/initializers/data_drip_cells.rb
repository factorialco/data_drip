# Multi-cell mode for local development, enabled by `bin/dev-cells`.
#
# Each cell is a separate server process of this same app, with its own SQLite
# database (see config/database.yml) and port: the Nth cell in CELL_IDS listens
# on CELLS_BASE_PORT + N. Cells talk to each other through the real Cell API
# over plain HTTP on localhost.
#
# Without CELL_ID (plain `bin/dev`, the test suite) this does nothing, so the
# app runs single-cell as before.
if Rails.env.development? && ENV["CELL_ID"].present?
  cell_ids = ENV.fetch("CELL_IDS", "cell-a,cell-b,cell-c").split(",").map(&:strip)
  base_port = Integer(ENV.fetch("CELLS_BASE_PORT", "3000"))
  token = "dev-cell-secret"

  cell_url = lambda do |cell_id|
    index = cell_ids.index(cell_id) or raise ArgumentError, "unknown cell #{cell_id}"
    "http://localhost:#{base_port + index}"
  end

  DataDrip.current_cell_id = ENV["CELL_ID"]
  DataDrip.cell_ids = cell_ids
  DataDrip.cell_api_tokens = [ token ]
  DataDrip.cell_transport = DataDrip::CellTransport::Http.new(
    url: ->(cell_id) { "#{cell_url.call(cell_id)}/data_drip/cell_api" },
    headers: -> { { "Authorization" => "Bearer #{token}" } }
  )
  DataDrip.cell_ui_url = ->(cell_id, path) { "#{cell_url.call(cell_id)}/data_drip#{path}" }
end
