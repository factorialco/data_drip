# Minimal data to play with the engine in development.
# The test_app's ApplicationController#current_user returns User.first!.
User.find_or_create_by!(name: "Dev User")

[
  { name: "John", age: 25 },
  { name: "Jane", age: 30 },
  { name: "Bob", age: 25 },
  { name: "Alice", age: 41 }
].each do |attrs|
  Employee.find_or_create_by!(name: attrs[:name]) do |employee|
    employee.age = attrs[:age]
  end
end
