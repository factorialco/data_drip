# frozen_string_literal: true

module DataDrip
  # Fetches a group's status snapshot from several cells concurrently, against
  # a single shared deadline. A cell that errors or misses the deadline is
  # reported as unreachable instead of blocking the page: the coordinator's UI
  # must render whatever it has.
  class CellStatusFetcher
    DEADLINE_SECONDS = 5

    UNREACHABLE = { "unreachable" => true }.freeze

    def initialize(
      group_uuid:,
      cell_ids:,
      client: DataDrip::CellClient.new,
      deadline: DEADLINE_SECONDS
    )
      @group_uuid = group_uuid
      @cell_ids = cell_ids
      @client = client
      @deadline = deadline
    end

    # Returns { cell_id => snapshot }, where snapshot is either the Cell API's
    # group payload ({ "cell_id" =>, "runs" => [...] }) or an unreachable
    # marker ({ "unreachable" => true, ... }).
    def call
      threads =
        @cell_ids.map do |cell_id|
          thread = Thread.new { fetch(cell_id) }
          thread.report_on_exception = false
          [ cell_id, thread ]
        end

      deadline_at = monotonic_now + @deadline

      threads.to_h do |cell_id, thread|
        remaining = deadline_at - monotonic_now
        if thread.join([ remaining, 0 ].max)
          [ cell_id, thread.value ]
        else
          thread.kill
          [ cell_id, UNREACHABLE.merge("timed_out" => true) ]
        end
      end
    end

    private

    def fetch(cell_id)
      response = @client.fetch_group(cell_id: cell_id, group_uuid: @group_uuid)
      return response.body if response.success?

      UNREACHABLE.merge("http_status" => response.status)
    rescue DataDrip::CellTransport::Error => e
      UNREACHABLE.merge("error" => e.message)
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
