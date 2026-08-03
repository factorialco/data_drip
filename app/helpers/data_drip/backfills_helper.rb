# frozen_string_literal: true

module DataDrip
  # View helpers for the backfills catalog (BackfillsController).
  module BackfillsHelper
    # A backfill's one-line description. Guarded with `respond_to?` so a class
    # loaded before the `description` DSL existed (e.g. an older host app that
    # hasn't restarted after upgrading) degrades to nil instead of 500ing the
    # whole catalog.
    def backfill_description(backfill_class)
      return unless backfill_class.respond_to?(:description)

      backfill_class.description
    end

    # The configurable fields a backfill accepts, as `[{ name:, type: }]`,
    # derived from the declared options schema. Introspects
    # `backfill_options_class.attribute_types` directly so it renders even for a
    # backfill defined before richer introspection existed.
    def backfill_configurable_fields(backfill_class)
      return [] unless backfill_class.respond_to?(:backfill_options_class)

      backfill_class.backfill_options_class.attribute_types.map do |name, type|
        { name: name, type: type.type }
      end
    end

    # Renders the configurable-field pills for the catalog's last column, or an
    # em dash when a backfill takes no options.
    def backfill_configurable_field_tags(backfill_class)
      fields = backfill_configurable_fields(backfill_class)
      if fields.empty?
        return content_tag(:span, "—", class: "text-zinc-400 dark:text-zinc-600")
      end

      content_tag :div, class: "flex flex-wrap gap-1.5" do
        safe_join(fields.map { |field| configurable_field_pill(field) })
      end
    end

    private

    def configurable_field_pill(field)
      content_tag :span,
                  class:
                    "inline-flex items-baseline gap-x-1.5 rounded-md bg-zinc-100 " \
                    "px-2 py-0.5 dark:bg-white/10" do
        safe_join(
          [
            content_tag(
              :span,
              field[:name],
              class: "font-mono text-xs text-zinc-700 dark:text-zinc-200"
            ),
            content_tag(
              :span,
              field[:type],
              class: "font-mono text-[0.6875rem] text-zinc-400 dark:text-zinc-500"
            )
          ]
        )
      end
    end
  end
end
