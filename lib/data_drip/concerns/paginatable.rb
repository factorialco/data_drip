# frozen_string_literal: true

module DataDrip
  module Paginatable
    extend ActiveSupport::Concern

    private

    def paginate_collection(collection, per_page: 25, page_param: :page)
      page = params[page_param].to_i
      page = 1 if page < 1

      offset = (page - 1) * per_page

      paginated_collection = collection.limit(per_page).offset(offset)
      total_count = collection.count
      total_pages = (total_count / per_page.to_f).ceil

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
