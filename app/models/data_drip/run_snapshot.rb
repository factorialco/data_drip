# frozen_string_literal: true

module DataDrip
  # JSON-friendly status snapshot of a run, served by the Cell API and rendered
  # on the coordinator's per-cell cards. String keys throughout: the coordinator
  # consumes these snapshots parsed from JSON, so local and remote snapshots
  # must look identical.
  module RunSnapshot
    module_function

    # How much of a script's log a snapshot carries. Snapshots travel once per
    # cell per refresh, so shipping the whole log (which `ScriptRun::OUTPUT_LIMIT`
    # caps at a megabyte) would be a lot of traffic for a card that shows a short
    # scrollback and links into the owning cell for the rest.
    def output_tail_bytes
      DataDrip.resolve_setting(DataDrip.script_output_tail_bytes).to_i
    end

    def for(run)
      run.is_a?(DataDrip::ScriptRun) ? script(run) : backfill(run)
    end

    def backfill(run)
      {
        "id" => run.id,
        "type" => "backfill",
        "class_name" => run.backfill_class_name,
        "status" => run.status,
        "terminal" => run.terminal?,
        "progress_percent" => run.progress_percent,
        "processed_count" => run.processed_count,
        "total_count" => run.total_count,
        "throughput_per_minute" => run.throughput_per_minute&.round(1),
        "eta_seconds" => run.eta_seconds&.round,
        "error_message" => run.error_message,
        "failed_batches_count" => run.batches.failed.count,
        "backfiller_id" => run.backfiller_id,
        "not_yet_run" => run.not_yet_run?,
        "created_at" => run.created_at&.utc&.iso8601,
        "start_at" => run.start_at&.utc&.iso8601,
        "updated_at" => run.updated_at&.utc&.iso8601
      }
    end

    def script(run)
      {
        "id" => run.id,
        "type" => "script",
        "class_name" => run.script_class_name,
        "status" => run.status,
        "terminal" => run.completed? || run.failed?,
        "output_tail" => output_tail(run.output),
        "output_truncated" => run.output.to_s.bytesize > output_tail_bytes,
        "error_message" => run.error_message,
        "error_backtrace" => run.error_backtrace,
        "backfiller_id" => run.backfiller_id,
        "not_yet_run" => run.not_yet_run?,
        "created_at" => run.created_at&.utc&.iso8601,
        "start_at" => run.start_at&.utc&.iso8601,
        "started_at" => run.started_at&.utc&.iso8601,
        "finished_at" => run.finished_at&.utc&.iso8601,
        "updated_at" => run.updated_at&.utc&.iso8601
      }
    end

    def output_tail(output)
      text = output.to_s
      limit = output_tail_bytes
      return text if text.bytesize <= limit

      # Cut on a byte boundary, then drop the (possibly partial) first line so
      # the tail always starts mid-log at a readable place.
      tail = text.byteslice(-limit, limit).to_s
      tail = tail.scrub("")
      tail.split("\n", 2).last.to_s
    end
  end
end
