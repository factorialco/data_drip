class TestBackfillWithDefaults < DataDrip::Backfill
  attribute :dry_run, :boolean, default: true
  attribute :verbose, :boolean, default: false
  attribute :name, :string, default: "default_name"

  def scope
    Employee.all
  end

  def process_batch(batch)
    # Do nothing, this is just for testing
  end
end
