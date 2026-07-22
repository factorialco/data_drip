# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::Types::Enum do
  describe "#type" do
    it "identifies itself as :enum" do
      expect(described_class.new(values: %w[a b]).type).to eq(:enum)
    end
  end

  describe "#available_values" do
    it "returns a static list as-is" do
      expect(described_class.new(values: %w[a b]).available_values).to eq(%w[a b])
    end

    it "resolves a callable lazily" do
      counter = 0
      type = described_class.new(values: -> { counter += 1; %w[x y] })

      expect(type.available_values).to eq(%w[x y])
      expect(type.available_values).to eq(%w[x y])
      # Called each time, not memoized.
      expect(counter).to eq(2)
    end
  end

  describe "casting" do
    it "casts values to strings, like its String parent" do
      type = described_class.new(values: %w[a b])

      expect(type.cast(:a)).to eq("a")
      expect(type.cast(nil)).to be_nil
    end
  end
end
