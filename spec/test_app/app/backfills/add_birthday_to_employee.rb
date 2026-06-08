
class AddBirthdayToEmployee < DataDrip::Backfill
  attribute :employee_id, :integer
  def self.description
    "Sets today's date as the **birthday** for all employees missing one.\n\n" \
    "## Options\n" \
    "- `employee_id`: Target a **single employee** by ID (optional)\n\n" \
    "## Finding an employee ID\n" \
    "You can get the ID from an email with:\n" \
    "```\n" \
    "SELECT id FROM employees\n" \
    "WHERE email = 'jane@example.com';\n" \
    "```\n\n" \
    "## Notes\n" \
    "- Uses `update_all` for fast batch processing\n" \
    "- Safe to re-run — only touches employees where `birthday` is `nil`"
  end
def scope
    Employee.where(birthday: nil)
  end


  #######################################################
  ## YOU DON'T NEED TO IMPLEMENT BOTH METHODS          ##
  ##                                                   ##
  ## EITHER IMPLEMENT process_batch OR process_element ##
  #######################################################

  # TODO: explain if you can yse update_all use process_batch, otherwise use process_element

  # If you want to process the whole batch at once, implement this method.
  # This is useful when you can use `update_all` or similar methods.
  #
  # Example:
  # def process_batch(batch)
  #   batch.update_all(birthday: Date.today)
  # end

  # If you need to process each element individually, implement this method.
  # This is useful when you need to perform more complex operations on each element.
  #
  # Example:
  # def process_element(element)
  #   element.update!(role: 'new_role')
  # end


  def process_batch(batch)
    batch.update_all(birthday: Date.today)
  end


  def process_element(element)
    # Process each element with the changes that you need to do
    # Example: element.update!(attribute: element.other_attribute * 100)
    raise NotImplementedError
  end
end
