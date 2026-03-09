# frozen_string_literal: true

require "spec_helper"

RSpec.describe "HookHandler" do
  let!(:employee2) { Employee.create!(name: "Jane", role: nil, age: 30) }
  let!(:backfill_run) do
    DataDrip::BackfillRun.create!(
      {
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: User.create!(name: "Test User")
      }
    )
  end
  context "when the hook handler is configured" do
    before { DataDrip.hooks_handler_class_name = "HookHandler" }

    it "calls the expected hook" do
      expect(HookHandler).to receive(:after_run_enqueued).and_call_original
      backfill_run.update_column(:status, :pending)
      backfill_run.enqueue
    end

    it "runs before hooks and wraps the enqueue action with around hooks" do
      backfill_run.update_column(:status, :pending)
      HookNotifier.instance.set("handler_run_enqueued_sequence", [])
      backfill_run.enqueue

      expect(
        HookNotifier.instance.get("handler_run_enqueued_sequence")
      ).to eq(%w[before around_before around_after after])
    end

    it "Doesn't raise an error if a hook method is not implemented" do
      expect { backfill_run.enqueued! }.not_to raise_error
    end

    it "Doesn't call the hook handler if the hook is implemented in the backfill class" do
      expect(HookHandler).not_to receive(:after_run_completed)
      backfill_run.completed!
    end

    context "with batch hooks" do
      let!(:batch) do
        DataDrip::BackfillRunBatch.create!(
          {
            backfill_run: backfill_run,
            start_id: 1,
            finish_id: 100,
            batch_size: 100
          }
        )
      end

      it "calls the expected batch hook from handler" do
        expect(HookHandler).to receive(:after_batch_enqueued).and_call_original
        batch.update_column(:status, :pending)
        batch.enqueued!
      end

      it "doesn't raise an error if a batch hook method is not implemented" do
        expect { batch.running! }.not_to raise_error
      end

      it "doesn't call the hook handler if the hook is implemented in the backfill class" do
        expect(HookHandler).not_to receive(:after_batch_completed)
        batch.completed!
      end

      it "wraps batch run with around hooks" do
        HookNotifier.instance.set("handler_batch_running_sequence", [])
        allow(batch).to receive(:sleep)

        batch.run!

        expect(
          HookNotifier.instance.get("handler_batch_running_sequence")
        ).to eq(%w[before around_before around_after after])
      end
    end
  end

  context "when the hook handler is not configured" do
    before { DataDrip.hooks_handler_class_name = nil }

    it "does not call any hooks" do
      expect(HookHandler).not_to receive(:after_run_enqueued)
      backfill_run.enqueued!
    end

    it "does not call batch hooks" do
      batch =
        DataDrip::BackfillRunBatch.create!(
          {
            backfill_run: backfill_run,
            start_id: 1,
            finish_id: 100,
            batch_size: 100
          }
        )
      expect(HookHandler).not_to receive(:after_batch_enqueued)
      batch.update_column(:status, :pending)
      batch.enqueued!
    end
  end
end
