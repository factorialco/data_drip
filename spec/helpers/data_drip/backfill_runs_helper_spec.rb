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

  describe "#backfill_option_inputs with an enum attribute" do
    let(:backfill_run) do
      DataDrip::BackfillRun.new(
        backfill_class_name: "BackfillRunsHelperSpec::TieredBackfill",
        options: {}
      )
    end

    let(:html) { helper.backfill_option_inputs(backfill_run) }

    it "renders a hidden field with all values preselected, wired to the enum-select controller" do
      expect(html).to include(%(data-controller="enum-select"))
      expect(html).to match(
        %r{<input[^>]*type="hidden"[^>]*name="backfill_run\[options\]\[tiers\]"[^>]*value="starter,growth"}
      )
    end

    it "renders one checkbox per enum value plus the select-all toggle" do
      expect(html).to include(%(id="enum_tiers_starter"))
      expect(html).to include(%(id="enum_tiers_growth"))
      expect(html).to include(%(id="enum_tiers_select_all"))
    end

    it "keeps only checked values in the hidden field when options are present" do
      backfill_run.options = { "tiers" => "growth" }

      expect(html).to match(
        %r{<input[^>]*type="hidden"[^>]*name="backfill_run\[options\]\[tiers\]"[^>]*value="growth"}
      )
    end
  end

  describe "#status_tag" do
    it "renders a badge without inline styles" do
      html = helper.status_tag("running")

      expect(html).to include("Running")
      expect(html).to include("animate-pulse")
      expect(html).not_to include("style=")
    end

    it "falls back to the pending style for unknown statuses" do
      expect(helper.status_tag("whatever")).to include("Whatever")
    end
  end

  describe "#progress_bar" do
    it "exposes the percentage as a CSS variable and aria value" do
      html = helper.progress_bar(64, status: "running")

      expect(html).to include(%(--progress: 64%))
      expect(html).to include(%(aria-valuenow="64"))
    end

    it "uses semantic fills for terminal statuses" do
      expect(helper.progress_bar(38, status: "failed")).to include("bg-red-500")
      expect(helper.progress_bar(100, status: "completed")).to include("bg-green-500")
    end
  end
end

module BackfillRunsHelperSpec
  class TieredBackfill < DataDrip::Backfill
    attribute :tiers, :enum, values: %w[starter growth]

    def scope
      Employee.all
    end

    def process_element(_element); end
  end
end
