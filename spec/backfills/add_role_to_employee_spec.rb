require "spec_helper"

RSpec.describe AddRoleToEmployee, type: :model do
  let!(:employee1) { Employee.create!(name: "John", role: nil, age: 25) }
  let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }
  let!(:employee3) { Employee.create!(name: "Bob", role: nil, age: 25) }
  let!(:employee4) { Employee.create!(name: "Alice", role: "manager", age: 25) }

  describe "attributes" do
    it "can create an instance and access attributes" do
      backfill = AddRoleToEmployee.new

      expect(backfill).to respond_to(:age)
      expect(backfill).to respond_to(:name)
    end

    it "can access attribute values set through backfill_options" do
      backfill =
        AddRoleToEmployee.new(backfill_options: { age: 25, name: "John" })

      expect(backfill.age).to eq(25)
      expect(backfill.name).to eq("John")
    end

    it "supports type casting for integer attributes" do
      backfill = AddRoleToEmployee.new(backfill_options: { age: "25" })

      expect(backfill.age).to eq(25) # Should be cast to integer
    end

    it "returns nil for unset attributes" do
      backfill = AddRoleToEmployee.new

      expect(backfill.age).to be_nil
      expect(backfill.name).to be_nil
    end
  end

  describe "#scope" do
    context "with no options" do
      it "returns all employees with nil role" do
        backfill = AddRoleToEmployee.new

        scope = backfill.scope

        expect(scope.count).to eq(3) # employee1, employee2, employee3
        expect(scope.pluck(:role)).to all(be_nil)
      end
    end

    context "with age option" do
      it "filters by age when age is present" do
        backfill = AddRoleToEmployee.new(backfill_options: { age: 25 })

        scope = backfill.scope

        expect(scope.count).to eq(2) # employee1, employee3
        expect(scope.pluck(:age)).to all(eq(25))
        expect(scope.pluck(:role)).to all(be_nil)
      end

      it "ignores age filter when age is blank" do
        backfill = AddRoleToEmployee.new(backfill_options: { age: "" })

        scope = backfill.scope

        expect(scope.count).to eq(3) # All employees with nil role
      end

      it "ignores age filter when age is nil" do
        backfill = AddRoleToEmployee.new(backfill_options: { age: nil })

        scope = backfill.scope

        expect(scope.count).to eq(3) # All employees with nil role
      end
    end

    context "with name option" do
      it "filters by name when name is present" do
        backfill = AddRoleToEmployee.new(backfill_options: { name: "John" })

        scope = backfill.scope

        expect(scope.count).to eq(1) # employee1
        expect(scope.first.name).to eq("John")
        expect(scope.first.role).to be_nil
      end

      it "ignores name filter when name is blank" do
        backfill = AddRoleToEmployee.new(backfill_options: { name: "" })

        scope = backfill.scope

        expect(scope.count).to eq(3) # All employees with nil role
      end
    end

    context "with multiple options" do
      it "applies both filters (AND condition)" do
        backfill =
          AddRoleToEmployee.new(backfill_options: { age: 25, name: "John" })

        scope = backfill.scope

        expect(scope.count).to eq(1) # Only employee1 matches both conditions
        expect(scope.first.name).to eq("John")
        expect(scope.first.age).to eq(25)
        expect(scope.first.role).to be_nil
      end

      it "ignores blank values in multiple options" do
        backfill =
          AddRoleToEmployee.new(backfill_options: { age: 25, name: "" })

        scope = backfill.scope

        expect(scope.count).to eq(2) # employee1, employee3 (only age filter applied)
        expect(scope.pluck(:age)).to all(eq(25))
      end
    end
  end

  describe "#process_batch" do
    it "updates all records in the batch to have role 'intern'" do
      employees = Employee.where(role: nil).limit(2)
      employee_ids = employees.pluck(:id)
      backfill = AddRoleToEmployee.new

      backfill.process_batch(employees)

      expect(Employee.where(id: employee_ids).pluck(:role)).to all(eq("intern"))
    end
  end

  describe "backfill_options class" do
    it "defines the correct attribute types" do
      options_class = AddRoleToEmployee.backfill_options_class
      attribute_types = options_class.attribute_types

      expect(attribute_types["age"]).to be_a(ActiveModel::Type::Integer)
      expect(attribute_types["name"]).to be_a(ActiveModel::Type::String)
    end

    it "can create an instance of the options class" do
      options =
        AddRoleToEmployee.backfill_options_class.new(age: 25, name: "John")

      expect(options.age).to eq(25)
      expect(options.name).to eq("John")
    end
  end
end
