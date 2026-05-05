class BooleanDefaultBackfill < DataDrip::Backfill
  attribute :dry_run, :boolean, default: true

  def scope
    Employee.where(role: nil)
  end

  def process_element(element)
    element.update!(role: "intern") unless dry_run
  end
end
