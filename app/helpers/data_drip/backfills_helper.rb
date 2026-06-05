# frozen_string_literal: true

module DataDrip
  module BackfillsHelper
    # Renders a backfill's declared options as inline-styled "chips" for the
    # catalog table (e.g. `company_ids: string`). Inline styles are used because
    # the engine ships a precompiled Tailwind build that isn't rebuilt for new
    # class names — see build_enum_input in BackfillRunsHelper for the same
    # approach.
    def custom_field_tags(backfill_class)
      fields = backfill_class.custom_fields
      return content_tag(:span, "—", style: "color: #9ca3af;") if fields.empty?

      safe_join(fields.map { |field| custom_field_chip(field) })
    end

    # Lowercased haystack used by the catalog's client-side search: matches on
    # the class name, the description, and each custom field name (so searching
    # "company_ids" surfaces every datadrip that accepts it).
    def backfill_search_terms(backfill_class)
      [
        backfill_class.name,
        backfill_class.description,
        *backfill_class.custom_fields.map { |field| field[:name] }
      ].compact.join(" ").downcase
    end

    private

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
               "white-space: nowrap;"
      )
    end
  end
end
