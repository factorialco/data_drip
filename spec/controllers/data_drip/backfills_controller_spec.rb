require "rails_helper"

RSpec.describe DataDrip::BackfillsController, type: :controller do
  routes { DataDrip::Engine.routes }

  let(:valid_backfill_class) do
    Class.new(DataDrip::Backfill) do
      def self.name = "TestBackfill"
      def scope = double(count: 1)
      def process_element(e); end
    end
  end

  before do
    stub_const("DataDrip::TestBackfill", valid_backfill_class)
    allow(DataDrip).to receive(:all).and_return([valid_backfill_class])
  end

  it "enqueues job if valid and has records" do
    expect do
      post :run, params: { backfill: "TestBackfill" }
    end.to have_enqueued_job(DataDrip::Dripper)
    expect(flash[:notice]).to match(/has been enqueued/)
  end

  it "shows alert if class not found" do
    allow(DataDrip).to receive(:all).and_return([])
    post :run, params: { backfill: "MissingBackfill" }
    expect(flash[:alert]).to match(/not found/)
  end

  it "shows alert if scope not implemented" do
    klass = Class.new(DataDrip::Backfill) do
      def self.name = "NoScopeBackfill"
      def process_element(e); end
    end
    stub_const("DataDrip::NoScopeBackfill", klass)
    allow(DataDrip).to receive(:all).and_return([klass])
    post :run, params: { backfill: "NoScopeBackfill" }
    expect(flash[:alert]).to match(/must implement #scope/)
  end

  it "shows alert if process_element not implemented" do
    klass = Class.new(DataDrip::Backfill) do
      def self.name = "NoElementBackfill"
      def scope = double(count: 1)
    end
    stub_const("DataDrip::NoElementBackfill", klass)
    allow(DataDrip).to receive(:all).and_return([klass])
    post :run, params: { backfill: "NoElementBackfill" }
    expect(flash[:alert]).to match(/must implement #process_element/)
  end

  it "shows alert if process_batch has wrong arity" do
    klass = Class.new(DataDrip::Backfill) do
      def self.name = "BadBatchBackfill"
      def scope = double(count: 1)
      def process_element(e); end
      def process_batch; end # wrong arity
    end
    stub_const("DataDrip::BadBatchBackfill", klass)
    allow(DataDrip).to receive(:all).and_return([klass])
    post :run, params: { backfill: "BadBatchBackfill" }
    expect(flash[:alert]).to match(/should accept exactly one argument/)
  end

  it "shows notice if no records to process" do
    klass = Class.new(DataDrip::Backfill) do
      def self.name = "EmptyBackfill"
      def scope = double(count: 0)
      def process_element(e); end
    end
    stub_const("DataDrip::EmptyBackfill", klass)
    allow(DataDrip).to receive(:all).and_return([klass])
    post :run, params: { backfill: "EmptyBackfill" }
    expect(flash[:notice]).to match(/No records to process/)
  end
end
