# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::BackfillRunsHelper, type: :helper do
  describe "#backfill_option_inputs" do
    let!(:backfiller) { User.create!(name: "Test User") }

    context "with boolean attributes" do
      let(:backfill_run) do
        DataDrip::BackfillRun.new(
          backfill_class_name: "TestBackfillWithDefaults",
          batch_size: 100,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          options: {}
        )
      end

      it "renders checkbox as checked when default is true" do
        html = helper.backfill_option_inputs(backfill_run)

        # Parse the HTML to check the checkbox state
        expect(html).to include('name="backfill_run[options][dry_run]"')
        expect(html).to include('type="checkbox"')

        # The checkbox should be checked for dry_run (default: true)
        # In Rails, checked checkboxes have the 'checked' attribute
        dry_run_checkbox = html.match(/name="backfill_run\[options\]\[dry_run\]"[^>]*/)
        expect(dry_run_checkbox.to_s).to include('checked')
      end

      it "renders checkbox as unchecked when default is false" do
        html = helper.backfill_option_inputs(backfill_run)

        # The checkbox for verbose (default: false) should not be checked
        expect(html).to include('name="backfill_run[options][verbose]"')

        # Extract the verbose checkbox HTML
        verbose_section = html.match(/name="backfill_run\[options\]\[verbose\]"[^>]*/)
        expect(verbose_section.to_s).not_to include('checked')
      end

      it "uses default value for text fields" do
        html = helper.backfill_option_inputs(backfill_run)

        # Text field should have the default value
        expect(html).to include('name="backfill_run[options][name]"')
        expect(html).to include('value="default_name"')
      end
    end

    context "when backfill has no options class" do
      let(:backfill_run) do
        DataDrip::BackfillRun.new(
          backfill_class_name: "AddRoleToEmployee",
          batch_size: 100,
          start_at: 1.hour.from_now,
          backfiller: backfiller,
          options: {}
        )
      end

      it "still works for backfills without default values" do
        html = helper.backfill_option_inputs(backfill_run)

        expect(html).to include('name="backfill_run[options][age]"')
        expect(html).to include('name="backfill_run[options][name]"')
      end
    end
  end
end
