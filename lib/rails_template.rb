# rails_template.rb

# Set application name
app_name = "data_drip_dummy"

# Add the Employee model
after_bundle do
  # Add the DataDrip gem with local path
  gem "data_drip", path: ".."

  # Run bundle install again for the new gem
  run "bundle install"

  # Generate Employee model
  generate :model, "Employee", "name:string", "age:integer", "role:string"

  # Migrate database
  rails_command "db:migrate"

  # Create seed file with 1000 Employees
  append_to_file "db/seeds.rb", <<~RUBY

    puts "Seeding employees..."
    1000.times do |i|
      Employee.create!(
        name: "Employee \#{i + 1}",
        age: rand(20..60),
        role: nil
      )
    end
    puts "Seeding complete!"
  RUBY

  rails_command "db:seed"

  # Run DataDrip install generator
  rails_command "generate data_drip:install"

  # Run DataDrip backfill generator
  # rails_command "generate data_drip:backfill add_role_to_employee"
end
