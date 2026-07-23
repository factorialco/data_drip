class GreetEmployees < DataDrip::Script
  description "Logs a greeting for every employee, optionally updating their role."

  input :greeting, :string, required: true
  input :repeat, :integer, default: 1
  input :dry_run, :boolean, required: true
  input :effective_date, :date

  def call
    Employee.find_each do |employee|
      repeat.times { log "#{greeting}, #{employee.name}!" }
      employee.update!(role: "greeted") unless dry_run
    end
    log "Done greeting #{Employee.count} employees"
  end

  def self.on_script_run_completed(run)
    HookNotifier.instance.set("GreetEmployees_script_run_completed", run.id)
  end
end
