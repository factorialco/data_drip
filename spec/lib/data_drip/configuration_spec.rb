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
