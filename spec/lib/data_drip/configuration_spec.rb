# frozen_string_literal: true

require "spec_helper"

RSpec.describe "DataDrip Configuration" do
  describe "base_job_class" do
    it "defaults to ActiveJob::Base" do
      expect(DataDrip.base_job_class).to eq("ActiveJob::Base")
    end

    it "can be configured" do
      original_value = DataDrip.base_job_class
      begin
        DataDrip.base_job_class = "::ApplicationJob"
        expect(DataDrip.base_job_class).to eq("::ApplicationJob")
      ensure
        DataDrip.base_job_class = original_value
      end
    end

    it "is used by Dripper class" do
      expect(DataDrip::Dripper.superclass).to eq(ActiveJob::Base)
    end

    it "is used by DripperChild class" do
      expect(DataDrip::DripperChild.superclass).to eq(ActiveJob::Base)
    end

    context "when set to a custom job class" do
      let(:custom_job_class) do
        Class.new(ActiveJob::Base) do
          def self.name
            "CustomJobClass"
          end
        end
      end

      before do
        @original_value = DataDrip.base_job_class
        stub_const("CustomJobClass", custom_job_class)
        DataDrip.base_job_class = "::CustomJobClass"
      end

      after { DataDrip.base_job_class = @original_value }

      it "uses the custom job class for Dripper" do
        # Create a new class to pick up the new setting
        new_dripper_class = Class.new(DataDrip.base_job_class.safe_constantize)
        expect(new_dripper_class.superclass).to eq(custom_job_class)
      end
    end
  end

  describe "queue_name" do
    it "defaults to :data_drip when DATA_DRIP_QUEUE is not set" do
      original_value = DataDrip.queue_name
      original_env = ENV["DATA_DRIP_QUEUE"]
      begin
        ENV.delete("DATA_DRIP_QUEUE")
        DataDrip.queue_name = (ENV["DATA_DRIP_QUEUE"].presence || "data_drip").to_sym
        expect(DataDrip.queue_name).to eq(:data_drip)
      ensure
        ENV["DATA_DRIP_QUEUE"] = original_env
        DataDrip.queue_name = original_value
      end
    end

    it "can be configured" do
      original_value = DataDrip.queue_name
      begin
        DataDrip.queue_name = :custom_queue
        expect(DataDrip.queue_name).to eq(:custom_queue)
      ensure
        DataDrip.queue_name = original_value
      end
    end

    it "is resolved dynamically at enqueue time for Dripper" do
      original_value = DataDrip.queue_name
      begin
        DataDrip.queue_name = :within_24_hours
        expect(DataDrip::Dripper.new.queue_name).to eq("within_24_hours")

        DataDrip.queue_name = :low_priority
        expect(DataDrip::Dripper.new.queue_name).to eq("low_priority")
      ensure
        DataDrip.queue_name = original_value
      end
    end
  end

  describe "child_queue_name" do
    it "defaults to :data_drip_child when DATA_DRIP_CHILD_QUEUE is not set" do
      original_value = DataDrip.child_queue_name
      original_env = ENV["DATA_DRIP_CHILD_QUEUE"]
      begin
        ENV.delete("DATA_DRIP_CHILD_QUEUE")
        DataDrip.child_queue_name = (ENV["DATA_DRIP_CHILD_QUEUE"].presence || "data_drip_child").to_sym
        expect(DataDrip.child_queue_name).to eq(:data_drip_child)
      ensure
        ENV["DATA_DRIP_CHILD_QUEUE"] = original_env
        DataDrip.child_queue_name = original_value
      end
    end

    it "can be configured" do
      original_value = DataDrip.child_queue_name
      begin
        DataDrip.child_queue_name = :custom_child_queue
        expect(DataDrip.child_queue_name).to eq(:custom_child_queue)
      ensure
        DataDrip.child_queue_name = original_value
      end
    end

    it "is resolved dynamically at enqueue time for DripperChild" do
      original_value = DataDrip.child_queue_name
      begin
        DataDrip.child_queue_name = :within_24_hours
        expect(DataDrip::DripperChild.new.queue_name).to eq("within_24_hours")

        DataDrip.child_queue_name = :low_priority
        expect(DataDrip::DripperChild.new.queue_name).to eq("low_priority")
      ensure
        DataDrip.child_queue_name = original_value
      end
    end
  end

  describe "base_controller_class" do
    it "defaults to ApplicationController" do
      expect(DataDrip.base_controller_class).to eq("::ApplicationController")
    end

    it "can be configured" do
      original_value = DataDrip.base_controller_class
      begin
        DataDrip.base_controller_class = "::ActionController::Base"
        expect(DataDrip.base_controller_class).to eq("::ActionController::Base")
      ensure
        DataDrip.base_controller_class = original_value
      end
    end
  end
end
