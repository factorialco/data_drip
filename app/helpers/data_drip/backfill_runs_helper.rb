# frozen_string_literal: true

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
      return "" unless backfill_run.backfill_class&.backfill_options_class

      attribute_types =
        backfill_run.backfill_class.backfill_options_class.attribute_types
      return "" if attribute_types.empty?

      metadata = backfill_run.backfill_class.respond_to?(:attribute_metadata) ?
        backfill_run.backfill_class.attribute_metadata : {}

      input_class =
        "block w-full mt-1 rounded border border-gray-200 focus:ring focus:ring-blue-200 focus:border-blue-400 px-3 py-2"

      content_tag :div, class: "mb-6 p-4 rounded-lg bg-gray-50" do
        header_content =
          content_tag :h3,
                      "OPTIONS:",
                      class: "block text-gray-500 font-semibold mb-2"

        inputs_content =
          attribute_types
            .map do |name, type|
              meta = metadata[name.to_sym] || {}

              content_tag :div, class: "mb-6" do
                label_content =
                  label_tag "backfill_run[options][#{name}]",
                            name.to_s.upcase,
                            class: "block text-gray-500 font-semibold mb-2"

                input_content =
                  if type.is_a?(DataDrip::Types::Enum)
                    build_enum_input(name, type, backfill_run, input_class)
                  else
                    value = resolve_option_value(backfill_run.options[name], meta[:form_default])
                    build_standard_input(name, type, value, input_class)
                  end

                label_content + input_content
              end
            end
            .join
            .html_safe

        header_content + inputs_content
      end
    end

    private

    def resolve_option_value(current_value, form_default)
      return current_value unless current_value.nil? && form_default
      form_default.respond_to?(:call) ? form_default.call : form_default
    end

    def build_standard_input(name, type, value, input_class)
      case type
      when ActiveModel::Type::String,
           ActiveModel::Type::ImmutableString
        text_field_tag "backfill_run[options][#{name}]",
                       value,
                       class: input_class
      when ActiveModel::Type::Integer, ActiveModel::Type::BigInteger
        number_field_tag "backfill_run[options][#{name}]",
                         value,
                         class: input_class,
                         step: 1
      when ActiveModel::Type::Decimal, ActiveModel::Type::Float
        number_field_tag "backfill_run[options][#{name}]",
                         value,
                         class: input_class,
                         step: 0.01
      when ActiveModel::Type::Boolean
        content_tag :div, class: "flex items-center" do
          check_box_tag(
            "backfill_run[options][#{name}]",
            "1",
            value,
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
                       value,
                       class: input_class
      when ActiveModel::Type::Time
        time_field_tag "backfill_run[options][#{name}]",
                       value,
                       class: input_class
      when ActiveModel::Type::DateTime
        datetime_field_tag "backfill_run[options][#{name}]",
                           value,
                           class: input_class
      else
        text_area_tag "backfill_run[options][#{name}]",
                      value,
                      class: input_class,
                      rows: 3
      end
    end

    def build_enum_input(name, type, backfill_run, _input_class)
      choices = type.available_values
      field_name = "backfill_run[options][#{name}]"
      field_id = "enum_#{name}"
      current_value = backfill_run.options[name].to_s
      selected = current_value.present? ? current_value.split(/[,;\s]+/).map(&:strip) : choices

      hidden = hidden_field_tag field_name, selected.join(","), id: "#{field_id}_hidden"

      select_all_id = "#{field_id}_select_all"
      clear_id = "#{field_id}_clear"
      all_checked = selected.sort == choices.sort

      toolbar = content_tag(:div, class: "flex items-center gap-4 mb-2 pb-2 border-b border-gray-200") do
        select_all = check_box_tag(select_all_id, "1", all_checked, class: "mr-1") +
          label_tag(select_all_id, "Select All", class: "text-gray-700 font-medium text-sm")

        clear_btn = content_tag(:button, "Clear",
          type: "button",
          id: clear_id,
          class: "text-sm text-blue-600 hover:text-blue-800 underline")

        select_all + clear_btn
      end

      checkboxes = choices.map do |choice|
        cb_id = "#{field_id}_#{choice.parameterize(separator: '_')}"
        checked = selected.include?(choice)
        content_tag(:div, class: "flex items-center mb-1") do
          check_box_tag(cb_id, choice, checked,
            class: "mr-2 #{field_id}_cb",
            data: { enum_field: field_id }) +
            label_tag(cb_id, choice, class: "text-gray-700 text-sm")
        end
      end.join.html_safe

      choices_container = content_tag(:div, checkboxes,
        style: "max-height: 200px; overflow-y: auto; border: 1px solid #e5e7eb; border-radius: 0.25rem; padding: 0.5rem;")

      js = content_tag(:script) do
        raw(<<~JS)
          (function() {
            var hiddenField = document.getElementById('#{field_id}_hidden');
            var selectAll = document.getElementById('#{select_all_id}');
            var clearBtn = document.getElementById('#{clear_id}');
            var checkboxes = document.querySelectorAll('.#{field_id}_cb');

            function syncToHidden() {
              var values = [];
              checkboxes.forEach(function(cb) { if (cb.checked) values.push(cb.value); });
              hiddenField.value = values.join(',');
              selectAll.checked = (values.length === checkboxes.length);
            }

            selectAll.addEventListener('change', function() {
              checkboxes.forEach(function(cb) { cb.checked = selectAll.checked; });
              syncToHidden();
            });

            clearBtn.addEventListener('click', function() {
              checkboxes.forEach(function(cb) { cb.checked = false; });
              syncToHidden();
            });

            checkboxes.forEach(function(cb) {
              cb.addEventListener('change', syncToHidden);
            });
          })();
        JS
      end

      hidden + toolbar + choices_container + js
    end
  end
end
