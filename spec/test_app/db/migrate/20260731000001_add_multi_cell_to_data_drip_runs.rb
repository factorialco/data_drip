class AddMultiCellToDataDripRuns < ActiveRecord::Migration[7.0]
  def change
    change_table :data_drip_backfill_runs, bulk: true do |t|
      t.string :group_uuid
      t.string :cell_id
      t.integer :origin, default: 0, null: false
      t.string :origin_cell_id
    end
    add_index :data_drip_backfill_runs,
              [ :group_uuid, :cell_id ],
              unique: true,
              name: "idx_backfill_runs_on_group_and_cell"

    change_table :data_drip_script_runs, bulk: true do |t|
      t.string :backfiller_name
      t.string :group_uuid
      t.string :cell_id
      t.integer :origin, default: 0, null: false
      t.string :origin_cell_id
    end
    add_index :data_drip_script_runs,
              [ :group_uuid, :cell_id ],
              unique: true,
              name: "idx_script_runs_on_group_and_cell"
  end
end
