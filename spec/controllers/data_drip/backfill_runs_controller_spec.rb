require "spec_helper"

RSpec.describe DataDrip::BackfillRunsController, type: :controller do
  describe "POST #create" do
    let(:valid_attributes) do
      {
        backfill_class_name: "SomeBackfillClass",
        batch_size: 100,
        start_at: Time.current + 1.hour
      }
    end

    let(:invalid_attributes) do
      {
        backfill_class_name: nil,
        batch_size: nil,
        start_at: nil
      }
    end

    it "creates a new BackfillRun and redirects on success" do
      expect do
        post :create, params: { backfill_run: valid_attributes }
      end.to change(DataDrip::BackfillRun, :count).by(1)
      expect(response).to redirect_to(backfill_runs_path)
      expect(flash[:notice]).to match(/Backfill job for/)
    end

    it "renders new template on failure" do
      expect do
        post :create, params: { backfill_run: invalid_attributes }
      end.not_to change(DataDrip::BackfillRun, :count)
      expect(response).to render_template(:new)
      expect(flash[:alert]).to eq("Error creating backfill run")
    end
  end
end
