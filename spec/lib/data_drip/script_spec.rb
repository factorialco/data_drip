# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::Script, type: :model do
  describe ".input" do
    it "defines reader methods delegating to inputs" do
      script = GreetEmployees.new(inputs: { greeting: "Hi" })

      expect(script.greeting).to eq("Hi")
      expect(script.inputs.greeting).to eq("Hi")
    end

    it "creates attribute types in the inputs_class" do
      attribute_types = GreetEmployees.inputs_class.attribute_types

      expect(attribute_types["greeting"]).to be_a(ActiveModel::Type::String)
      expect(attribute_types["repeat"]).to be_a(ActiveModel::Type::Integer)
      expect(attribute_types["dry_run"]).to be_a(ActiveModel::Type::Boolean)
      expect(attribute_types["effective_date"]).to be_a(ActiveModel::Type::Date)
    end

    it "raises error when trying to define an existing method" do
      expect do
        Class.new(DataDrip::Script) { input :call, :string }
      end.to raise_error(/Method call already defined/)
    end

    it "registers :enum as a DataDrip::Types::Enum type" do
      klass = Class.new(DataDrip::Script) do
        input :color, :enum, values: %w[red green blue]
      end

      attr_type = klass.inputs_class.attribute_types["color"]
      expect(attr_type).to be_a(DataDrip::Types::Enum)
      expect(attr_type.available_values).to eq(%w[red green blue])
    end

    it "coerces string values to the declared type" do
      script =
        GreetEmployees.new(
          inputs: {
            greeting: "Hi",
            repeat: "3",
            effective_date: "2026-07-22"
          }
        )

      expect(script.repeat).to eq(3)
      expect(script.effective_date).to eq(Date.new(2026, 7, 22))
    end

    it "applies defaults and allows overriding them" do
      expect(GreetEmployees.new.repeat).to eq(1)
      expect(GreetEmployees.new(inputs: { repeat: 5 }).repeat).to eq(5)
    end
  end

  describe "required inputs" do
    it "tracks required attribute names" do
      expect(GreetEmployees.required_inputs).to include("greeting", "dry_run")
      expect(GreetEmployees.required_inputs).not_to include("repeat")
    end

    it "marks the inputs object invalid when a required string is missing or blank" do
      expect(GreetEmployees.inputs_class.new(dry_run: true)).not_to be_valid
      expect(
        GreetEmployees.inputs_class.new(greeting: "", dry_run: true)
      ).not_to be_valid
      expect(
        GreetEmployees.inputs_class.new(greeting: "Hi", dry_run: true)
      ).to be_valid
    end

    it "accepts false for a required boolean but rejects nil" do
      expect(
        GreetEmployees.inputs_class.new(greeting: "Hi", dry_run: false)
      ).to be_valid
      expect(
        GreetEmployees.inputs_class.new(greeting: "Hi", dry_run: "0")
      ).to be_valid
      expect(GreetEmployees.inputs_class.new(greeting: "Hi")).not_to be_valid
    end
  end

  describe ".description" do
    it "returns the configured description" do
      expect(GreetEmployees.description).to be_present
    end

    it "returns nil when not set" do
      klass = Class.new(DataDrip::Script)
      expect(klass.description).to be_nil
    end
  end

  describe "#log" do
    it "sends timestamped lines to the injected logger" do
      lines = []
      script =
        GreetEmployees.new(
          inputs: { greeting: "Hi", dry_run: true },
          logger: ->(line) { lines << line }
        )

      script.log("hello")

      expect(lines.size).to eq(1)
      expect(lines.first).to match(/\A\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\] hello\z/)
    end
  end

  describe "#call" do
    it "raises NotImplementedError when not defined" do
      expect { Class.new(DataDrip::Script).new.call }.to raise_error(
        NotImplementedError
      )
    end
  end

  describe "DataDrip.scripts" do
    it "lists Script descendants" do
      expect(DataDrip.scripts).to include(GreetEmployees, AlwaysFails)
      expect(DataDrip.scripts).not_to include(AddRoleToEmployee)
    end
  end
end
