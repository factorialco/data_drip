# frozen_string_literal: true

module DataDrip
  module Paginatable
    extend ActiveSupport::Concern

    private

    def paginate_collection(collection, per_page: 25, page_param: :page)
      page = params[page_param].to_i
      page = 1 if page < 1

      total_count = collection.count
      total_pages = (total_count / per_page.to_f).ceil

      # Clamp past-the-end requests (e.g. ?page=999) to the last real page so
      # the offset and the "Showing X–Y" label stay sensible.
      page = total_pages if total_pages.positive? && page > total_pages

      offset = (page - 1) * per_page
      # Works for both an ActiveRecord relation (the runs lists) and a plain
      # Array (the backfills catalog, which paginates an in-memory list).
      paginated_collection =
        if collection.respond_to?(:limit)
          collection.limit(per_page).offset(offset)
        else
          collection[offset, per_page] || []
        end

      {
        collection: paginated_collection,
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: total_pages,
        has_previous_page: page > 1,
        has_next_page: page < total_pages,
        previous_page: page - 1,
        next_page: page + 1,
        page_range: calculate_page_range(page, total_pages)
      }
    end

    def calculate_page_range(current_page, total_pages)
      start_page = [ current_page - 2, 1 ].max
      end_page = [ start_page + 4, total_pages ].min
      (start_page..end_page)
    end
  end
end
