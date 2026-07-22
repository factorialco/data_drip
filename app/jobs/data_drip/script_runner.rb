# frozen_string_literal: true

module DataDrip
  class ScriptRunner < DataDrip.base_job_class.safe_constantize
    queue_as { DataDrip.script_queue_name }

    def perform(script_run)
      script_run.update!(status: :running, started_at: Time.current)

      script =
        script_run.script_class.new(
          inputs: script_run.inputs || {},
          logger: ->(line) { script_run.append_output(line) }
        )
      script.call

      script_run.update!(status: :completed, finished_at: Time.current)
    rescue StandardError => e
      script_run.update!(
        status: :failed,
        finished_at: Time.current,
        error_message: e.message,
        error_backtrace: e.backtrace&.join("\n")
      )
      raise e
    end
  end
end
