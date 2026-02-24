# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::Backfill, type: :model do
  let(:test_backfill_class) { AddRoleToEmployee }

  describe ".attribute" do
    it "defines attribute methods on the class" do
      expect(test_backfill_class.new).to respond_to(:age)
      expect(test_backfill_class.new).to respond_to(:name)
    end

    it "creates attribute types in the backfill_options_class" do
      attribute_types =
        test_backfill_class.backfill_options_class.attribute_types

      expect(attribute_types["age"]).to be_a(ActiveModel::Type::Integer)
      expect(attribute_types["name"]).to be_a(ActiveModel::Type::String)
    end

    it "raises error when trying to define an existing method" do
      expect do
        Class.new(DataDrip::Backfill) { attribute :scope, :string }
      end.to raise_error(/Method scope already defined/)
    end

    it "registers :enum as a DataDrip::Types::Enum type" do
      klass = Class.new(DataDrip::Backfill) do
        attribute :color, :enum, values: %w[red green blue]
      end

      attr_type = klass.backfill_options_class.attribute_types["color"]
      expect(attr_type).to be_a(DataDrip::Types::Enum)
      expect(attr_type.available_values).to eq(%w[red green blue])
    end

    it "supports callable values for :enum type" do
      klass = Class.new(DataDrip::Backfill) do
        attribute :items, :enum, values: -> { %w[a b c] }
      end

      attr_type = klass.backfill_options_class.attribute_types["items"]
      expect(attr_type).to be_a(DataDrip::Types::Enum)
      expect(attr_type.available_values).to eq(%w[a b c])
    end

    it "casts :enum values as strings" do
      klass = Class.new(DataDrip::Backfill) do
        attribute :color, :enum, values: %w[red green blue]
      end

      instance = klass.new(backfill_options: { color: "red,green" })
      expect(instance.color).to eq("red,green")
    end

    it "stores form_default in attribute_metadata" do
      klass = Class.new(DataDrip::Backfill) do
        attribute :start_date, :date, form_default: "2010-01-01"
      end

      expect(klass.attribute_metadata[:start_date]).to eq({ form_default: "2010-01-01" })
    end

    it "stores callable form_default in attribute_metadata" do
      klass = Class.new(DataDrip::Backfill) do
        attribute :end_date, :date, form_default: -> { Date.current }
      end

      expect(klass.attribute_metadata[:end_date][:form_default]).to respond_to(:call)
    end

    it "does not store metadata for plain attributes" do
      expect(test_backfill_class.attribute_metadata).to be_empty
    end
  end

  describe ".backfill_options_class" do
    it "creates a class that includes ActiveModel::Attributes" do
      options_class = test_backfill_class.backfill_options_class

      expect(options_class.ancestors).to include(ActiveModel::Attributes)
      expect(options_class.ancestors).to include(ActiveModel::API)
    end

    it "can create instances with attributes" do
      options =
        test_backfill_class.backfill_options_class.new(age: 25, name: "John")

      expect(options.age).to eq(25)
      expect(options.name).to eq("John")
    end
  end

  describe "#initialize" do
    it "accepts backfill_options and makes them accessible via attributes" do
      backfill =
        test_backfill_class.new(backfill_options: { age: "25", name: "John" })

      expect(backfill.age).to eq(25)
      expect(backfill.name).to eq("John")
    end

    it "sets default values for batch_size and sleep_time" do
      backfill = test_backfill_class.new

      expect(backfill.instance_variable_get(:@batch_size)).to eq(100)
      expect(backfill.instance_variable_get(:@sleep_time)).to eq(
        DataDrip.sleep_time
      )
    end

    it "allows overriding batch_size and sleep_time" do
      backfill = test_backfill_class.new(batch_size: 50, sleep_time: 2)

      expect(backfill.instance_variable_get(:@batch_size)).to eq(50)
      expect(backfill.instance_variable_get(:@sleep_time)).to eq(2)
    end

    it "handles empty backfill_options" do
      backfill = test_backfill_class.new(backfill_options: {})

      expect(backfill.age).to be_nil
      expect(backfill.name).to be_nil
    end
  end

  describe "attribute delegation" do
    it "delegates attribute access to backfill_options" do
      backfill =
        test_backfill_class.new(backfill_options: { name: "delegated" })

      expect(backfill.name).to eq("delegated")
      expect(backfill.backfill_options.name).to eq("delegated")
    end

    it "returns nil for unset attributes" do
      backfill = test_backfill_class.new

      expect(backfill.age).to be_nil
      expect(backfill.name).to be_nil
    end
  end

  describe "abstract methods" do
    let(:minimal_backfill_class) { Class.new(DataDrip::Backfill) { } }

    it "raises NotImplementedError for scope when not defined" do
      backfill = minimal_backfill_class.new

      expect { backfill.scope }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for process_element when not defined" do
      backfill = minimal_backfill_class.new

      expect { backfill.send(:process_element, nil) }.to raise_error(
        NotImplementedError
      )
    end
  end

  describe "#count" do
    let!(:employee1) { Employee.create!(name: "John", role: nil, age: 25) }
    let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }

    it "delegates to scope.count" do
      backfill = test_backfill_class.new

      expect(backfill.count).to eq(backfill.scope.count)
      expect(backfill.count).to eq(2)
    end

    it "respects filtering options in count" do
      backfill = test_backfill_class.new(backfill_options: { age: 25 })

      expect(backfill.count).to eq(1)
    end
  end

  describe "#backfill_options" do
    it "provides access to the options object" do
      backfill =
        test_backfill_class.new(backfill_options: { name: "accessible" })

      expect(backfill.backfill_options).to be_a(
        test_backfill_class.backfill_options_class
      )
      expect(backfill.backfill_options.name).to eq("accessible")
    end
  end

  describe "framework integration" do
    let!(:employee1) { Employee.create!(name: "John", role: nil, age: 25) }
    let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }

    it "works end-to-end with real data" do
      backfill = test_backfill_class.new(backfill_options: { age: 25 })

      scope = backfill.scope
      expect(scope.count).to eq(1)
      expect(scope.first.name).to eq("John")

      backfill.send(:process_batch, scope)
      expect(employee1.reload.role).to eq("intern")
      expect(employee2.reload.role).to be_nil
    end
  end
end
