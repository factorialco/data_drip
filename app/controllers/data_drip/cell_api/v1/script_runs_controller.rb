# frozen_string_literal: true

module DataDrip
  module CellApi
    module V1
      class ScriptRunsController < DataDrip::CellApi::BaseController
        # Creates this cell's copy of a fanned-out script run. Idempotent per
        # (group_uuid, cell_id), same contract as backfill runs.
        def create
          if params[:group_uuid].blank?
            return(
              render json: { errors: [ "group_uuid is required" ] },
                     status: :unprocessable_entity
            )
          end

          if (existing = find_existing)
            return render_snapshot(existing)
          end

          run = DataDrip::ScriptRun.new(create_params)
          run.origin = :remote

          if run.save
            render_snapshot(run, status: :created)
          elsif (existing = find_existing)
            render_snapshot(existing)
          else
            render json: { errors: run.errors.full_messages },
                   status: :unprocessable_entity
          end
        rescue ActiveRecord::RecordNotUnique
          render_snapshot(find_existing)
        end

        def destroy
          run = DataDrip::ScriptRun.find_by(id: params[:id])
          return render json: { error: "not_found" }, status: :not_found unless run

          unless run.backfiller_id == acting_backfiller_id
            return render json: { error: "not_owner" }, status: :forbidden
          end
          unless run.not_yet_run?
            return render json: { error: "already_run" }, status: :conflict
          end

          run.destroy!
          head :no_content
        end

        private

        def find_existing
          DataDrip::ScriptRun.find_by(
            group_uuid: params[:group_uuid],
            cell_id: current_cell_id
          )
        end

        def create_params
          params.permit(
            :group_uuid,
            :origin_cell_id,
            :script_class_name,
            :start_at,
            :backfiller_id,
            :backfiller_name,
            inputs: {}
          )
        end
      end
    end
  end
end
