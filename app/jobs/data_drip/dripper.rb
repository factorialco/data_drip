# frozen_string_literal: true

module DataDrip
  class Dripper < DataDrip.base_job_class.safe_constantize
    queue_as { DataDrip.queue_name }

    # How many ids one planning query fetches. Each page is cut into batches of
    # the run's batch_size, so planning issues one query per ~10k records
    # instead of two per batch.
    PLANNING_PAGE_SIZE = 10_000

    def perform(backfill_run)
      # Idempotency guard: a run transitions enqueued -> running once, and is
      # only planned while it is enqueued or still planning (running without a
      # total_count). A duplicate delivery after planning finished, or for a
      # terminal run, is a no-op. A delivery that finds the run mid-planning
      # (the previous worker was killed, e.g. by a deploy) resumes after the
      # last planned batch instead of leaving the run stuck in `running`.
      return unless backfill_run.enqueued? || backfill_run.planning?

      backfill_run.running! if backfill_run.enqueued?

      scope =
        backfill_run.backfill_class.new(
          batch_size: backfill_run.batch_size,
          backfill_options: backfill_run.options || {}
        ).scope

      loop { break unless plan_next_page(backfill_run, scope) }

      # An empty scope yields no batches, so no DripperChild will ever run to
      # settle this run, and children that finished while we were still
      # planning could not settle it either (see BackfillRun#planning?).
      # Finalizing here completes it in both cases; when batches are still
      # active this is a no-op and the children settle the run as usual.
      backfill_run.finalize_if_batches_finished!
    rescue StandardError => e
      backfill_run.failed!
      backfill_run.update!(error_message: e.message)
      raise e
    end

    private

    # Plans the next page of batches and commits them, so their children are
    # enqueued (after_commit) while planning continues. Returns whether there
    # may be more to plan.
    #
    # The run row is locked for the page and the cursor is read back from the
    # batches already committed, so a crashed planner's retry resumes where it
    # stopped and two concurrent deliveries never plan the same ids twice.
    def plan_next_page(backfill_run, scope)
      more = false

      backfill_run.with_lock do
        # Another delivery finished planning, or the run was stopped/failed.
        next unless backfill_run.planning?

        planned = backfill_run.batches
        limit = page_size(backfill_run, planned)
        ids = limit.zero? ? [] : next_ids(scope, planned.maximum(:finish_id), limit)

        ids.uniq.each_slice(backfill_run.batch_size) do |slice|
          BackfillRunBatch.create!(
            backfill_run: backfill_run,
            status: :pending,
            batch_size: slice.size,
            start_id: slice.first,
            finish_id: slice.last
          )
        end

        more = ids.size == limit && limit.positive?
        # total_count is the exact number of planned records; writing it marks
        # planning as finished.
        backfill_run.update!(total_count: planned.sum(:batch_size)) unless more
      end

      more
    end

    # A whole number of batches, capped by what is left of amount_of_elements.
    def page_size(backfill_run, planned)
      batch_size = backfill_run.batch_size
      size = [ PLANNING_PAGE_SIZE / batch_size, 1 ].max * batch_size

      amount = backfill_run.amount_of_elements
      return size unless amount.present? && amount.positive?

      [ size, amount - planned.sum(:batch_size) ].min.clamp(0, size)
    end

    # Keyset pagination over the scope's primary key: only ids are read, and
    # the scope's own filters decide which ones make it into a batch, so
    # batches never span empty id ranges and sizes stay exact.
    def next_ids(scope, cursor, limit)
      primary_key = scope.arel_table[scope.primary_key]
      relation = scope.reorder(primary_key.asc).limit(limit)
      relation = relation.where(primary_key.gt(cursor)) if cursor
      relation.pluck(primary_key)
    end
  end
end
