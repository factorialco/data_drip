# frozen_string_literal: true

require "spec_helper"

RSpec.describe "HookHandler" do
  let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }
  let!(:backfill_run) do
    DataDrip::BackfillRun.create!({
      backfill_class_name: "AddRoleToEmployee",
      batch_size: 100,
      start_at: 1.hour.from_now,
      backfiller: User.create!(name: "Test User")
    })
  end
  context "when the hook handler is configured" do
    before do
      DataDrip.hooks_handler_class_name = "HookHandler"
    end

    it "calls the expected hook" do
      expect(HookHandler).to receive(:on_run_enqueued).and_call_original
      backfill_run.update_column(:status, :pending)
      backfill_run.enqueued!
    end

    it "Doesn't raise an error if a hook method is not implemented" do
      expect { backfill_run.enqueued! }.not_to raise_error
    end

    it "Doesn't call the hook handler if the hook is implemented in the backfill class" do
      expect(HookHandler).not_to receive(:on_run_completed)
      backfill_run.completed!
    end
  end

  context "when the hook handler is not configured" do
    before do
      DataDrip.hooks_handler_class_name = nil
    end

    it "does not call any hooks" do
      expect(HookHandler).not_to receive(:on_run_enqueued)
      backfill_run.enqueued!
    end
  end
end
