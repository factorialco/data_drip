# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::ScriptRunner, type: :job do
  let!(:backfiller) { User.create!(name: "Test User") }
  let!(:employee1) { Employee.create!(name: "John", role: nil, age: 25) }
  let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }

  describe "#perform" do
    context "when the script succeeds" do
      let(:script_run) do
        DataDrip::ScriptRun.create!(
          script_class_name: "GreetEmployees",
          backfiller: backfiller,
          inputs: {
            greeting: "Hello",
            dry_run: "0",
            repeat: "2"
          }
        )
      end

      it "runs the script with coerced inputs and applies its side effects" do
        described_class.new.perform(script_run)

        expect(employee1.reload.role).to eq("greeted")
        expect(employee2.reload.role).to eq("greeted")
      end

      it "marks the run completed with timestamps" do
        described_class.new.perform(script_run)

        script_run.reload
        expect(script_run.status).to eq("completed")
        expect(script_run.started_at).to be_present
        expect(script_run.finished_at).to be_present
        expect(script_run.finished_at).to be >= script_run.started_at
      end

      it "captures timestamped log output in order" do
        described_class.new.perform(script_run)

        lines = script_run.reload.output.lines
        expect(lines.length).to eq(5) # 2 employees x repeat 2 + final summary
        expect(lines[0]).to match(/\[\d{4}-\d{2}-\d{2}T.*\] Hello, John!/)
        expect(lines.last).to include("Done greeting 2 employees")
      end
    end

    context "when the script fails" do
      let(:script_run) do
        DataDrip::ScriptRun.create!(
          script_class_name: "AlwaysFails",
          backfiller: backfiller,
          inputs: {
            message: "custom explosion"
          }
        )
      end

      it "marks the run failed, stores the error and re-raises" do
        expect { described_class.new.perform(script_run) }.to raise_error(
          StandardError,
          "custom explosion"
        )

        script_run.reload
        expect(script_run.status).to eq("failed")
        expect(script_run.error_message).to eq("custom explosion")
        expect(script_run.error_backtrace).to include("always_fails.rb")
        expect(script_run.finished_at).to be_present
      end

      it "preserves the output logged before the failure" do
        expect { described_class.new.perform(script_run) }.to raise_error(
          StandardError
        )

        expect(script_run.reload.output).to include("about to fail")
      end
    end
  end
end
