class CreateDataDripBackfillRuns < ActiveRecord::Migration[7.0]
  def change
    create_table :data_drip_backfill_runs, id: :bigint do |t|
      t.string :backfill_class_name, null: false
      t.json :options, null: false, default: {}
      t.text :error_message
      t.integer :status, null: false, default: 0, index: true
      t.integer :batch_size, null: false, default: 100
      t.integer :total_count
      t.integer :processed_count, null: false, default: 0
      t.integer :amount_of_elements, null: true
      t.bigint :backfiller_id, null: false
      t.datetime :start_at, null: false
      t.timestamps null: false
    end
  end
end
