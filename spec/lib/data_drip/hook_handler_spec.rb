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

  # hooks_handler_class_name is global config; restore it so these examples
  # don't leak state into the rest of the suite.
  around do |example|
    original = DataDrip.hooks_handler_class_name
    example.run
  ensure
    DataDrip.hooks_handler_class_name = original
  end

  context "when the hook handler is configured" do
    before { DataDrip.hooks_handler_class_name = "HookHandler" }

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
        expect(HookHandler).to receive(:on_batch_enqueued).and_call_original
        batch.update_column(:status, :pending)
        batch.enqueued!
      end

      it "doesn't raise an error if a batch hook method is not implemented" do
        expect { batch.running! }.not_to raise_error
      end

      it "doesn't call the hook handler if the hook is implemented in the backfill class" do
        expect(HookHandler).not_to receive(:on_batch_completed)
        batch.completed!
      end
    end
  end

  # `enqueue` commits its own `enqueued!` transition from inside the creating commit. Hooks must
  # still fire once per transition, whatever order the app runs after_commit callbacks in.
  context "when a record is created and enqueued" do
    before { DataDrip.hooks_handler_class_name = "HookHandler" }

    def hooks_fired(handler, hooks)
      fired = []
      hooks.each do |hook|
        allow(handler).to receive(hook) { |record| fired << [ hook, record.status ] }
      end
      yield
      fired
    end

    it "fires each run hook once" do
      backfill_run.delete # an identical pending run would fail validation
      fired =
        hooks_fired(HookHandler, %i[on_run_pending on_run_enqueued]) do
          DataDrip::BackfillRun.create!(
            backfill_class_name: "AddRoleToEmployee",
            batch_size: 100,
            start_at: Time.current,
            backfiller: User.create!(name: "Test User")
          )
        end

      expect(fired).to eq([ [ :on_run_enqueued, "enqueued" ] ])
    end

    it "fires each batch hook once" do
      fired =
        hooks_fired(HookHandler, %i[on_batch_pending on_batch_enqueued]) do
          DataDrip::BackfillRunBatch.create!(
            backfill_run: backfill_run,
            start_id: 1,
            finish_id: 100,
            batch_size: 100
          )
        end

      expect(fired).to eq([ [ :on_batch_enqueued, "enqueued" ] ])
    end

    it "fires each script run hook once" do
      fired =
        hooks_fired(HookHandler, %i[on_script_run_pending on_script_run_enqueued]) do
          DataDrip::ScriptRun.create!(
            script_class_name: "GreetEmployees",
            backfiller: User.create!(name: "Test User"),
            inputs: { greeting: "Hello", dry_run: true }
          )
        end

      expect(fired).to eq([ [ :on_script_run_enqueued, "enqueued" ] ])
    end
  end

  context "when the hook handler is not configured" do
    before { DataDrip.hooks_handler_class_name = nil }

    it "does not call any hooks" do
      expect(HookHandler).not_to receive(:on_run_enqueued)
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
      expect(HookHandler).not_to receive(:on_batch_enqueued)
      batch.update_column(:status, :pending)
      batch.enqueued!
    end
  end
end
