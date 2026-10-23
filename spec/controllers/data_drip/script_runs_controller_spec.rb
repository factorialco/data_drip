# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::ScriptRunsController, type: :controller do
  routes { DataDrip::Engine.routes }

  let!(:backfiller) { User.create!(name: "Suzie") }

  let(:valid_inputs) { { greeting: "Hello", dry_run: "1" } }

  def create_script_run(attributes = {})
    DataDrip::ScriptRun.create!(
      {
        script_class_name: "GreetEmployees",
        backfiller: backfiller,
        inputs: valid_inputs
      }.merge(attributes)
    )
  end

  describe "GET #index" do
    render_views

    let!(:own_run) { create_script_run }
    let!(:other_run) do
      create_script_run(backfiller: User.create!(name: "Other"))
    end

    it "shows only the current backfiller's runs in the my_runs tab" do
      get :index, params: { tab: "my_runs" }

      expect(response.body).to include("/script_runs/#{own_run.id}")
      expect(response.body).not_to include("/script_runs/#{other_run.id}")
    end

    it "shows all runs in the all tab" do
      get :index, params: { tab: "all" }

      expect(response.body).to include("/script_runs/#{own_run.id}")
      expect(response.body).to include("/script_runs/#{other_run.id}")
    end
  end

  describe "POST #create" do
    render_views

    it "creates a new ScriptRun and redirects on success" do
      expect do
        post :create,
             params: {
               script_run: {
                 script_class_name: "GreetEmployees",
                 inputs: valid_inputs
               }
             }
      end.to change(DataDrip::ScriptRun, :count).by(1)

      script_run = DataDrip::ScriptRun.last!
      expect(script_run.backfiller).to eq(backfiller)
      expect(script_run.inputs).to eq(
        "greeting" => "Hello",
        "dry_run" => "1"
      )
      expect(script_run.status).to eq("enqueued")

      expect(response).to redirect_to(script_runs_path(tab: "my_runs"))
      expect(flash[:notice]).to match(/Script run for GreetEmployees/)
    end

    it "converts start_at from the user timezone" do
      post :create,
           params: {
             script_run: {
               script_class_name: "GreetEmployees",
               inputs: valid_inputs,
               start_at: "2030-01-15T10:30:00"
             },
             user_timezone: "America/New_York"
           }

      expect(response).to redirect_to(script_runs_path(tab: "my_runs"))
      expect(flash[:notice]).to include("Will run at 15-01-2030, 10:30:00 EST")
    end

    it "re-renders new with sticky inputs when validation fails" do
      expect do
        post :create,
             params: {
               script_run: {
                 script_class_name: "GreetEmployees",
                 inputs: {
                   greeting: "",
                   dry_run: "1",
                   repeat: "9"
                 }
               }
             }
      end.not_to change(DataDrip::ScriptRun, :count)

      expect(response.body).to include("There were errors")
      expect(response.body).to include("greeting can&#39;t be blank")
      # The inputs form is rendered server-side with the submitted values
      expect(response.body).to match(
        %r{<input[^>]*name="script_run\[inputs\]\[repeat\]"[^>]*value="9"}
      )
    end

    it "re-renders new when the script class is unknown" do
      expect do
        post :create,
             params: {
               script_run: {
                 script_class_name: "NonExistentClass"
               }
             }
      end.not_to change(DataDrip::ScriptRun, :count)

      expect(response.body).to include("must be a valid DataDrip script class")
    end
  end

  describe "GET #new" do
    render_views

    context "with source_run_id" do
      let!(:source_run) do
        create_script_run(
          inputs: {
            greeting: "Hi",
            repeat: "3",
            dry_run: "0"
          }
        )
      end

      it "pre-fills the class and inputs from the source run" do
        get :new, params: { source_run_id: source_run.id }

        expect(response.body).to include(
          'type="text" value="GreetEmployees" name="script_run[script_class_name]"'
        )
        expect(response.body).to include(
          'name="script_run[inputs][greeting]" id="script_run_inputs_greeting" value="Hi"'
        )
        expect(response.body).to include(
          'name="script_run[inputs][repeat]" id="script_run_inputs_repeat" value="3"'
        )
      end

      it "pre-fills a boolean input stored as the string \"0\" unchecked" do
        get :new, params: { source_run_id: source_run.id }

        expect(response.body).not_to match(
          %r{<input[^>]*type="checkbox"[^>]*name="script_run\[inputs\]\[dry_run\]"[^>]*checked}
        )
      end

      it "drops inputs the script class no longer declares" do
        source_run.update_columns(
          inputs: { greeting: "Hi", retired_input: "x" }
        )

        get :new, params: { source_run_id: source_run.id }

        expect(response.body).not_to include("retired_input")
      end

      it "falls back to the empty form when the source run does not exist" do
        get :new, params: { source_run_id: 999_999 }

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(
          'type="text" value="GreetEmployees" name="script_run[script_class_name]"'
        )
      end
    end
  end

  describe "GET #show" do
    render_views

    it "renders the run with its output and inputs" do
      script_run = create_script_run
      script_run.append_output("hello from the script")
      script_run.update!(status: :completed)

      get :show, params: { id: script_run.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("hello from the script")
      expect(response.body).to include("GreetEmployees")
    end

    it "shows a Run again link to the new-run form pre-filled from this run" do
      script_run = create_script_run

      get :show, params: { id: script_run.id }

      expect(response.body).to include(
        %(href="#{new_script_run_path(source_run_id: script_run.id)}")
      )
    end

    it "shows the Run again link even for a run owned by another backfiller" do
      script_run = create_script_run(backfiller: User.create!(name: "Bob"))

      get :show, params: { id: script_run.id }

      expect(response.body).to include(
        %(href="#{new_script_run_path(source_run_id: script_run.id)}")
      )
    end
  end

  describe "GET #updates" do
    render_views

    it "returns the run state as JSON" do
      script_run = create_script_run
      script_run.append_output("progress line")
      script_run.update!(
        status: :failed,
        error_message: "kapow",
        error_backtrace: "line1\nline2"
      )

      get :updates, params: { id: script_run.id }

      json = JSON.parse(response.body)
      expect(json["status"]).to eq("failed")
      expect(json["status_html"]).to include("Failed")
      expect(json["output"]).to include("progress line")
      expect(json["error_message"]).to eq("kapow")
      expect(json["error_backtrace"]).to eq("line1\nline2")
    end
  end

  describe "DELETE #destroy" do
    it "deletes an enqueued run" do
      script_run = create_script_run

      expect do
        delete :destroy, params: { id: script_run.id }
      end.to change(DataDrip::ScriptRun, :count).by(-1)

      expect(flash[:notice]).to eq("Script run has been deleted.")
    end

    it "refuses to delete a run that already ran" do
      script_run = create_script_run
      script_run.update!(status: :completed)

      expect do
        delete :destroy, params: { id: script_run.id }
      end.not_to change(DataDrip::ScriptRun, :count)

      expect(flash[:alert]).to eq(
        "Script run can only be deleted before it has run."
      )
    end

    it "refuses to delete a run belonging to another user" do
      other_user = User.create!(name: "Bob")
      script_run = create_script_run(backfiller: other_user)

      expect do
        delete :destroy, params: { id: script_run.id }
      end.not_to change(DataDrip::ScriptRun, :count)

      expect(flash[:alert]).to eq(
        "You can only delete script runs you created."
      )
    end
  end

  describe "GET #script_inputs" do
    it "returns empty html for a blank class name" do
      get :script_inputs, params: { script_class_name: "" }

      expect(JSON.parse(response.body)["html"]).to eq("")
    end

    it "returns empty html for an unknown class" do
      get :script_inputs, params: { script_class_name: "Nope" }

      expect(JSON.parse(response.body)["html"]).to eq("")
    end

    it "returns the rendered input fields with description and required markers" do
      get :script_inputs, params: { script_class_name: "GreetEmployees" }

      html = JSON.parse(response.body)["html"]
      expect(html).to include(%(name="script_run[inputs][greeting]"))
      expect(html).to include(" · required")
      expect(html).to include(GreetEmployees.description)
    end
  end
end
