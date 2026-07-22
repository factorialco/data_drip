# Example backfill demonstrating a mandatory option (role) next to an
# optional one (max_age). The run cannot be created until role is filled in.
class SetEmployeeRole < DataDrip::Backfill
  attribute :role, :string, required: true
  attribute :max_age, :integer

  def scope
    scope = Employee.all
    scope = scope.where(age: ..max_age) if max_age.present?
    scope
  end

  def process_batch(batch)
    batch.update_all(role: role)
  end
end
