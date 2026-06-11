# frozen_string_literal: true

module DataDrip
  module BackfillsHelper
    # Renders a backfill's declared options as inline-styled "chips" for the
    # catalog table (e.g. `company_ids: string`). Inline styles are used because
    # the engine ships a precompiled Tailwind build that isn't rebuilt for new
    # class names — see build_enum_input in BackfillRunsHelper for the same
    # approach.
    def custom_field_tags(backfill_class)
      fields = backfill_fields(backfill_class)
      return content_tag(:span, "—", style: "color: #9ca3af;") if fields.empty?

      safe_join(fields.map { |field| custom_field_chip(field) })
    end

    # Description is optional. A backfill class that predates the DSL — or that
    # simply doesn't set one — won't respond to .description, so guard the call
    # instead of letting the whole catalog 500.
    def backfill_description(backfill_class)
      return unless backfill_class.respond_to?(:description)

      backfill_class.description
    end

    # Lowercased haystack used by the catalog's client-side search: matches on
    # the class name, the description, and each custom field name (so searching
    # "company_ids" surfaces every datadrip that accepts it).
    def backfill_search_terms(backfill_class)
      [
        backfill_class.name,
        backfill_description(backfill_class),
        *backfill_fields(backfill_class).map { |field| field[:name] }
      ].compact.join(" ").downcase
    end

    private

    # Reads a backfill's declared options for the CUSTOM FIELDS column. Prefer
    # the Backfill.custom_fields DSL, but fall back to introspecting the options
    # model's attribute_types directly. The fallback matters in a host app whose
    # DataDrip::Backfill was loaded before custom_fields existed (e.g. the server
    # wasn't restarted after upgrading): attribute_types has always been part of
    # the options model, so the chips still render.
    def backfill_fields(backfill_class)
      return backfill_class.custom_fields if backfill_class.respond_to?(:custom_fields)
      return [] unless backfill_class.respond_to?(:backfill_options_class)

      backfill_class.backfill_options_class.attribute_types.map do |name, type|
        { name: name, type: type.type }
      end
    end

    def custom_field_chip(field)
      label = "#{field[:name]}: #{field[:type]}"
      values = Array(field[:values]).map(&:to_s)

      unless values.empty?
        preview = values.join(", ")
        preview = "#{preview[0, 37]}…" if preview.length > 38
        label = "#{label} (#{preview})"
      end

      content_tag(
        :span,
        label,
        title: (values.join(", ") if values.any?),
        style: "display: inline-block; margin: 2px 4px 2px 0; padding: 2px 8px; " \
               "border-radius: 9999px; background-color: #eef2ff; color: #4338ca; " \
               "font-size: 12px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; " \
               "white-space: normal; overflow-wrap: anywhere;"
      )
    end
  end
end
