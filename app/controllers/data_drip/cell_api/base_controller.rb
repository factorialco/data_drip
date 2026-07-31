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

        render json: { error: "unauthorized" }, status: :unauthorized
      end

      # Every request names the cell it was meant for; if the routing layer
      # delivered it to a different one, refuse instead of silently acting on
      # the wrong cell's data.
      def verify_target_cell!
        target = params[:target_cell_id].to_s
        return if target.present? && target == current_cell_id

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
    end
  end
end
