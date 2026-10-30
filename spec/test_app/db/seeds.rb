# Minimal data to play with the engine in development.
# The test_app's ApplicationController#current_user returns User.first!.
cell_id = ENV["CELL_ID"].presence

if cell_id
  # Multi-cell mode requires backfiller ids not to be reused between cells, so
  # each cell's user gets an id from its own range (cell-a 1001, cell-b 2001…).
  cell_index = ENV.fetch("CELL_IDS", "cell-a,cell-b,cell-c").split(",").map(&:strip).index(cell_id).to_i
  User.find_or_create_by!(name: "Dev User (#{cell_id})") { |user| user.id = (cell_index + 1) * 1000 + 1 }
else
  User.find_or_create_by!(name: "Dev User")
end

employees = [
  { name: "John", age: 25 },
  { name: "Jane", age: 30 },
  { name: "Bob", age: 25 },
  { name: "Alice", age: 41 }
]
# A row only this cell has, so a run's results differ between cells.
employees << { name: "Local to #{cell_id}", age: 35 } if cell_id

employees.each do |attrs|
  Employee.find_or_create_by!(name: attrs[:name]) do |employee|
    employee.age = attrs[:age]
  end
end
