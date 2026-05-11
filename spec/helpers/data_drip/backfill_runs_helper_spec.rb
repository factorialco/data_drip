# frozen_string_literal: true

require "spec_helper"

# Inline backfill class so we don't add boolean fields to the existing
# test fixtures. The default: true mirrors the real-world bug — when the
# form omits the field, the server-side default silently re-applies.
class DryRunnableBackfill < DataDrip::Backfill
  attribute :dry_run, :boolean, default: true

  def scope
    Employee.all
  end

  def process_element(_element); end
end

RSpec.describe DataDrip::BackfillRunsHelper, type: :helper do
  describe "#backfill_option_inputs with a boolean attribute" do
    let(:backfill_run) do
      DataDrip::BackfillRun.new(
        backfill_class_name: "DryRunnableBackfill",
        options: {}
      )
    end

    let(:html) { helper.backfill_option_inputs(backfill_run) }

    it "pairs the checkbox with a hidden 0 field so unchecked submits explicit false" do
      expect(html).to include(
        %(<input type="hidden" name="backfill_run[options][dry_run]" value="0")
      )
    end

    it "still renders the checkbox itself with value 1" do
      expect(html).to match(
        %r{<input[^>]*type="checkbox"[^>]*name="backfill_run\[options\]\[dry_run\]"[^>]*value="1"}
      )
    end

    it "renders both inputs under the same field name so the last wins on submit" do
      occurrences = html.scan(
        %(name="backfill_run[options][dry_run]")
      ).length
      # exactly two inputs share the name: the hidden 0 and the checkbox 1
      expect(occurrences).to eq(2)
    end
  end
end
