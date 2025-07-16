require "spec_helper"

RSpec.describe DataDrip::BackfillRunsController, type: :controller do
  routes { DataDrip::Engine.routes }
  describe "POST #create" do
    let(:valid_attributes) do
      {
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: Time.current + 1.hour
      }
    end

    let(:invalid_attributes) do
      { backfill_class_name: nil, batch_size: nil, start_at: nil }
    end

    before { Employee.create!(name: "Pepe", role: nil) }

    render_views

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

      expect(response.body).to include("Error")
      expect(flash[:alert]).to eq("Error creating backfill run")
    end
  end

  describe "POST #stop" do
    let!(:backfill_run) { DataDrip::BackfillRun.create!(backfill_class_name: "AddRoleToEmployee", batch_size: 100, start_at: Time.current + 1.hour) }

    context "when the backfill run is running" do
      before do
        backfill_run.update(status: "running")
      end

      it "stops the backfill run and redirects" do
        post :stop, params: { id: backfill_run.id }

        expect(backfill_run.reload.status).to eq("stopped")
        expect(response).to redirect_to(backfill_run_path(backfill_run))
        expect(flash[:notice]).to eq("Backfill run has been stopped.")
      end
    end

    context "when the backfill run is not running" do
      before do
        backfill_run.update(status: "completed")
      end

      it "does not change the status and redirects" do
        post :stop, params: { id: backfill_run.id }

        expect(backfill_run.reload.status).to eq("completed")
        expect(response).to redirect_to(backfill_run_path(backfill_run))
        expect(flash[:alert]).to eq("Backfill run is not currently running.")
      end
    end
  end

  describe "DELETE #destroy" do
    let!(:backfill_run) { DataDrip::BackfillRun.create!(backfill_class_name: "AddRoleToEmployee", batch_size: 100, start_at: Time.current + 1.hour) }

    context "when the backfill run is enqueued" do
      before do
        backfill_run.update(status: "enqueued")
      end

      it "deletes the backfill run and redirects" do
        delete :destroy, params: { id: backfill_run.id }

        expect(DataDrip::BackfillRun.exists?(backfill_run.id)).to be_falsey
        expect(response).to redirect_to(backfill_runs_path)
        expect(flash[:notice]).to eq("Backfill run has been deleted.")
      end
    end

    context "when the backfill run is not enqueued" do
      before do
        backfill_run.update(status: "running")
      end

      it "does not delete the backfill run and redirects with an alert" do
        delete :destroy, params: { id: backfill_run.id }

        expect(DataDrip::BackfillRun.exists?(backfill_run.id)).to be_truthy
        expect(response).to redirect_to(backfill_runs_path)
        expect(flash[:alert]).to eq("Backfill run cannot be deleted as it is not in an enqueued state.")
      end
    end
  end
end
