# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::Paginatable do
  # A minimal host that mixes in the concern and exposes params, like a controller.
  let(:harness) do
    Class.new do
      include DataDrip::Paginatable
      attr_accessor :params

      def initialize(params)
        @params = params
      end
    end
  end

  before do
    Employee.delete_all
    5.times { |i| Employee.create!(name: "E#{i}") }
  end

  def paginate(params, per_page: 2)
    harness.new(params).send(:paginate_collection, Employee.all, per_page: per_page)
  end

  it "defaults to the first page" do
    result = paginate({})

    expect(result[:current_page]).to eq(1)
    expect(result[:collection].size).to eq(2)
  end

  it "clamps a page past the end to the last real page" do
    result = paginate({ page: 999 })

    expect(result[:total_pages]).to eq(3)
    expect(result[:current_page]).to eq(3)
    expect(result[:collection].size).to eq(1) # 5 records, 2 per page -> last page has 1
  end

  it "clamps a page below 1 to the first page" do
    result = paginate({ page: -4 })

    expect(result[:current_page]).to eq(1)
  end

  # The backfills catalog paginates an in-memory Array rather than an
  # ActiveRecord relation.
  describe "with a plain array" do
    let(:items) { %w[a b c d e] }

    def paginate_array(params, per_page: 2)
      harness.new(params).send(:paginate_collection, items, per_page: per_page)
    end

    it "slices the array for the requested page" do
      result = paginate_array({ page: 2 })

      expect(result[:collection]).to eq(%w[c d])
      expect(result[:total_count]).to eq(5)
      expect(result[:total_pages]).to eq(3)
    end

    it "clamps a page past the end to the last page" do
      result = paginate_array({ page: 99 })

      expect(result[:current_page]).to eq(3)
      expect(result[:collection]).to eq(%w[e])
    end

    it "returns an empty slice for an empty array" do
      result = harness.new({}).send(:paginate_collection, [], per_page: 2)

      expect(result[:collection]).to eq([])
      expect(result[:total_pages]).to eq(0)
    end
  end
end
