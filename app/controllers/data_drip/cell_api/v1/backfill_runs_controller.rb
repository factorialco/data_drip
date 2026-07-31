# frozen_string_literal: true

module DataDrip
  module CellApi
    module V1
      class BackfillRunsController < DataDrip::CellApi::BaseController
        # Creates this cell's copy of a fanned-out run. Idempotent per
        # (group_uuid, cell_id): a duplicate delivery gets the existing run
        # back with 200 instead of a new one.
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

          run = DataDrip::BackfillRun.new(create_params)
          run.origin = :remote

          if run.save
            render_snapshot(run, status: :created)
          elsif (existing = find_existing)
            # Lost a race against a concurrent duplicate delivery (the unique
            # index, or the duplicate-active-run guard tripping on our own
            # group sibling).
            render_snapshot(existing)
          else
            render json: { errors: run.errors.full_messages },
                   status: :unprocessable_entity
          end
        rescue ActiveRecord::RecordNotUnique
          render_snapshot(find_existing)
        end

        def destroy
          run = DataDrip::BackfillRun.find_by(id: params[:id])
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

        def stop
          run = DataDrip::BackfillRun.find_by(id: params[:id])
          return render json: { error: "not_found" }, status: :not_found unless run

          unless run.backfiller_id == acting_backfiller_id
            return render json: { error: "not_owner" }, status: :forbidden
          end
          unless run.running?
            return render json: { error: "not_running" }, status: :conflict
          end

          run.stopped!
          render_snapshot(run)
        end

        def retry_failed_batches
          run = DataDrip::BackfillRun.find_by(id: params[:id])
          return render json: { error: "not_found" }, status: :not_found unless run

          unless run.backfiller_id == acting_backfiller_id
            return render json: { error: "not_owner" }, status: :forbidden
          end

          failed_batches = run.batches.failed
          if failed_batches.none?
            return render json: { error: "no_failed_batches" }, status: :conflict
          end

          failed_batches.find_each do |batch|
            batch.update!(status: :pending, error_message: nil)
            batch.enqueue
          end
          run.running! unless run.running?
          render_snapshot(run)
        end

        private

        def find_existing
          DataDrip::BackfillRun.find_by(
            group_uuid: params[:group_uuid],
            cell_id: current_cell_id
          )
        end

        def create_params
          params.permit(
            :group_uuid,
            :origin_cell_id,
            :backfill_class_name,
            :batch_size,
            :amount_of_elements,
            :start_at,
            :backfiller_id,
            :backfiller_name,
            options: {}
          )
        end
      end
    end
  end
end
