# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::BackfillRunsController, type: :controller do
  routes { DataDrip::Engine.routes }

  let!(:backfiller) { User.create!(name: "Suzie") }

  before do
    Employee.create!(name: "Pepe", role: nil, age: 25)
    Employee.create!(name: "John", role: nil, age: 30)
  end

  describe "POST #create" do
    let(:valid_attributes) do
      {
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now
      }
    end

    let(:invalid_attributes) do
      { backfill_class_name: nil, batch_size: nil, start_at: nil }
    end

    render_views

    it "creates a new BackfillRun and redirects on success" do
      expect do
        post :create, params: { backfill_run: valid_attributes }
      end.to change(DataDrip::BackfillRun, :count).by(1)

      backfill_run = DataDrip::BackfillRun.last!

      expect(backfill_run.backfiller).to eq(backfiller)

      expect(response).to redirect_to(backfill_runs_path(tab: "my_runs"))
      expect(flash[:notice]).to match(/Backfill job for/)
    end

    it "renders new template on failure" do
      expect do
        post :create, params: { backfill_run: invalid_attributes }
      end.not_to change(DataDrip::BackfillRun, :count)

      expect(response.body).to include("Error")
    end

    it "renders new template when backfill class name is invalid" do
      invalid_class_attributes =
        valid_attributes.merge(backfill_class_name: "NonExistentClass")

      expect do
        post :create, params: { backfill_run: invalid_class_attributes }
      end.not_to change(DataDrip::BackfillRun, :count)

      expect(response.body).to include("Error")
    end

    context "with timezone conversion" do
      let(:timezone_attributes) do
        {
          backfill_class_name: "AddRoleToEmployee",
          batch_size: 100,
          start_at: "2024-01-15T10:30:00",
          user_timezone: "America/New_York"
        }
      end

      it "converts timezone correctly" do
        post :create,
             params: {
               backfill_run: timezone_attributes,
               user_timezone: "America/New_York"
             }
        expect(response).to redirect_to(backfill_runs_path(tab: "my_runs"))
        expect(flash[:notice]).to include(
          "Will run at 15-01-2024, 10:30:00 EST"
        )
      end

      it "uses UTC when no timezone is provided" do
        post :create,
             params: {
               backfill_run: timezone_attributes,
               user_timezone: nil
             }
        expect(response).to redirect_to(backfill_runs_path(tab: "my_runs"))
        expect(flash[:notice]).to include("Will run at")
      end
    end
  end

  describe "POST #stop" do
    let!(:backfill_run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller
      )
    end

    context "when the backfill run is running" do
      before { backfill_run.update!(status: "running") }

      it "stops the backfill run and redirects" do
        post :stop, params: { id: backfill_run.id }

        expect(backfill_run.reload.status).to eq("stopped")
        expect(response).to redirect_to(backfill_run_path(backfill_run))
        expect(flash[:notice]).to eq("Backfill run has been stopped.")
      end
    end

    context "when the backfill run is not running" do
      before { backfill_run.update!(status: "completed") }

      it "does not change the status and redirects" do
        post :stop, params: { id: backfill_run.id }

        expect(backfill_run.reload.status).to eq("completed")
        expect(response).to redirect_to(backfill_run_path(backfill_run))
        expect(flash[:alert]).to eq("Backfill run is not currently running.")
      end
    end
  end

  describe "DELETE #destroy" do
    let!(:backfill_run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller
      )
    end

    context "when the backfill run is enqueued" do
      before { backfill_run.update!(status: "enqueued") }

      it "deletes the backfill run and redirects" do
        delete :destroy, params: { id: backfill_run.id }

        expect(DataDrip::BackfillRun.exists?(backfill_run.id)).to be_falsey
        expect(response).to redirect_to(backfill_runs_path(tab: "my_runs"))
        expect(flash[:notice]).to eq("Backfill run has been deleted.")
      end
    end

    context "when the backfill run is not enqueued" do
      before { backfill_run.update!(status: "running") }

      it "does not delete the backfill run and redirects with an alert" do
        delete :destroy, params: { id: backfill_run.id }

        expect(DataDrip::BackfillRun.exists?(backfill_run.id)).to be_truthy
        expect(response).to redirect_to(backfill_runs_path(tab: "my_runs"))
        expect(flash[:alert]).to eq(
          "Backfill run cannot be deleted as it is not in an enqueued state."
        )
      end
    end

    context "when backfill run is not found" do
      it "raises an error" do
        expect { delete :destroy, params: { id: 999_999 } }.to raise_error(
          ActiveRecord::RecordNotFound
        )
      end
    end
  end

  describe "#backfill_class_names" do
    it "returns sorted and unique backfill class names" do
      expect(controller.send(:backfill_class_names)).to include(
        "Select a backfill class"
      )
      expect(controller.send(:backfill_class_names)).to include(
        "AddRoleToEmployee"
      )
    end
  end

  describe "POST #create with options" do
    let(:base_attributes) do
      {
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now
      }
    end

    context "with valid options" do
      it "creates BackfillRun with options stored" do
        options = { age: "25" }
        attributes = base_attributes.merge(options: options)

        expect do
          post :create, params: { backfill_run: attributes }
        end.to change(DataDrip::BackfillRun, :count).by(1)

        backfill_run = DataDrip::BackfillRun.last!
        expect(backfill_run.options).to eq({ "age" => "25" })
        expect(response).to redirect_to(backfill_runs_path(tab: "my_runs"))
      end
    end

    context "with empty options" do
      it "creates BackfillRun with empty options hash" do
        attributes = base_attributes.merge(options: {})

        expect do
          post :create, params: { backfill_run: attributes }
        end.to change(DataDrip::BackfillRun, :count).by(1)

        backfill_run = DataDrip::BackfillRun.last!
        expect(backfill_run.options).to eq({})
        expect(response).to redirect_to(backfill_runs_path(tab: "my_runs"))
      end
    end

    context "with invalid option keys" do
      it "rejects BackfillRun with unknown attributes" do
        options = { invalid_key: "some_value", another_invalid: "123" }
        attributes = base_attributes.merge(options: options)

        expect do
          post :create, params: { backfill_run: attributes }
        end.not_to change(DataDrip::BackfillRun, :count)

        expect(response).to have_http_status(:ok)
      end
    end

    context "options parameter permitting" do
      it "allows any keys in options hash" do
        options = { age: "25" }
        attributes = base_attributes.merge(options: options)

        expect do
          post :create, params: { backfill_run: attributes }
        end.to change(DataDrip::BackfillRun, :count).by(1)

        backfill_run = DataDrip::BackfillRun.last!
        expect(backfill_run.options).to eq({ "age" => "25" })
      end
    end
  end
end
