class AddRoleToEmployee < DataDrip::Backfill

  attribute :employee_id, :integer
  
  def scope
    Employee.where(role: nil)
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
#   batch.update_all(role: 'intern')
# end

  # If you need to process each element individually, implement this method.
  # This is useful when you need to perform more complex operations on each element.
  #
  # Example:
  # def process_element(element)
  #   element.update!(role: 'new_role')
  # end

  def process_batch(batch)
    batch.update_all(role: 'intern')
  end

  def process_element(element)
    # Process each element with the changes that you need to do
    # Example: element.update!(attribute: element.other_attribute * 100)
    raise NotImplementedError
  end
end