class CreateDataDripBackfillRunBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :data_drip_backfill_run_batches, id: :bigint do |t|
      t.references :backfill_run, null: false, foreign_key: { to_table: :data_drip_backfill_runs }, type: :bigint
      t.integer :status, null: false, default: 0, index: true
      t.text :error_message
      t.integer :batch_size, null: false, default: 100
      t.bigint :start_id, null: false
      t.bigint :finish_id, null: false
      t.timestamps null: false
    end
  end
end