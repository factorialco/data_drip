class AddDataDripPerformanceIndexes < ActiveRecord::Migration[7.0]
  def change
    add_index :data_drip_backfill_runs, [ :backfiller_id, :created_at ],
              name: "idx_backfill_runs_on_backfiller_and_created_at"
    add_index :data_drip_backfill_runs, :created_at

    add_index :data_drip_backfill_run_batches, [ :backfill_run_id, :status ],
              name: "idx_backfill_batches_on_run_and_status"
    add_index :data_drip_backfill_run_batches, [ :backfill_run_id, :created_at ],
              name: "idx_backfill_batches_on_run_and_created_at"
    remove_index :data_drip_backfill_run_batches, column: :status
    remove_index :data_drip_backfill_run_batches, column: :backfill_run_id
  end
end
