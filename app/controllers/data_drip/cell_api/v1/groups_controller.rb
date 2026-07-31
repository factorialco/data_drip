# frozen_string_literal: true

module DataDrip
  module CellApi
    module V1
      class GroupsController < DataDrip::CellApi::BaseController
        # This cell's status snapshot for a group: whatever runs it holds for
        # the group_uuid (normally exactly one). Script snapshots include the
        # full log output — the coordinator never stores it, it re-fetches on
        # every poll.
        def show
          group_uuid = params[:group_uuid]

          runs =
            DataDrip::BackfillRun.where(group_uuid: group_uuid).to_a +
              DataDrip::ScriptRun.where(group_uuid: group_uuid).to_a

          render json: {
                   cell_id: current_cell_id,
                   runs: runs.map { |run| DataDrip::RunSnapshot.for(run) }
                 }
        end
      end
    end
  end
end
