# rails_template.rb

# Set application name
app_name = "data_drip_dummy"

possible_paths = [
  File.expand_path("..", Dir.pwd),
  File.expand_path("../..", Dir.pwd)
]
gem_path =
  possible_paths.find do |path|
    File.exist?(File.join(path, "data_drip.gemspec"))
  end

raise "Could not find data_drip.gemspec in expected locations" unless gem_path

# Add the Employee model
after_bundle do
  # Add the DataDrip gem with local path
  gem "data_drip", path: gem_path

  # Run bundle install again for the new gem
  run "bundle install"

  # Generate Employee model
  generate :model, "Employee", "name:string", "age:integer", "role:string"
  generate :model, "User", "name:string"

  # Migrate database
  rails_command "db:migrate"

  # Create seed file with 1000 Employees
  append_to_file "db/seeds.rb", <<~RUBY

    puts "Seeding users..."
    User.create!(name: "Suzie")

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
  rails_command "generate data_drip:backfill add_role_to_employee"

  # Update the scope method in the generated backfill
  gsub_file "app/backfills/add_role_to_employee.rb",
            /def scope.*?end/m,
            "def scope\n    Employee.where(role: nil)\n  end\n"

  # Update all occurrences of the process batch method in the generated backfill
  gsub_file "app/backfills/add_role_to_employee.rb",
            /(def |# def )process_batch\(batch\)(?:.|\n)*?end/m do |match|
    if match.lstrip.start_with?("#")
      # Comment each line of the replacement
      "# def process_batch(batch)\n#   batch.update_all(role: 'intern')\n# end"
    else
      "def process_batch(batch)\n    batch.update_all(role: 'intern')\n  end"
    end
  end

  gsub_file "app/controllers/application_controller.rb",
            "ActionController::Base",
            "ActionController::Base\n\ndef find_current_backfiller\n  User.first!\nend\n"
end
