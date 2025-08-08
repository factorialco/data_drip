module DataDrip
  module BackfillRunsHelper
    def status_tag(status)
      tag_styles = case status.to_s
                   when "enqueued" then "background-color: #cec254; color: #fff; border: 1px solid #eab308;"
                   when "running" then "background-color: #e28e26; color: #fff; border: 1px solid #f97316;"
                   when "completed" then "background-color: #51bc5f; color: #fff; border: 1px solid #16a34a;"
                   when "failed" then "background-color: #ef4444; color: #fff; border: 1px solid #dc2626;"
                   when "stopped" then "background-color: #ef4444; color: #fff; border: 1px solid #dc2626;"
                   else "background-color: #9ca3af; color: #fff; border: 1px solid #6b7280;"
                   end
      content_tag(:span, status.to_s.capitalize,
                  class: "inline-block py-1 rounded text-xs font-semibold",
                  style: "#{tag_styles} padding-right: 5px; padding-left: 5px;")
    end

    def format_datetime_in_user_timezone(datetime, user_timezone = "UTC")
      return "" unless datetime

      user_timezone = user_timezone.presence || "UTC"
      local_time = datetime.in_time_zone(user_timezone)
      local_time.strftime("%d-%m-%Y, %H:%M:%S %Z")
    end
  end
end
