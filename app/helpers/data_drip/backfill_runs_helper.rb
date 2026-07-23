# frozen_string_literal: true

module DataDrip
  module BackfillRunsHelper
    INPUT_CLASSES =
      "block w-full rounded-lg bg-white px-3 py-1.5 text-sm text-zinc-900 " \
      "outline-1 -outline-offset-1 outline-zinc-950/15 placeholder:text-zinc-400 " \
      "focus:outline-2 focus:-outline-offset-1 focus:outline-drip-700 max-sm:text-base " \
      "dark:bg-white/5 dark:text-white dark:outline-white/15 " \
      "dark:placeholder:text-zinc-500 dark:focus:outline-drip-400"

    LABEL_CLASSES =
      "block text-sm font-semibold text-zinc-900 dark:text-white"

    STATUS_BADGES = {
      "pending" => {
        badge: "bg-zinc-50 text-zinc-600 inset-ring-zinc-500/20 " \
          "dark:bg-white/5 dark:text-zinc-400 dark:inset-ring-white/10",
        dot: "bg-zinc-400"
      },
      "enqueued" => {
        badge: "bg-amber-50 text-amber-700 inset-ring-amber-600/20 " \
          "dark:bg-amber-400/10 dark:text-amber-400 dark:inset-ring-amber-400/20",
        dot: "bg-amber-500"
      },
      "running" => {
        badge: "bg-blue-50 text-blue-700 inset-ring-blue-600/20 " \
          "dark:bg-blue-400/10 dark:text-blue-400 dark:inset-ring-blue-400/30",
        dot: "bg-blue-500 animate-pulse motion-reduce:animate-none"
      },
      "completed" => {
        badge: "bg-green-50 text-green-700 inset-ring-green-600/20 " \
          "dark:bg-green-400/10 dark:text-green-400 dark:inset-ring-green-400/30",
        dot: "bg-green-500"
      },
      "failed" => {
        badge: "bg-red-50 text-red-700 inset-ring-red-600/20 " \
          "dark:bg-red-400/10 dark:text-red-400 dark:inset-ring-red-400/30",
        dot: "bg-red-500"
      },
      "stopped" => {
        badge: "bg-zinc-50 text-zinc-600 inset-ring-zinc-500/20 " \
          "dark:bg-white/5 dark:text-zinc-400 dark:inset-ring-white/10",
        dot: "bg-zinc-400"
      }
    }.freeze

    def status_tag(status)
      config = STATUS_BADGES.fetch(status.to_s, STATUS_BADGES["pending"])

      content_tag(
        :span,
        class:
          "inline-flex items-center gap-x-1.5 rounded-full px-2 py-0.5 " \
          "text-xs font-medium inset-ring #{config[:badge]}"
      ) do
        tag.span(
          "",
          class: "size-1.5 rounded-full #{config[:dot]}",
          aria: { hidden: true }
        ) + status.to_s.capitalize
      end
    end

    # Renders a progress bar. Pass sizing (height/width/margins) via +classes+.
    def progress_bar(percent, status: nil, classes: "h-1.5")
      fill =
        case status.to_s
        when "failed"
          "bg-red-500"
        when "stopped"
          "bg-zinc-400 dark:bg-zinc-500"
        when "completed"
          "bg-green-500"
        else
          "bg-linear-to-r from-drip-pink to-drip-700"
        end

      content_tag(
        :div,
        class:
          "overflow-hidden rounded-full bg-zinc-950/5 dark:bg-white/10 #{classes}",
        role: "progressbar",
        aria: {
          valuenow: percent,
          valuemin: 0,
          valuemax: 100
        }
      ) do
        tag.div(
          "",
          class: "h-full rounded-full w-(--progress) #{fill}",
          style: "--progress: #{percent}%"
        )
      end
    end

    def relative_time(datetime, user_timezone = "UTC")
      return "" unless datetime

      local = datetime.in_time_zone(user_timezone.presence || "UTC")
      words =
        if datetime.past?
          "#{time_ago_in_words(datetime)} ago"
        else
          "in #{distance_of_time_in_words(Time.current, datetime)}"
        end

      tag.time(
        words,
        datetime: datetime.iso8601,
        title: local.strftime("%b %d, %Y %H:%M %Z")
      )
    end

    def format_duration(seconds)
      return "—" if seconds.nil?

      seconds = seconds.round
      return "#{seconds} s" if seconds < 60

      minutes = seconds / 60
      return "#{minutes} min" if minutes < 60

      "#{minutes / 60} h #{minutes % 60} min"
    end

    def format_datetime_in_user_timezone(datetime, user_timezone = "UTC")
      return "" unless datetime

      user_timezone = user_timezone.presence || "UTC"
      local_time = datetime.in_time_zone(user_timezone)

      local_time.strftime("%b %d, %H:%M")
    end

    def backfiller_initials(name)
      name.to_s.split.map { |part| part[0] }.first(2).join.upcase
    end

    def primary_button_classes
      "inline-flex items-center rounded-lg bg-drip-700 px-3 py-1.5 text-sm " \
        "font-semibold text-white hover:bg-drip-600 focus-visible:outline-2 " \
        "focus-visible:outline-offset-2 focus-visible:outline-drip-700 " \
        "dark:bg-drip-600 dark:hover:bg-drip-500 dark:focus-visible:outline-drip-400"
    end

    def secondary_button_classes(size: :base)
      padding = size == :small ? "px-2.5 py-1 text-xs" : "px-3 py-1.5 text-sm"

      "inline-flex items-center rounded-lg bg-white #{padding} font-semibold " \
        "text-zinc-900 shadow-xs ring-1 ring-zinc-950/10 hover:bg-zinc-50 " \
        "focus-visible:outline-2 focus-visible:outline-offset-2 " \
        "focus-visible:outline-drip-700 dark:bg-white/5 dark:text-white " \
        "dark:shadow-none dark:ring-white/10 dark:hover:bg-white/10"
    end

    def danger_button_classes
      "inline-flex items-center rounded-lg bg-red-50 px-3 py-1.5 text-sm " \
        "font-semibold text-red-700 ring-1 ring-red-600/20 hover:bg-red-100 " \
        "focus-visible:outline-2 focus-visible:outline-offset-2 " \
        "focus-visible:outline-red-600 dark:bg-red-400/10 dark:text-red-400 " \
        "dark:ring-red-400/20 dark:hover:bg-red-400/15"
    end

    def ghost_button_classes
      "inline-flex items-center rounded-lg px-3 py-1.5 text-sm font-semibold " \
        "text-zinc-600 hover:bg-zinc-950/5 dark:text-zinc-400 dark:hover:bg-white/5"
    end

    # Pill styling for the primary section navigation (Backfills / Scripts) in
    # the shared header.
    def nav_link_classes(active:)
      base = "rounded-lg px-3 py-1.5 text-sm font-medium transition-colors"
      state =
        if active
          "bg-drip-50 text-drip-700 dark:bg-drip-400/10 dark:text-drip-300"
        else
          "text-zinc-600 hover:bg-zinc-950/5 hover:text-zinc-900 " \
            "dark:text-zinc-400 dark:hover:bg-white/5 dark:hover:text-zinc-200"
        end

      "#{base} #{state}"
    end

    # A single option row in the backfill-class combobox. `data-name` /
    # `data-component` / `data-value` feed the fuzzy matcher in the Stimulus
    # controller; the name span is re-rendered with match highlights on filter.
    def backfill_class_option_tag(name, recent: false)
      component = name.deconstantize

      content_tag :li,
                  role: "option",
                  class:
                    "flex cursor-pointer items-baseline justify-between gap-x-4 " \
                    "rounded-md px-2.5 py-1.5",
                  data: {
                    combobox_target: "option",
                    action: "mousedown->combobox#select",
                    value: name,
                    name: name.demodulize,
                    component: component,
                    recent: recent.to_s
                  } do
        safe_join(
          [
            content_tag(
              :span,
              name.demodulize,
              class: "font-mono text-sm text-zinc-800 dark:text-zinc-200",
              data: { combobox_name: true }
            ),
            if component.present?
              content_tag(
                :span,
                component,
                class: "font-mono text-xs text-zinc-400 dark:text-zinc-500"
              )
            end
          ].compact
        )
      end
    end

    def backfill_option_inputs(backfill_run)
      backfill_class = backfill_run.backfill_class
      return "" unless backfill_class&.backfill_options_class

      typed_option_inputs(
        options_class: backfill_class.backfill_options_class,
        values: backfill_run.options,
        field_prefix: "backfill_run[options]",
        title: "Options · #{backfill_run.backfill_class_name}",
        required_attributes: backfill_class.required_option_names
      )
    end

    # Renders the typed input fields for an options/inputs schema. Shared by
    # backfills (prefix `backfill_run[options]`) and scripts (prefix
    # `script_run[inputs]`) through the `field_prefix` argument.
    def typed_option_inputs(
      options_class:,
      values:,
      field_prefix:,
      title:,
      required_attributes: [],
      description: nil
    )
      attribute_types = options_class.attribute_types
      return "" if attribute_types.empty? && description.blank?

      required_names = required_attributes.map(&:to_s).to_set
      defaults = options_class.new
      values ||= {}

      content_tag :div, class: "mb-5 rounded-xl bg-zinc-50 p-4 dark:bg-white/5" do
        header =
          content_tag :h3,
                      title,
                      class:
                        "#{description.present? ? "mb-1" : "mb-4"} font-mono text-xs font-medium text-zinc-500 dark:text-zinc-400"

        description_block =
          if description.present?
            content_tag :p,
                        description,
                        class: "mb-4 text-sm text-zinc-500 dark:text-zinc-400"
          else
            "".html_safe
          end

        inputs =
          safe_join(
            attribute_types.map do |name, type|
              required = required_names.include?(name.to_s)

              content_tag :div, class: "mb-4 last:mb-0" do
                label =
                  label_tag "#{field_prefix}[#{name}]",
                            class:
                              "mb-1.5 block font-mono text-sm font-medium " \
                              "text-zinc-700 dark:text-zinc-300" do
                    if required
                      safe_join(
                        [
                          name.to_s,
                          content_tag(
                            :span,
                            " · required",
                            class:
                              "font-sans font-normal text-zinc-400 dark:text-zinc-500"
                          )
                        ]
                      )
                    else
                      name.to_s
                    end
                  end

                input =
                  if type.is_a?(DataDrip::Types::Enum)
                    build_enum_input(name, type, values, field_prefix)
                  else
                    current = values[name]
                    value = current.nil? ? defaults.public_send(name) : current
                    build_standard_input(
                      name,
                      type,
                      value,
                      field_prefix,
                      required: required
                    )
                  end

                label + input
              end
            end
          )

        header + description_block + inputs
      end
    end

    private

    def build_standard_input(name, type, value, field_prefix, required: false)
      field_name = "#{field_prefix}[#{name}]"

      case type
      when ActiveModel::Type::String, ActiveModel::Type::ImmutableString
        text_field_tag field_name, value, class: INPUT_CLASSES, required: required
      when ActiveModel::Type::Integer, ActiveModel::Type::BigInteger
        number_field_tag field_name, value, class: INPUT_CLASSES, step: 1, required: required
      when ActiveModel::Type::Decimal, ActiveModel::Type::Float
        number_field_tag field_name, value, class: INPUT_CLASSES, step: 0.01, required: required
      when ActiveModel::Type::Boolean
        # Pair the checkbox with a hidden "0" field so an unchecked box
        # submits an explicit false instead of dropping the key entirely.
        # Without this, the attribute's `default:` silently re-applies on the
        # server, which is invisible from the persisted options.
        content_tag :div, class: "flex items-center gap-x-2" do
          hidden_field_tag(field_name, "0", id: nil) +
            check_box_tag(
              field_name,
              "1",
              value,
              class: "size-4 accent-drip-700 dark:accent-drip-400"
            ) +
            label_tag(
              field_name,
              "Enabled",
              class: "text-sm text-zinc-700 dark:text-zinc-300"
            )
        end
      when ActiveModel::Type::Date
        date_field_tag field_name, value, class: INPUT_CLASSES, required: required
      when ActiveModel::Type::Time
        time_field_tag field_name, value, class: INPUT_CLASSES, required: required
      when ActiveModel::Type::DateTime
        datetime_field_tag field_name, value, class: INPUT_CLASSES, required: required
      else
        text_area_tag field_name, value, class: INPUT_CLASSES, rows: 3, required: required
      end
    end

    def build_enum_input(name, type, values, field_prefix)
      raw_choices = type.available_values
      # Normalize to [label, value] pairs — supports both ["a","b"] and [["Label","val"],...]
      pairs = raw_choices.map { |choice| choice.is_a?(Array) ? choice : [ choice, choice ] }

      field_name = "#{field_prefix}[#{name}]"
      field_id = "enum_#{name}"
      current_value = values[name].to_s
      selected_values =
        current_value.present? ? current_value.split(",") : pairs.map(&:last).map(&:to_s)

      content_tag :div, data: { controller: "enum-select" } do
        hidden =
          hidden_field_tag field_name,
                           selected_values.join(","),
                           id: "#{field_id}_hidden",
                           data: {
                             enum_select_target: "hidden"
                           }

        search =
          tag.input(
            type: "text",
            id: "#{field_id}_search",
            placeholder: "Search…",
            autocomplete: "off",
            aria: { label: "Search options" },
            data: {
              enum_select_target: "search",
              action: "input->enum-select#filter"
            },
            class: "#{INPUT_CLASSES} mb-2"
          )

        toolbar =
          content_tag :div,
                      class:
                        "mb-2 flex items-center gap-x-3 border-b border-zinc-950/5 " \
                        "pb-2 dark:border-white/10" do
            select_all =
              check_box_tag(
                "#{field_id}_select_all",
                "1",
                selected_values.length == pairs.length,
                class: "size-4 accent-drip-700 dark:accent-drip-400",
                data: {
                  enum_select_target: "selectAll",
                  action: "change->enum-select#toggleAll"
                }
              )

            select_all_label =
              label_tag "#{field_id}_select_all",
                        "Select all",
                        class:
                          "text-sm font-medium text-zinc-700 dark:text-zinc-300"

            spacer = tag.span("", class: "flex-1")

            counter =
              content_tag :span,
                          "#{selected_values.length}/#{pairs.length} selected",
                          class: "text-xs text-zinc-500 tabular-nums dark:text-zinc-400",
                          data: {
                            enum_select_target: "counter"
                          }

            clear =
              content_tag :button,
                          "Clear",
                          type: "button",
                          class:
                            "text-xs font-medium text-drip-700 hover:text-drip-600 " \
                            "dark:text-drip-400 dark:hover:text-drip-300",
                          data: {
                            action: "enum-select#clear"
                          }

            select_all + select_all_label + spacer + counter + clear
          end

        checkboxes =
          safe_join(
            pairs.map do |label, value|
              value_string = value.to_s
              checkbox_id = "#{field_id}_#{value_string.parameterize(separator: "_")}"

              content_tag :div,
                          class:
                            "flex items-center gap-x-2 rounded-md px-2 py-1 " \
                            "hover:bg-zinc-950/5 dark:hover:bg-white/5",
                          data: {
                            enum_select_target: "row",
                            search: label.to_s.downcase
                          } do
                check_box_tag(
                  checkbox_id,
                  value_string,
                  selected_values.include?(value_string),
                  class: "size-4 accent-drip-700 dark:accent-drip-400",
                  data: {
                    enum_select_target: "checkbox",
                    action: "change->enum-select#sync"
                  }
                ) +
                  label_tag(
                    checkbox_id,
                    label,
                    class:
                      "flex-1 cursor-pointer text-sm text-zinc-700 select-none " \
                      "dark:text-zinc-300"
                  )
              end
            end
          )

        no_results =
          content_tag :p,
                      "No matches found.",
                      class: "hidden p-3 text-center text-sm text-zinc-400 dark:text-zinc-500",
                      data: {
                        enum_select_target: "noResults"
                      }

        list =
          content_tag :div,
                      checkboxes + no_results,
                      class:
                        "max-h-64 overflow-y-auto rounded-lg p-1 outline-1 " \
                        "-outline-offset-1 outline-zinc-950/10 dark:outline-white/10"

        hidden + search + toolbar + list
      end
    end
  end
end
