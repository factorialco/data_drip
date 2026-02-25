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

      options_class = backfill_run.backfill_class.backfill_options_class
      attribute_types = options_class.attribute_types
      return "" if attribute_types.empty?

      defaults = options_class.new

      input_class =
        "block w-full mt-1 rounded border border-gray-200 focus:ring focus:ring-blue-200 focus:border-blue-400 px-3 py-2"

      content_tag :div, class: "mb-6 p-4 rounded-lg bg-gray-50" do
        header_content =
          content_tag :h3,
                      "OPTIONS:",
                      class: "block text-gray-500 font-semibold mb-2"

        inputs_content =
          safe_join(
            attribute_types.map do |name, type|
              content_tag :div, class: "mb-6" do
                label_content =
                  label_tag "backfill_run[options][#{name}]",
                            name.to_s.upcase,
                            class: "block text-gray-500 font-semibold mb-2"

                input_content =
                  if type.is_a?(DataDrip::Types::Enum)
                    build_enum_input(name, type, backfill_run)
                  else
                    current = backfill_run.options[name]
                    value = current.nil? ? defaults.public_send(name) : current
                    build_standard_input(name, type, value, input_class)
                  end

                label_content + input_content
              end
            end
          )

        header_content + inputs_content
      end
    end

    private

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

    def build_enum_input(name, type, backfill_run)
      choices = type.available_values
      field_name = "backfill_run[options][#{name}]"
      field_id = "enum_#{name}"
      current_value = backfill_run.options[name].to_s
      selected = current_value.present? ? current_value.split(",") : choices

      hidden = hidden_field_tag field_name, selected.join(","), id: "#{field_id}_hidden"

      search_id = "#{field_id}_search"
      select_all_id = "#{field_id}_select_all"
      clear_id = "#{field_id}_clear"
      counter_id = "#{field_id}_counter"
      no_results_id = "#{field_id}_no_results"

      search_input = tag.input(
        type: "text",
        id: search_id,
        placeholder: "Search...",
        autocomplete: "off",
        style: "display: block; width: 100%; padding: 6px 10px 6px 30px; margin-bottom: 8px; " \
               "border: 1px solid #d1d5db; border-radius: 6px; font-size: 13px; " \
               "outline: none; box-sizing: border-box; " \
               "background-image: url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' " \
               "fill='none' viewBox='0 0 20 20'%3E%3Cpath stroke='%239ca3af' stroke-linecap='round' " \
               "stroke-width='2' d='m13 13 4 4M8.5 3a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11Z'/" \
               "%3E%3C/svg%3E\"); background-repeat: no-repeat; " \
               "background-position: 8px center; background-size: 16px 16px;"
      )

      counter = content_tag(:span, "#{selected.length}/#{choices.length} selected",
        id: counter_id,
        style: "font-size: 12px; color: #6b7280;")

      toolbar = content_tag(:div,
        style: "display: flex; align-items: center; gap: 10px; margin-bottom: 6px; " \
               "padding-bottom: 6px; border-bottom: 1px solid #e5e7eb;") do
        select_all_cb = check_box_tag(select_all_id, "1", selected.length == choices.length,
          style: "margin-right: 4px; cursor: pointer; accent-color: #3b82f6;")
        select_all_label = label_tag(select_all_id, "Select All",
          style: "font-size: 13px; color: #374151; font-weight: 500; cursor: pointer;")

        clear_btn = content_tag(:button, "Clear",
          type: "button",
          id: clear_id,
          style: "font-size: 12px; color: #3b82f6; background: none; border: none; " \
                 "cursor: pointer; text-decoration: underline; padding: 0;")

        spacer = content_tag(:span, "", style: "flex: 1;")

        select_all_cb + select_all_label + spacer + counter + clear_btn
      end

      checkboxes = safe_join(
        choices.map do |choice|
          cb_id = "#{field_id}_#{choice.parameterize(separator: '_')}"
          checked = selected.include?(choice)
          content_tag(:div,
            data: { value: choice.downcase },
            style: "display: flex; align-items: center; padding: 4px 6px; " \
                   "border-radius: 4px; transition: background-color 0.1s;") do
            check_box_tag(cb_id, choice, checked,
              class: "#{field_id}_cb",
              style: "margin-right: 8px; cursor: pointer; accent-color: #3b82f6;") +
              label_tag(cb_id, choice,
                style: "font-size: 13px; color: #374151; cursor: pointer; user-select: none;")
          end
        end
      )

      no_results = content_tag(:div, "No matches found",
        id: no_results_id,
        style: "display: none; padding: 12px; text-align: center; " \
               "color: #9ca3af; font-size: 13px; font-style: italic;")

      choices_container = content_tag(:div, checkboxes + no_results,
        id: "#{field_id}_list",
        style: "max-height: 260px; overflow-y: auto; border: 1px solid #e5e7eb; " \
               "border-radius: 6px; padding: 4px;")

      js = content_tag(:script) do
        raw(<<~JS)
          (function() {
            var hiddenField = document.getElementById('#{field_id}_hidden');
            var searchInput = document.getElementById('#{search_id}');
            var selectAll = document.getElementById('#{select_all_id}');
            var clearBtn = document.getElementById('#{clear_id}');
            var counter = document.getElementById('#{counter_id}');
            var noResults = document.getElementById('#{no_results_id}');
            var checkboxes = document.querySelectorAll('.#{field_id}_cb');
            var rows = document.querySelectorAll('##{field_id}_list > div[data-value]');
            var total = checkboxes.length;

            function syncToHidden() {
              var values = [];
              checkboxes.forEach(function(cb) { if (cb.checked) values.push(cb.value); });
              hiddenField.value = values.join(',');
              var count = values.length;
              counter.textContent = count + '/' + total + ' selected';
              selectAll.checked = (count === total);
              selectAll.indeterminate = (count > 0 && count < total);
            }

            searchInput.addEventListener('input', function() {
              var query = this.value.toLowerCase().trim();
              var visible = 0;
              rows.forEach(function(row) {
                var match = !query || row.getAttribute('data-value').indexOf(query) !== -1;
                row.style.display = match ? 'flex' : 'none';
                if (match) visible++;
              });
              noResults.style.display = visible === 0 ? 'block' : 'none';
            });

            selectAll.addEventListener('change', function() {
              var checked = selectAll.checked;
              checkboxes.forEach(function(cb) {
                if (cb.closest('div[data-value]').style.display !== 'none') {
                  cb.checked = checked;
                }
              });
              syncToHidden();
            });

            clearBtn.addEventListener('click', function() {
              checkboxes.forEach(function(cb) { cb.checked = false; });
              searchInput.value = '';
              rows.forEach(function(row) { row.style.display = 'flex'; });
              noResults.style.display = 'none';
              syncToHidden();
            });

            checkboxes.forEach(function(cb) {
              cb.addEventListener('change', syncToHidden);
            });

            rows.forEach(function(row) {
              row.addEventListener('mouseenter', function() { row.style.backgroundColor = '#f3f4f6'; });
              row.addEventListener('mouseleave', function() { row.style.backgroundColor = 'transparent'; });
            });

            syncToHidden();
          })();
        JS
      end

      hidden + search_input + toolbar + choices_container + js
    end
  end
end
