class CreateDataDripCellDispatches < ActiveRecord::Migration[7.0]
  def change
    create_table :data_drip_cell_dispatches do |t|
      t.string :group_uuid, null: false
      t.string :cell_id, null: false
      t.integer :runnable_type, default: 0, null: false
      t.integer :status, default: 0, null: false
      t.bigint :remote_run_id
      t.text :error_message
      t.json :payload, default: {}, null: false

      t.timestamps
    end

    add_index :data_drip_cell_dispatches,
              [ :group_uuid, :cell_id ],
              unique: true,
              name: "idx_cell_dispatches_on_group_and_cell"
  end
end
