# frozen_string_literal: true

# Test helpers for multi-cell mode. Cells are addressed as
# https://<cell_id>.example.com/data_drip/cell_api so specs can stub each
# cell's Cell API with webmock.
module MultiCellHelpers
  CELL_API_TOKEN = "test-cell-secret"

  def configure_multi_cell!(
    current: "cell-a",
    cells: %w[cell-a cell-b cell-c],
    tokens: [ CELL_API_TOKEN ]
  )
    DataDrip.current_cell_id = current
    DataDrip.cell_ids = cells
    DataDrip.cell_api_tokens = tokens
    DataDrip.cell_transport =
      DataDrip::CellTransport::Http.new(
        url: ->(cell_id) { "https://#{cell_id}.example.com/data_drip/cell_api" },
        headers: -> { { "Authorization" => "Bearer #{CELL_API_TOKEN}" } }
      )
  end

  def reset_multi_cell_config!
    DataDrip.current_cell_id = nil
    DataDrip.cell_ids = []
    DataDrip.cell_transport = nil
    DataDrip.cell_api_tokens = []
    DataDrip.cell_ui_url = nil
    DataDrip.cell_fanout_concurrency = 8
    DataDrip.cell_fanout_deadline = 5
    DataDrip.cell_status_refresh_interval = 3
    DataDrip.script_output_tail_bytes = 4_096
  end

  def cell_api_url(cell_id, path)
    "https://#{cell_id}.example.com/data_drip/cell_api#{path}"
  end
end
