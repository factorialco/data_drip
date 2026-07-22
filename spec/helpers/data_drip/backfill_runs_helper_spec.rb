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

  describe "#backfill_option_inputs with a required attribute" do
    let(:backfill_run) do
      DataDrip::BackfillRun.new(
        backfill_class_name: "BackfillRunsHelperSpec::RequiredFieldBackfill",
        options: {}
      )
    end

    let(:html) { helper.backfill_option_inputs(backfill_run) }

    it "marks the required input with the required attribute" do
      expect(html).to match(
        %r{<input[^>]*name="backfill_run\[options\]\[audience\]"[^>]*required="required"}
      )
    end

    it "labels the required option and not the optional one" do
      expect(html.scan("· required").length).to eq(1)
      expect(html).not_to match(
        %r{<input[^>]*name="backfill_run\[options\]\[note\]"[^>]*required}
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

    it "uses a muted fill for stopped runs" do
      expect(helper.progress_bar(50, status: "stopped")).to include("bg-zinc-400")
    end

    it "uses the gradient fill for in-progress runs" do
      expect(helper.progress_bar(20, status: "running")).to include("from-drip-pink")
    end
  end

  describe "#relative_time" do
    it "returns an empty string for nil" do
      expect(helper.relative_time(nil)).to eq("")
    end

    it "renders a past time as '… ago'" do
      html = helper.relative_time(2.hours.ago)

      expect(html).to include("ago")
      expect(html).to include("<time")
    end

    it "renders a future time as 'in …'" do
      html = helper.relative_time(2.hours.from_now)

      expect(html).to include("in ")
    end

    it "localizes the title tooltip to the given timezone" do
      time = Time.utc(2030, 1, 15, 12, 0, 0)

      html = helper.relative_time(time, "America/New_York")

      # 12:00 UTC is 07:00 EST.
      expect(html).to include("07:00")
    end
  end

  describe "#format_duration" do
    it "returns an em dash for nil" do
      expect(helper.format_duration(nil)).to eq("—")
    end

    it "formats sub-minute durations in seconds" do
      expect(helper.format_duration(42.4)).to eq("42 s")
    end

    it "formats sub-hour durations in minutes" do
      expect(helper.format_duration(125)).to eq("2 min")
    end

    it "formats multi-hour durations in hours and minutes" do
      expect(helper.format_duration(3 * 3600 + 25 * 60)).to eq("3 h 25 min")
    end
  end

  describe "#format_datetime_in_user_timezone" do
    it "returns an empty string for nil" do
      expect(helper.format_datetime_in_user_timezone(nil)).to eq("")
    end

    it "formats in UTC by default" do
      time = Time.utc(2030, 3, 4, 9, 30, 0)

      expect(helper.format_datetime_in_user_timezone(time)).to eq("Mar 04, 09:30")
    end

    it "converts to the provided timezone" do
      time = Time.utc(2030, 3, 4, 9, 30, 0)

      # 09:30 UTC is 10:30 in Madrid (CET).
      expect(
        helper.format_datetime_in_user_timezone(time, "Europe/Madrid")
      ).to eq("Mar 04, 10:30")
    end

    it "falls back to UTC for a blank timezone" do
      time = Time.utc(2030, 3, 4, 9, 30, 0)

      expect(
        helper.format_datetime_in_user_timezone(time, "")
      ).to eq("Mar 04, 09:30")
    end
  end

  describe "#backfiller_initials" do
    it "takes the first two initials, uppercased" do
      expect(helper.backfiller_initials("ada lovelace")).to eq("AL")
    end

    it "handles single-word names" do
      expect(helper.backfiller_initials("Cher")).to eq("C")
    end

    it "handles nil safely" do
      expect(helper.backfiller_initials(nil)).to eq("")
    end
  end

  describe "button class helpers" do
    it "exposes each button style" do
      expect(helper.primary_button_classes).to include("bg-drip-700")
      expect(helper.danger_button_classes).to include("bg-red-50")
      expect(helper.ghost_button_classes).to include("hover:bg-zinc-950/5")
    end

    it "adjusts secondary button padding by size" do
      expect(helper.secondary_button_classes).to include("px-3 py-1.5 text-sm")
      expect(helper.secondary_button_classes(size: :small)).to include(
        "px-2.5 py-1 text-xs"
      )
    end
  end

  describe "#backfill_option_inputs with varied attribute types" do
    let(:backfill_run) do
      DataDrip::BackfillRun.new(
        backfill_class_name: "BackfillRunsHelperSpec::TypedBackfill",
        options: {}
      )
    end

    let(:html) { helper.backfill_option_inputs(backfill_run) }

    it "renders a number input for integer attributes" do
      expect(html).to match(
        %r{<input[^>]*type="number"[^>]*name="backfill_run\[options\]\[quantity\]"[^>]*step="1"}
      )
    end

    it "renders a decimal-stepped number input for float attributes" do
      expect(html).to match(
        %r{<input[^>]*type="number"[^>]*name="backfill_run\[options\]\[ratio\]"[^>]*step="0.01"}
      )
    end

    it "renders a date input for date attributes" do
      expect(html).to match(
        %r{<input[^>]*type="date"[^>]*name="backfill_run\[options\]\[on_date\]"}
      )
    end

    it "renders a time input for time attributes" do
      expect(html).to match(
        %r{<input[^>]*type="time"[^>]*name="backfill_run\[options\]\[at_time\]"}
      )
    end

    it "renders a datetime input for datetime attributes" do
      expect(html).to match(
        %r{<input[^>]*type="datetime-local"[^>]*name="backfill_run\[options\]\[at\]"}
      )
    end
  end

  describe "#backfill_option_inputs with an unrecognized attribute type" do
    let(:backfill_run) do
      DataDrip::BackfillRun.new(
        backfill_class_name: "BackfillRunsHelperSpec::CustomTypeBackfill",
        options: {}
      )
    end

    it "falls back to a textarea" do
      html = helper.backfill_option_inputs(backfill_run)

      expect(html).to match(
        %r{<textarea[^>]*name="backfill_run\[options\]\[payload\]"}
      )
    end
  end

  describe "#backfill_option_inputs with no options" do
    it "returns an empty string when the class has no options" do
      backfill_run =
        DataDrip::BackfillRun.new(
          backfill_class_name: "BackfillRunsHelperSpec::NoOptionsBackfill",
          options: {}
        )

      expect(helper.backfill_option_inputs(backfill_run)).to eq("")
    end

    it "returns an empty string for an unresolvable class" do
      backfill_run =
        DataDrip::BackfillRun.new(
          backfill_class_name: "NopeDoesNotExist",
          options: {}
        )

      expect(helper.backfill_option_inputs(backfill_run)).to eq("")
    end
  end
end

module BackfillRunsHelperSpec
  class RequiredFieldBackfill < DataDrip::Backfill
    attribute :audience, :string, required: true
    attribute :note, :string

    def scope
      Employee.all
    end

    def process_element(_element); end
  end

  class TieredBackfill < DataDrip::Backfill
    attribute :tiers, :enum, values: %w[starter growth]

    def scope
      Employee.all
    end

    def process_element(_element); end
  end

  class TypedBackfill < DataDrip::Backfill
    attribute :quantity, :integer
    attribute :ratio, :float
    attribute :on_date, :date
    attribute :at_time, :time
    attribute :at, :datetime

    def scope
      Employee.all
    end

    def process_element(_element); end
  end

  class NoOptionsBackfill < DataDrip::Backfill
    def scope
      Employee.all
    end

    def process_element(_element); end
  end

  # An attribute typed with something outside the recognized set exercises the
  # textarea fallback in build_standard_input.
  class CustomAttributeType < ActiveModel::Type::Value
  end

  class CustomTypeBackfill < DataDrip::Backfill
    attribute :payload, CustomAttributeType.new

    def scope
      Employee.all
    end

    def process_element(_element); end
  end
end
