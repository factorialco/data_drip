# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::ScriptRun, type: :model do
  let!(:backfiller) { User.create!(name: "Test User") }

  let(:valid_attributes) do
    {
      script_class_name: "GreetEmployees",
      backfiller: backfiller,
      inputs: {
        greeting: "Hello",
        dry_run: true
      }
    }
  end

  describe "validations" do
    it "is valid with a known script class and valid inputs" do
      expect(DataDrip::ScriptRun.new(valid_attributes)).to be_valid
    end

    it "validates presence of script_class_name" do
      script_run = DataDrip::ScriptRun.new(backfiller: backfiller)

      expect(script_run).not_to be_valid
      expect(script_run.errors[:script_class_name]).to include("can't be blank")
    end

    it "validates script_class exists" do
      script_run =
        DataDrip::ScriptRun.new(
          valid_attributes.merge(script_class_name: "NonExistentClass")
        )

      expect(script_run).not_to be_valid
      expect(script_run.errors[:script_class_name]).to include(
        "must be a valid DataDrip script class"
      )
    end

    it "is invalid when a required input is missing" do
      script_run =
        DataDrip::ScriptRun.new(
          valid_attributes.merge(inputs: { dry_run: true })
        )

      expect(script_run).not_to be_valid
      expect(script_run.errors[:inputs]).to include("greeting can't be blank")
    end

    it "is invalid when a required boolean input is missing" do
      script_run =
        DataDrip::ScriptRun.new(
          valid_attributes.merge(inputs: { greeting: "Hello" })
        )

      expect(script_run).not_to be_valid
      expect(script_run.errors[:inputs]).to include("dry_run can't be blank")
    end

    it "accepts false for a required boolean input" do
      script_run =
        DataDrip::ScriptRun.new(
          valid_attributes.merge(inputs: { greeting: "Hello", dry_run: "0" })
        )

      expect(script_run).to be_valid
    end

    it "is invalid with unknown input keys" do
      script_run =
        DataDrip::ScriptRun.new(
          valid_attributes.merge(
            inputs: {
              greeting: "Hello",
              dry_run: true,
              bogus: "nope"
            }
          )
        )

      expect(script_run).not_to be_valid
      expect(script_run.errors[:inputs].join).to include("unknown attribute")
    end
  end

  describe "start_at default" do
    it "defaults start_at to the current time on create" do
      script_run = DataDrip::ScriptRun.create!(valid_attributes)

      expect(script_run.start_at).to be_within(5.seconds).of(Time.current)
    end

    it "keeps an explicitly provided start_at" do
      start_at = 2.hours.from_now
      script_run =
        DataDrip::ScriptRun.create!(valid_attributes.merge(start_at: start_at))

      expect(script_run.start_at).to be_within(1.second).of(start_at)
    end
  end

  describe "#script_class" do
    it "returns the script class" do
      expect(DataDrip::ScriptRun.new(valid_attributes).script_class).to eq(
        GreetEmployees
      )
    end

    it "returns nil for an unknown class name" do
      script_run =
        DataDrip::ScriptRun.new(script_class_name: "NonExistentClass")

      expect(script_run.script_class).to be_nil
    end
  end

  describe "enqueueing" do
    include ActiveJob::TestHelper

    after { clear_enqueued_jobs }

    it "enqueues a ScriptRunner job on create and transitions to enqueued" do
      script_run = DataDrip::ScriptRun.create!(valid_attributes)

      expect(DataDrip::ScriptRunner).to have_been_enqueued.with(script_run)
      expect(script_run.reload.status).to eq("enqueued")
    end

    it "enqueues with wait_until when start_at is in the future" do
      start_at = 2.hours.from_now
      DataDrip::ScriptRun.create!(valid_attributes.merge(start_at: start_at))

      expect(DataDrip::ScriptRunner).to have_been_enqueued.at(
        a_value_within(1.second).of(start_at)
      )
    end
  end

  describe "hooks" do
    before { DataDrip.hooks_handler_class_name = "HookHandler" }
    after { DataDrip.hooks_handler_class_name = nil }

    it "prefers the script class hook over the global handler" do
      script_run = DataDrip::ScriptRun.create!(valid_attributes)
      script_run.completed!

      expect(
        HookNotifier.instance.get("GreetEmployees_script_run_completed")
      ).to eq(script_run.id)
      expect(
        HookNotifier.instance.get("HookHandler_script_run_completed")
      ).to be_nil
    end

    it "falls back to the global handler when the class defines no hook" do
      script_run = DataDrip::ScriptRun.create!(valid_attributes)

      expect(
        HookNotifier.instance.get("HookHandler_script_run_enqueued")
      ).to eq(script_run.id)
    end
  end

  describe "#append_output" do
    it "appends lines to output and persists them" do
      script_run = DataDrip::ScriptRun.create!(valid_attributes)

      script_run.append_output("line one")
      script_run.append_output("line two")

      expect(script_run.reload.output).to eq("line one\nline two\n")
    end
  end
end
