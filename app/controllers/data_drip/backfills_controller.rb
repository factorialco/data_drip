# frozen_string_literal: true

module DataDrip
  # Catalog of the backfill classes available in the host app. Unlike
  # BackfillRunsController (which lists persisted *runs*), this lists the
  # datadrip *definitions* themselves so users can discover what each one does
  # and which options it accepts.
  class BackfillsController < DataDrip.base_controller_class.constantize
    layout "data_drip/layouts/application"
    helper DataDrip::BackfillsHelper

    def index
      # Skip anonymous subclasses (e.g. those created in tests) — only real,
      # named datadrips belong in the catalog.
      @backfills =
        DataDrip.all.select { |klass| klass.name.present? }.sort_by(&:name)
    end
  end
end
