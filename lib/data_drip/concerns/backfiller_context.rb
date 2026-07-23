# frozen_string_literal: true

module DataDrip
  # Shared controller behavior: resolving the current backfiller through the
  # configured method and tracking the user's timezone in the session.
  module BackfillerContext
    extend ActiveSupport::Concern

    included do
      helper_method :find_current_backfiller

      before_action :set_user_timezone
    end

    def find_current_backfiller
      if DataDrip.current_backfiller_method.blank?
        raise "Missing DataDrip.current_backfiller_method, please set it in an initializer (like DataDrip.current_backfiller_method = :current_user"
      end
      unless respond_to?(DataDrip.current_backfiller_method, true)
        raise "Invalid DataDrip.current_backfiller_method: #{DataDrip.current_backfiller_method}. Maybe you need to change the `base_controller_class` for DataDrip (currently: #{DataDrip.base_controller_class})?"
      end

      send(DataDrip.current_backfiller_method)
    end

    private

    def set_user_timezone
      @user_timezone =
        params[:user_timezone].presence || session[:user_timezone] || "UTC"
      session[:user_timezone] = @user_timezone if params[
        :user_timezone
      ].present?
    end
  end
end
