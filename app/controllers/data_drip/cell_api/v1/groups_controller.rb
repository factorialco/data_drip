# frozen_string_literal: true

module DataDrip
  module CellApi
    module V1
      class GroupsController < DataDrip::CellApi::BaseController
        # This cell's status snapshot for a group: the run it holds for the
        # group_uuid (exactly one, per the unique (group_uuid, cell_id) index).
        # Scoped to this cell's own rows so the answer cannot depend on how the
        # caller addressed us.
        def show
          group_uuid = params[:group_uuid]
          scope = { group_uuid: group_uuid, cell_id: current_cell_id }

          runs =
            DataDrip::BackfillRun.where(scope).to_a +
              DataDrip::ScriptRun.where(scope).to_a

          render json: {
                   cell_id: current_cell_id,
                   runs: runs.map { |run| DataDrip::RunSnapshot.for(run) }
                 }
        end
      end
    end
  end
end
