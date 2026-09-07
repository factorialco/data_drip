# frozen_string_literal: true

require "concurrent"

module DataDrip
  # Runs one block per cell against a single shared deadline and a bounded pool,
  # so a slow or hung cell costs the caller its deadline once — not once per
  # cell — and a wide fan-out cannot spawn an unbounded number of threads.
  #
  # Every cross-cell fan-out goes through here: reading status snapshots for the
  # coordinator's UI, and applying stop/delete/retry to the remote legs. Both
  # run inside a web request, so both need the same bound.
  module CellFanout
    # Cross-cell control traffic is tiny; the ceiling exists to keep a wide
    # fan-out from starving the host's thread budget, not to throttle work.
    MAX_CONCURRENCY = 8

    # Long enough for a healthy cell to answer, short enough that a request
    # fanning out to a dead cell still returns within a browser's patience.
    DEFAULT_DEADLINE_SECONDS = 5

    TimedOut = Class.new(DataDrip::Error)

    module_function

    # Yields each cell id on a pool thread and returns { cell_id => value }.
    # A cell that raises gets the exception object; a cell that misses the
    # deadline gets a TimedOut instance. Callers decide what either means —
    # nothing here swallows a failure silently.
    def call(cell_ids, deadline: DEFAULT_DEADLINE_SECONDS, &block)
      return {} if cell_ids.empty?

      pool = Concurrent::FixedThreadPool.new([ cell_ids.size, MAX_CONCURRENCY ].min)

      futures =
        cell_ids.to_h do |cell_id|
          [ cell_id, Concurrent::Promises.future_on(pool) { wrapped(cell_id, &block) } ]
        end

      deadline_at = monotonic_now + deadline

      results =
        futures.to_h do |cell_id, future|
          remaining = [ deadline_at - monotonic_now, 0 ].max
          [ cell_id, settle(cell_id, future, remaining, deadline) ]
        end

      # Work we gave up waiting for is left to drain rather than killed
      # mid-socket: its result is discarded and the block has no side effects,
      # so the only cost is a thread parked until its socket times out (which
      # is why the transport's timeouts sit near this deadline).
      pool.shutdown
      results
    end

    def settle(cell_id, future, remaining, deadline)
      unless future.wait(remaining)
        return TimedOut.new("Cell #{cell_id} did not answer within #{deadline}s")
      end

      future.fulfilled? ? future.value : future.reason
    end

    # The block may touch autoloaded constants, so it runs inside the Rails
    # executor: without it a pool thread can race the dev-mode reloader.
    def wrapped(cell_id, &block)
      if defined?(Rails) && Rails.application
        Rails.application.executor.wrap { block.call(cell_id) }
      else
        block.call(cell_id)
      end
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
