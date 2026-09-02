class AddMaxParallelWorkersToDataDripBackfillRuns < ActiveRecord::Migration[7.0]
  def change
    add_column :data_drip_backfill_runs, :max_parallel_workers, :integer
  end
end
