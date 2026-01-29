class AddAmountOfElementsToDataDripBackfillRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :data_drip_backfill_runs, :amount_of_elements, :integer
  end
end
