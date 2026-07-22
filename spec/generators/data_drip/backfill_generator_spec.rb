# frozen_string_literal: true

require "spec_helper"
require "ripper"
require "rails/generators"
require "generators/data_drip/backfill_generator"

RSpec.describe DataDrip::Generators::BackfillGenerator, type: :generator do
  let(:backfills_dir) { Rails.root.join("app/backfills") }

  around do |example|
    @generated_paths = []
    example.run
  ensure
    @generated_paths.each { |path| File.delete(path) if File.exist?(path) }
  end

  # Runs the real generator and returns the generated file's source.
  def generate(name, *args)
    # Silence Thor's create/exist status output.
    original_stdout = $stdout
    $stdout = StringIO.new
    described_class.start([ name, *args ])
    $stdout = original_stdout

    path = backfills_dir.join("#{name.underscore}.rb")
    @generated_paths << path
    File.read(path)
  end

  describe "without --sorbet" do
    it "generates syntactically valid Ruby" do
      source = generate("PlainSample")

      expect(Ripper.sexp(source)).not_to be_nil
      expect(source).to include("class PlainSample < DataDrip::Backfill")
      expect(source).to include("def scope")
      expect(source).not_to include("# typed:")
      expect(source).not_to include("T::Sig")
    end
  end

  describe "with --sorbet" do
    it "generates syntactically valid Ruby (regression: no stray bracket in sig)" do
      source = generate("SorbetSample", "--sorbet")

      # Ripper returns nil on a syntax error — the old template shipped
      # `sig { returns(RelationType]) }`, which would fail this.
      expect(Ripper.sexp(source)).not_to be_nil
    end

    it "emits sensible Sorbet annotations" do
      source = generate("SorbetSample", "--sorbet")

      expect(source).to include("# typed: strict")
      expect(source).to include("extend T::Sig")
      expect(source).to include("sig { returns(ActiveRecord::Relation) }")
      expect(source).to include("sig { params(batch: ActiveRecord::Relation).void }")
      expect(source).to include("sig { params(element: T.untyped).void }")
      # The broken generic scaffolding is gone.
      expect(source).not_to include("type_member")
    end
  end
end
