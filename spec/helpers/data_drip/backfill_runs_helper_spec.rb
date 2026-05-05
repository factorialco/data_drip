# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::BackfillRunsHelper, type: :helper do
  describe "#backfill_option_inputs" do
    it "renders boolean options with an explicit unchecked value" do
      backfill_run =
        DataDrip::BackfillRun.new(
          backfill_class_name: "BooleanDefaultBackfill",
          options: {}
        )

      html = helper.backfill_option_inputs(backfill_run)
      document = Nokogiri::HTML.fragment(html)
      inputs = document.css('input[name="backfill_run[options][dry_run]"]')

      expect(inputs.map { |input| input["type"] }).to eq(%w[hidden checkbox])
      expect(inputs.map { |input| input["value"] }).to eq(%w[0 1])
      expect(inputs.last["checked"]).to eq("checked")
      expect(inputs.map { |input| input["id"] }.compact).to eq(
        [ "backfill_run_options_dry_run" ]
      )
    end

    it "renders stored false boolean options as unchecked" do
      backfill_run =
        DataDrip::BackfillRun.new(
          backfill_class_name: "BooleanDefaultBackfill",
          options: {
            "dry_run" => "0"
          }
        )

      html = helper.backfill_option_inputs(backfill_run)
      document = Nokogiri::HTML.fragment(html)
      checkbox =
        document.css(
          'input[type="checkbox"][name="backfill_run[options][dry_run]"]'
        ).first

      expect(checkbox["checked"]).to be_nil
    end
  end
end
