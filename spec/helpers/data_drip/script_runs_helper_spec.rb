# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::ScriptRunsHelper, type: :helper do
  describe "#script_input_fields" do
    let(:script_run) do
      DataDrip::ScriptRun.new(script_class_name: "GreetEmployees", inputs: {})
    end

    let(:html) { helper.script_input_fields(script_run) }

    it "returns empty string for an unknown script class" do
      run = DataDrip::ScriptRun.new(script_class_name: "Nope")
      expect(helper.script_input_fields(run)).to eq("")
    end

    it "namespaces fields under script_run[inputs]" do
      expect(html).to include(%(name="script_run[inputs][greeting]"))
      expect(html).to include(%(name="script_run[inputs][repeat]"))
    end

    it "renders the script description" do
      expect(html).to include(GreetEmployees.description)
    end

    it "marks required inputs with a required marker and required attribute" do
      expect(html).to match(
        %r{<label[^>]*for="script_run_inputs_greeting"[^>]*>greeting<span[^>]*> · required</span></label>}
      )
      expect(html).to match(
        %r{<input[^>]*type="text"[^>]*name="script_run\[inputs\]\[greeting\]"[^>]*required="required"}
      )
    end

    it "does not mark optional inputs as required" do
      expect(html).to match(
        %r{<label[^>]*for="script_run_inputs_repeat"[^>]*>repeat</label>}
      )
      expect(html).not_to match(
        %r{<input[^>]*name="script_run\[inputs\]\[repeat\]"[^>]*required}
      )
    end

    it "pairs boolean checkboxes with a hidden 0 field" do
      expect(html).to include(
        %(<input type="hidden" name="script_run[inputs][dry_run]" value="0")
      )
      expect(html).to match(
        %r{<input[^>]*type="checkbox"[^>]*name="script_run\[inputs\]\[dry_run\]"[^>]*value="1"}
      )
    end

    it "renders typed fields per input type" do
      expect(html).to match(
        %r{<input[^>]*type="number"[^>]*name="script_run\[inputs\]\[repeat\]"}
      )
      expect(html).to match(
        %r{<input[^>]*type="date"[^>]*name="script_run\[inputs\]\[effective_date\]"}
      )
    end

    it "pre-fills defaults and keeps submitted values sticky" do
      expect(html).to match(
        %r{<input[^>]*name="script_run\[inputs\]\[repeat\]"[^>]*value="1"}
      )

      sticky_run =
        DataDrip::ScriptRun.new(
          script_class_name: "GreetEmployees",
          inputs: {
            "greeting" => "Bonjour",
            "repeat" => "7"
          }
        )
      sticky_html = helper.script_input_fields(sticky_run)

      expect(sticky_html).to match(
        %r{<input[^>]*name="script_run\[inputs\]\[greeting\]"[^>]*value="Bonjour"}
      )
      expect(sticky_html).to match(
        %r{<input[^>]*name="script_run\[inputs\]\[repeat\]"[^>]*value="7"}
      )
    end
  end
end
