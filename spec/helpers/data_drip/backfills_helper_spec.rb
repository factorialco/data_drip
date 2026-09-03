# frozen_string_literal: true

require "spec_helper"

# A backfill with no options, to exercise the em-dash "no configurable fields"
# branch without depending on inline classes from other spec files.
class NoOptionsCatalogBackfill < DataDrip::Backfill
  def scope
    Employee.all
  end

  def process_element(_element); end
end

RSpec.describe DataDrip::BackfillsHelper, type: :helper do
  # A plain class stands in for a backfill loaded before the description DSL
  # existed: it responds to neither .description nor .backfill_options_class.
  let(:legacy_backfill) { Class.new }

  describe "#backfill_description" do
    it "returns the class's description" do
      expect(helper.backfill_description(AddRoleToEmployee)).to include(
        "Assigns the default"
      )
    end

    it "returns nil for a backfill that sets none" do
      expect(helper.backfill_description(NoOptionsCatalogBackfill)).to be_nil
    end

    it "degrades to nil for a class predating the DSL" do
      expect(helper.backfill_description(legacy_backfill)).to be_nil
    end
  end

  describe "#backfill_configurable_fields" do
    it "derives name/type pairs from the options schema" do
      fields = helper.backfill_configurable_fields(AddRoleToEmployee)

      expect(fields).to include({ name: "age", type: :integer })
      expect(fields).to include({ name: "name", type: :string })
    end

    it "returns [] for a class without an options schema" do
      expect(helper.backfill_configurable_fields(legacy_backfill)).to eq([])
    end
  end

  describe "#backfill_configurable_field_tags" do
    it "renders a pill per field" do
      html = helper.backfill_configurable_field_tags(AddRoleToEmployee)

      expect(html).to include(">age</span>")
      expect(html).to include(">integer</span>")
    end

    it "renders an em dash when the backfill takes no options" do
      html = helper.backfill_configurable_field_tags(NoOptionsCatalogBackfill)

      expect(html).to include("—")
    end
  end
end
