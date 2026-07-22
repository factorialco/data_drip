# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::BackfillRunsController, type: :controller do
  routes { DataDrip::Engine.routes }

  let!(:backfiller) { User.create!(name: "Suzie") }

  before do
    Employee.create!(name: "Pepe", role: nil, age: 25)
    Employee.create!(name: "John", role: nil, age: 30)
  end

  describe "GET #new" do
    render_views

    it "renders the class picker with all backfill classes" do
      get :new

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("backfill_class_listbox")
      expect(response.body).to include('data-value="AddRoleToEmployee"')
    end

    it "surfaces the current user's recently run classes in a Recent section" do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller,
        options: {
          age: 25
        }
      )

      get :new

      expect(response.body).to include(">Recent<")
      expect(response.body).to include('data-recent="true"')
    end

    it "omits the Recent section when the user has no runs" do
      get :new

      expect(response.body).not_to include(">Recent<")
    end
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

      expect(response).to have_http_status(422)
      expect(response.body).to include("This run couldn")
    end

    it "renders new template when backfill class name is invalid" do
      invalid_class_attributes =
        valid_attributes.merge(backfill_class_name: "NonExistentClass")

      expect do
        post :create, params: { backfill_run: invalid_class_attributes }
      end.not_to change(DataDrip::BackfillRun, :count)

      expect(response).to have_http_status(422)
      expect(response.body).to include("This run couldn")
    end

    context "with timezone conversion" do
      let(:timezone_attributes) do
        {
          backfill_class_name: "AddRoleToEmployee",
          batch_size: 100,
          start_at: "2030-01-15T10:30:00",
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
          "Will run at 15-01-2030, 10:30:00 EST"
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

  describe "POST #create without start_at" do
    it "defaults to running immediately" do
      expect do
        post :create,
             params: {
               backfill_run: {
                 backfill_class_name: "AddRoleToEmployee",
                 batch_size: 100,
                 start_at: ""
               }
             }
      end.to change(DataDrip::BackfillRun, :count).by(1)

      backfill_run = DataDrip::BackfillRun.last!
      expect(backfill_run.start_at).to be_within(1.minute).of(Time.current)
      expect(flash[:notice]).to include("will start shortly")
    end
  end

  describe "POST #retry_failed_batches" do
    let!(:backfill_run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller
      )
    end

    context "with failed batches" do
      let!(:failed_batch) do
        DataDrip::BackfillRunBatch.create!(
          backfill_run: backfill_run,
          status: :failed,
          error_message: "boom",
          batch_size: 100,
          start_id: 1,
          finish_id: 100
        )
      end

      let!(:completed_batch) do
        DataDrip::BackfillRunBatch.create!(
          backfill_run: backfill_run,
          status: :completed,
          batch_size: 100,
          start_id: 101,
          finish_id: 200
        )
      end

      before { backfill_run.update!(status: "stopped") }

      it "re-enqueues only the failed batches and resumes the run" do
        expect do
          post :retry_failed_batches, params: { id: backfill_run.id }
        end.to have_enqueued_job(DataDrip::DripperChild).exactly(:once)

        expect(failed_batch.reload.status).to eq("enqueued")
        expect(failed_batch.error_message).to be_nil
        expect(completed_batch.reload.status).to eq("completed")
        expect(backfill_run.reload.status).to eq("running")
        expect(response).to redirect_to(backfill_run_path(backfill_run))
        expect(flash[:notice]).to eq("Re-enqueued 1 failed batch.")
      end
    end

    context "without failed batches" do
      it "redirects with an alert" do
        post :retry_failed_batches, params: { id: backfill_run.id }

        expect(response).to redirect_to(backfill_run_path(backfill_run))
        expect(flash[:alert]).to eq("This run has no failed batches to retry.")
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

    context "when the backfill run is running" do
      before { backfill_run.update!(status: "running") }

      it "does not delete the backfill run and redirects with an alert" do
        delete :destroy, params: { id: backfill_run.id }

        expect(DataDrip::BackfillRun.exists?(backfill_run.id)).to be_truthy
        expect(response).to redirect_to(backfill_runs_path(tab: "my_runs"))
        expect(flash[:alert]).to eq(
          "Backfill run cannot be deleted while it is pending or running."
        )
      end
    end

    context "when the backfill run is in a terminal state" do
      before { backfill_run.update!(status: "completed") }

      it "deletes the backfill run so finished runs can be cleaned up" do
        delete :destroy, params: { id: backfill_run.id }

        expect(DataDrip::BackfillRun.exists?(backfill_run.id)).to be_falsey
        expect(flash[:notice]).to eq("Backfill run has been deleted.")
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
      names = controller.send(:backfill_class_names)

      expect(names).to include("AddRoleToEmployee")
      expect(names).to eq(names.uniq.sort)
    end
  end

  describe "GET #index" do
    render_views

    let(:other_user) { User.create!(name: "Otto") }

    let!(:my_run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller,
        options: { age: 25 }
      )
    end

    let!(:other_run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddBirthdayToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: other_user,
        options: {}
      )
    end

    it "defaults to the current user's runs" do
      get :index

      expect(response).to have_http_status(:ok)
      # My runs tab is active and only shows the current user's run.
      expect(response.body).to include("AddRoleToEmployee")
      expect(response.body).not_to include("AddBirthdayToEmployee")
    end

    it "shows every run on the all-runs tab" do
      get :index, params: { tab: "all" }

      expect(response.body).to include("AddRoleToEmployee")
      expect(response.body).to include("AddBirthdayToEmployee")
    end

    it "renders the summary stats" do
      get :index, params: { tab: "all" }

      # Two runs, both enqueued via the after_commit callback.
      expect(response.body).to include("Enqueued")
      expect(response.body).to include("Running")
    end

    it "filters by a free-text class-name query" do
      get :index, params: { tab: "all", q: "AddBirthday" }

      expect(response.body).to include("AddBirthdayToEmployee")
      expect(response.body).not_to include("AddRoleToEmployee")
    end

    it "shows an empty state when the query matches nothing" do
      get :index, params: { tab: "all", q: "Nonexistent" }

      expect(response.body).to include("No runs match your filters.")
    end

    it "filters by status" do
      my_run.update_column(:status, DataDrip::BackfillRun.statuses[:running])

      get :index, params: { tab: "all", status: "running" }

      expect(response.body).to include("AddRoleToEmployee")
      expect(response.body).not_to include("AddBirthdayToEmployee")
    end

    it "ignores an unknown status filter" do
      get :index, params: { tab: "all", status: "bogus" }

      expect(response.body).to include("AddRoleToEmployee")
      expect(response.body).to include("AddBirthdayToEmployee")
    end
  end

  describe "GET #show" do
    render_views

    let!(:backfill_run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller,
        options: { age: 25 }
      )
    end

    let!(:completed_batch) do
      DataDrip::BackfillRunBatch.create!(
        backfill_run: backfill_run,
        status: :completed,
        batch_size: 100,
        start_id: 1,
        finish_id: 100
      )
    end

    let!(:failed_batch) do
      DataDrip::BackfillRunBatch.create!(
        backfill_run: backfill_run,
        status: :failed,
        error_message: "boom",
        batch_size: 100,
        start_id: 101,
        finish_id: 200
      )
    end

    it "renders the run with its batches" do
      get :show, params: { id: backfill_run.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("AddRoleToEmployee")
      expect(response.body).to include("Run ##{backfill_run.id}")
      # Both batches show up in the batches table.
      expect(response.body).to include("boom")
      expect(response.body).to include("Completed")
    end

    it "narrows to failed batches when batch_status=failed" do
      get :show, params: { id: backfill_run.id, batch_status: "failed" }

      expect(response.body).to include("boom")
      expect(response.body).to include("Failed")
    end
  end

  describe "GET #updates" do
    render_views

    let!(:backfill_run) do
      DataDrip::BackfillRun.create!(
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller,
        options: { age: 25 }
      )
    end

    it "returns the current run state as JSON fragments" do
      backfill_run.update_column(
        :status,
        DataDrip::BackfillRun.statuses[:running]
      )

      get :updates, params: { id: backfill_run.id }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("running")
      expect(body["terminal"]).to be(false)
      expect(body["status_html"]).to include("Running")
      expect(body["progress_html"]).to be_present
      expect(body["batches_meta_html"]).to be_present
      expect(body).to have_key("batches_html")
    end

    it "reports terminal runs as terminal" do
      backfill_run.update_column(
        :status,
        DataDrip::BackfillRun.statuses[:completed]
      )

      get :updates, params: { id: backfill_run.id }

      expect(JSON.parse(response.body)["terminal"]).to be(true)
    end
  end

  describe "POST #set_timezone" do
    it "stores the timezone in the session and returns JSON" do
      post :set_timezone,
           params: { timezone: "America/New_York" },
           format: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({ "success" => true })
      expect(session[:user_timezone]).to eq("America/New_York")
    end

    it "redirects back for an HTML request" do
      post :set_timezone, params: { timezone: "Europe/Madrid" }

      expect(response).to redirect_to(backfill_runs_path)
      expect(session[:user_timezone]).to eq("Europe/Madrid")
    end

    it "leaves the session untouched when no timezone is given" do
      post :set_timezone, params: {}, format: :json

      expect(session[:user_timezone]).to be_nil
    end
  end

  describe "GET #backfill_options" do
    it "returns empty html when no class name is given" do
      get :backfill_options

      expect(JSON.parse(response.body)).to eq({ "html" => "" })
    end

    it "returns empty html when the class name is unknown" do
      get :backfill_options, params: { backfill_class_name: "NopeClass" }

      expect(JSON.parse(response.body)).to eq({ "html" => "" })
    end

    it "renders the option inputs for a real backfill class" do
      get :backfill_options,
          params: { backfill_class_name: "AddRoleToEmployee" }

      html = JSON.parse(response.body)["html"]
      expect(html).to include("backfill_run[options][age]")
      expect(html).to include("backfill_run[options][name]")
    end
  end

  describe "#find_current_backfiller" do
    around do |example|
      original = DataDrip.current_backfiller_method
      example.run
      DataDrip.current_backfiller_method = original
    end

    it "raises when no current_backfiller_method is configured" do
      DataDrip.current_backfiller_method = nil

      expect { controller.send(:find_current_backfiller) }.to raise_error(
        /Missing DataDrip.current_backfiller_method/
      )
    end

    it "raises when the configured method is not available on the controller" do
      DataDrip.current_backfiller_method = :not_a_real_method

      expect { controller.send(:find_current_backfiller) }.to raise_error(
        /Invalid DataDrip.current_backfiller_method/
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

        expect(response).to have_http_status(422)
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
