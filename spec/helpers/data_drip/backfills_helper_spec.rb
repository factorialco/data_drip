# frozen_string_literal: true

require "spec_helper"

# A backfill that uses the description + attribute DSL.
class DescribedBackfill < DataDrip::Backfill
  description "Adds a thing to records"
  attribute :company_ids, :string

  def scope
    Employee.all
  end

  def process_element(_element); end
end

RSpec.describe DataDrip::BackfillsHelper, type: :helper do
  # Simulates a backfill class that predates the description/custom_fields DSL:
  # it responds to neither method (mirrors a stale-loaded base class in a host
  # app). The catalog must degrade gracefully instead of raising.
  let(:legacy_class) do
    Class.new do
      def self.name
        "LegacyBackfill"
      end
    end
  end

  describe "#backfill_description" do
    it "returns the description when the class defines one" do
      expect(helper.backfill_description(DescribedBackfill)).to eq(
        "Adds a thing to records"
      )
    end

    it "returns nil when the class does not respond to description" do
      expect(helper.backfill_description(legacy_class)).to be_nil
    end
  end

  describe "#backfill_search_terms" do
    it "includes the name, description and field names, lowercased" do
      terms = helper.backfill_search_terms(DescribedBackfill)

      expect(terms).to include("describedbackfill")
      expect(terms).to include("adds a thing to records")
      expect(terms).to include("company_ids")
    end

    it "does not raise for a class lacking description/custom_fields" do
      expect(helper.backfill_search_terms(legacy_class)).to eq("legacybackfill")
    end
  end

  describe "#custom_field_tags" do
    it "renders a chip per declared field" do
      expect(helper.custom_field_tags(DescribedBackfill)).to include(
        "company_ids: string"
      )
    end

    it "renders a dash for a class without custom_fields" do
      expect(helper.custom_field_tags(legacy_class)).to include("—")
    end
  end

  describe "#custom_field_tags fallback for a legacy base class" do
    # Mirrors a host app running a DataDrip::Backfill loaded before the
    # custom_fields DSL existed: the class does not respond to .custom_fields,
    # but still exposes its options via backfill_options_class.attribute_types.
    let(:legacy_with_fields) do
      Class.new do
        def self.name
          "LegacyWithFields"
        end

        def self.backfill_options_class
          @backfill_options_class ||=
            Class.new do
              include ActiveModel::API
              include ActiveModel::Attributes
              attribute :upload_process_ids, :string
              attribute :dry_run, :boolean, default: true
            end
        end
      end
    end

    it "renders a chip per attribute without relying on custom_fields" do
      expect(legacy_with_fields).not_to respond_to(:custom_fields)

      html = helper.custom_field_tags(legacy_with_fields)
      expect(html).to include("upload_process_ids: string")
      expect(html).to include("dry_run: boolean")
    end

    it "includes the field names in the search terms too" do
      expect(helper.backfill_search_terms(legacy_with_fields)).to include(
        "upload_process_ids"
      )
    end
  end
end
