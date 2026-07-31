# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::MultiCellRun do
  let!(:backfiller) { User.create!(name: "Suzie") }

  def build_run(**attributes)
    DataDrip::BackfillRun.new(
      {
        backfill_class_name: "AddRoleToEmployee",
        batch_size: 100,
        start_at: 1.hour.from_now,
        backfiller: backfiller
      }.merge(attributes)
    )
  end

  describe "cell stamping" do
    it "leaves cell_id nil in single-cell mode" do
      run = build_run
      run.save!

      expect(run.cell_id).to be_nil
      expect(run.origin).to eq("local")
    end

    it "stamps the current cell on creation in multi-cell mode" do
      configure_multi_cell!

      run = build_run
      run.save!

      expect(run.cell_id).to eq("cell-a")
    end

    it "keeps an explicitly assigned cell_id" do
      configure_multi_cell!

      run = build_run(cell_id: "somewhere-else")
      run.save!

      expect(run.cell_id).to eq("somewhere-else")
    end
  end

  describe "backfiller validation" do
    it "requires a backfiller id always" do
      run = build_run(backfiller: nil)

      expect(run).not_to be_valid
      expect(run.errors[:backfiller_id]).to be_present
    end

    it "requires a locally existing backfiller for local runs" do
      run = build_run(backfiller: nil, backfiller_id: backfiller.id + 999)

      expect(run).not_to be_valid
      expect(run.errors[:backfiller]).to include("must exist")
    end

    it "accepts a non-resolvable backfiller id for remote runs" do
      run =
        build_run(
          backfiller: nil,
          backfiller_id: backfiller.id + 999,
          backfiller_name: "Remote Rita",
          origin: :remote,
          group_uuid: "g-1"
        )

      expect(run).to be_valid
      run.save!
      expect(run.backfiller_display_name).to eq("Remote Rita")
    end
  end

  describe "backfiller_name snapshot on script runs" do
    it "snapshots the name at creation and survives backfiller deletion" do
      run =
        DataDrip::ScriptRun.create!(
          script_class_name: "GreetEmployees",
          inputs: { "greeting" => "Hi", "dry_run" => true },
          backfiller: backfiller
        )

      expect(run.backfiller_name).to eq("Suzie")

      backfiller.destroy!
      expect(run.reload.backfiller_display_name).to eq("Suzie")
    end
  end

  describe "#dispatches and #multi_cell_group?" do
    it "is not a group without a group_uuid" do
      run = build_run
      run.save!

      expect(run.dispatches).to be_empty
      expect(run.multi_cell_group?).to be(false)
    end

    it "exposes the group's dispatches ordered by cell" do
      run = build_run(group_uuid: "g-1")
      run.save!

      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-c",
        runnable_type: :backfill
      )
      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill
      )

      expect(run.dispatches.map(&:cell_id)).to eq(%w[cell-b cell-c])
      expect(run.multi_cell_group?).to be(true)
    end

    it "is never a group for remote runs" do
      run = build_run(group_uuid: "g-1", origin: :remote)
      run.save!

      DataDrip::CellDispatch.create!(
        group_uuid: "g-1",
        cell_id: "cell-b",
        runnable_type: :backfill
      )

      expect(run.multi_cell_group?).to be(false)
    end
  end

  describe "duplicate dispatch protection" do
    it "enforces one run per (group, cell)" do
      configure_multi_cell!

      build_run(group_uuid: "g-1").save!

      # A different amount_of_elements sidesteps the duplicate-active-run
      # validation, proving the DB index itself is the last line of defense.
      expect do
        build_run(group_uuid: "g-1", amount_of_elements: 1).save!
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows many runs with no group (legacy rows)" do
      build_run.save!
      run = build_run(amount_of_elements: 5)

      expect(run.save).to be(true)
    end
  end
end
