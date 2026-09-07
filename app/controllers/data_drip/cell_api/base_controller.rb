# frozen_string_literal: true

module DataDrip
  module CellApi
    # Machine-to-machine base controller. Deliberately NOT inheriting from
    # DataDrip.base_controller_class: there is no human session here, only a
    # shared-secret bearer token that authenticates the calling *cell*.
    class BaseController < ActionController::API
      before_action :authenticate_cell!
      before_action :verify_target_cell!

      private

      def authenticate_cell!
        tokens = DataDrip.resolved_cell_api_tokens
        provided = request.headers["Authorization"].to_s[/\ABearer (.+)\z/m, 1].to_s

        authorized =
          provided.present? &&
            tokens.any? do |token|
              ActiveSupport::SecurityUtils.secure_compare(token, provided)
            end
        return if authorized

        # The Cell API is a shared-secret surface reachable from outside the
        # cell, so rejections are logged: a run of them is the signal that a
        # token was rotated in one cell but not another, or is being guessed.
        audit(
          "unauthorized",
          reason: tokens.empty? ? "no_tokens_configured" : "token_mismatch",
          token_provided: provided.present?
        )
        render json: { error: "unauthorized" }, status: :unauthorized
      end

      # Every request names the cell it was meant for; if the routing layer
      # delivered it to a different one, refuse instead of silently acting on
      # the wrong cell's data.
      def verify_target_cell!
        target = params[:target_cell_id].to_s
        return if target.present? && target == current_cell_id

        audit("misdirected", target_cell_id: target)
        render json: {
                 error: "misdirected",
                 target_cell_id: target,
                 current_cell_id: current_cell_id
               },
               status: :misdirected_request
      end

      def current_cell_id
        DataDrip.resolved_current_cell_id
      end

      def acting_backfiller_id
        params[:acting_backfiller_id].to_i
      end

      def render_snapshot(run, status: :ok)
        render json: DataDrip::RunSnapshot.for(run), status: status
      end

      # Cell-to-cell calls mutate runs on behalf of an operator in another cell,
      # so each one leaves a structured trace naming the actor, the target and
      # the outcome. Without it a stopped or deleted run in this cell has no
      # local explanation at all.
      def audit(outcome, **details)
        Rails.logger.info(
          {
            event: "data_drip.cell_api",
            action: "#{controller_name}##{action_name}",
            outcome: outcome,
            cell_id: DataDrip.resolved_current_cell_id,
            acting_backfiller_id: params[:acting_backfiller_id].presence,
            group_uuid: params[:group_uuid].presence,
            run_id: params[:id].presence,
            remote_ip: request.remote_ip
          }.merge(details).compact.to_json
        )
      end

      # Fanned-out mutations may only ever touch this cell's own leg of a group:
      # a run created here through the Cell API. A run an operator created in
      # this cell's own UI is none of another cell's business, even though the
      # caller holds a valid token.
      def find_remote_run(scope)
        scope.remote.find_by(id: params[:id], cell_id: current_cell_id)
      end
    end
  end
end
