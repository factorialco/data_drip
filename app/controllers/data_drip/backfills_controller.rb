# frozen_string_literal: true

module DataDrip
  # Catalog of the backfill classes available in the host app. Unlike
  # BackfillRunsController (which lists persisted *runs*), this lists the
  # backfill *definitions* themselves so users can discover what each one does
  # and which options it accepts.
  class BackfillsController < DataDrip.base_controller_class.constantize
    include DataDrip::Paginatable
    include DataDrip::BackfillerContext

    layout "data_drip/layouts/application"
    helper DataDrip::BackfillRunsHelper
    helper DataDrip::BackfillsHelper

    def index
      @query = params[:q].to_s.strip

      # Skip anonymous subclasses (e.g. those created in tests) — only real,
      # named backfills belong in the catalog.
      backfills =
        DataDrip.all.select { |klass| klass.name.present? }.sort_by(&:name)
      backfills = filter_backfills(backfills, @query) if @query.present?

      pagination_data = paginate_collection(backfills, per_page: 10)
      @backfills = pagination_data[:collection]
      @pagination = pagination_data
    end

    private

    # Client asks for a needle; we match it (case-insensitively) against the
    # class name, the description, and each option name — so searching
    # "company_ids" surfaces every backfill that accepts it.
    def filter_backfills(backfills, query)
      needle = query.downcase
      backfills.select do |klass|
        haystack =
          [
            klass.name,
            (klass.description if klass.respond_to?(:description)),
            *klass.backfill_options_class.attribute_types.keys
          ].compact.join(" ").downcase
        haystack.include?(needle)
      end
    end
  end
end
