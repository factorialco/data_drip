module DataDrip
  module BackfillRunsHelper
    def status_tag(status)
      tag_styles =
        case status.to_s
        when "enqueued"
          "background-color: #cec254; color: #fff; border: 1px solid #eab308;"
        when "running"
          "background-color: #e28e26; color: #fff; border: 1px solid #f97316;"
        when "completed"
          "background-color: #51bc5f; color: #fff; border: 1px solid #16a34a;"
        when "failed"
          "background-color: #ef4444; color: #fff; border: 1px solid #dc2626;"
        when "stopped"
          "background-color: #ef4444; color: #fff; border: 1px solid #dc2626;"
        else
          "background-color: #9ca3af; color: #fff; border: 1px solid #6b7280;"
        end
      content_tag(
        :span,
        status.to_s.capitalize,
        class: "inline-block py-1 rounded text-xs font-semibold",
        style: "#{tag_styles} padding-right: 5px; padding-left: 5px;"
      )
    end

    def format_datetime_in_user_timezone(datetime, user_timezone = "UTC")
      return "" unless datetime

      user_timezone = user_timezone.presence || "UTC"
      local_time = datetime.in_time_zone(user_timezone)
      
      local_time.strftime("%b %d, %H:%M")
    end

    def backfill_option_inputs(backfill_run)
      return "" unless backfill_run.backfill_class&.backfill_options

      attribute_types =
        backfill_run.backfill_class.backfill_options.attribute_types
      return "" if attribute_types.empty?

      input_class =
        "block w-full mt-1 rounded border border-gray-200 focus:ring focus:ring-blue-200 focus:border-blue-400 px-3 py-2"

      attribute_types
        .map do |name, type|
          content_tag :div, class: "mb-6" do
            label_content =
              label_tag "backfill_run[options][#{name}]",
                        "FILTER BY #{name.to_s.upcase}",
                        class: "block text-gray-500 font-semibold mb-2"

            input_content =
              case type
              when ActiveModel::Type::String, ActiveModel::Type::ImmutableString
                text_field_tag "backfill_run[options][#{name}]",
                               backfill_run.options[name],
                               class: input_class
              when ActiveModel::Type::Integer, ActiveModel::Type::BigInteger
                number_field_tag "backfill_run[options][#{name}]",
                                 backfill_run.options[name],
                                 class: input_class,
                                 step: 1
              when ActiveModel::Type::Decimal, ActiveModel::Type::Float
                number_field_tag "backfill_run[options][#{name}]",
                                 backfill_run.options[name],
                                 class: input_class,
                                 step: 0.01
              when ActiveModel::Type::Boolean
                content_tag :div, class: "flex items-center" do
                  check_box_tag(
                    "backfill_run[options][#{name}]",
                    "1",
                    backfill_run.options[name],
                    class: "mr-2"
                  ) +
                    label_tag(
                      "backfill_run[options][#{name}]",
                      "Yes",
                      class: "text-gray-700"
                    )
                end
              when ActiveModel::Type::Date
                date_field_tag "backfill_run[options][#{name}]",
                               backfill_run.options[name],
                               class: input_class
              when ActiveModel::Type::Time
                time_field_tag "backfill_run[options][#{name}]",
                               backfill_run.options[name],
                               class: input_class
              when ActiveModel::Type::DateTime
                datetime_field_tag "backfill_run[options][#{name}]",
                                   backfill_run.options[name],
                                   class: input_class
              else
                text_area_tag "backfill_run[options][#{name}]",
                              backfill_run.options[name],
                              class: input_class,
                              rows: 3
              end

            label_content + input_content
          end
        end
        .join
        .html_safe
    end
  end
end
