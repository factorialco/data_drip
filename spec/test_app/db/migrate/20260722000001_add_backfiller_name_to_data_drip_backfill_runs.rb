class AddBackfillerNameToDataDripBackfillRuns < ActiveRecord::Migration[7.0]
  def change
    add_column :data_drip_backfill_runs, :backfiller_name, :string
  end
end
