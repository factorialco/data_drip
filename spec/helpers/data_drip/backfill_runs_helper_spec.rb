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
    end
  end
end
