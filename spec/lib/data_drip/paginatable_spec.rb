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
end
