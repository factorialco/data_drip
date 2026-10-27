# frozen_string_literal: true

module DataDrip
  class BackfillRunBatch < ApplicationRecord
    self.table_name = "data_drip_backfill_run_batches"

    belongs_to :backfill_run, class_name: "DataDrip::BackfillRun"

    validates :start_id, presence: true
    validates :finish_id, presence: true
    validates :batch_size, presence: true, numericality: { greater_than: 0 }

    DataDrip.cross_rails_enum(
      self,
      :status,
      %i[pending enqueued running completed failed stopped]
    )

    after_commit :enqueue, on: :create
    after_commit :run_hooks

    # `output` is a MEDIUMTEXT column (16MB), as a script run's is, but every
    # logged line rewrites the whole blob, so a log that big is slow long before
    # the database complains. Keep the first OUTPUT_LIMIT bytes and replace the
    # rest with a single notice.
    OUTPUT_LIMIT = 1.megabyte
    TRUNCATION_NOTICE = "[output truncated: reached the #{OUTPUT_LIMIT} byte limit]\n"
    BACKTRACE_LINES = 50

    # Columns added by `rails generate data_drip:add_batch_diagnostics`. Older
    # installs that have not run it keep working, without the extra detail.
    DIAGNOSTIC_COLUMNS = %w[error_class error_backtrace failed_record_id output].freeze

    def enqueue
      return unless pending?
      return unless slot_available?

      # The transition MUST commit before the job is enqueued. A worker can pick
      # the job up the instant it is visible; if it runs the batch to completion
      # first, a trailing `enqueued!` would stomp that terminal state and the
      # parent run, seeing a forever-active batch, would never settle.
      enqueued!
      DataDrip::DripperChild.perform_later(self)
    end

    # With a parallelism limit, a batch is only enqueued while fewer than that
    # many siblings are enqueued or running; DripperChild enqueues the next
    # pending batch when one finishes.
    def slot_available?
      limit = backfill_run.backfill_class&.max_parallel_batches
      return true if limit.nil?

      backfill_run.batches.where(status: %i[enqueued running]).count < limit
    end

    def run!
      running!
      migration =
        backfill_run.backfill_class.new(
          batch_size: batch_size,
          backfill_options: backfill_run.options,
          logger: ->(line) { append_output(line) }
        )

      migration
        .scope
        .in_batches(
          of: batch_size,
          start: start_id,
          finish: finish_id
        ) do |batch|
          migration.send(:process_batch, batch)
          # Throttle between batches using the configured DataDrip.sleep_time
          # (defaults to the migration's sleep_time).
          sleep migration.sleep_time
        end
    rescue StandardError
      @failed_record_id = migration&.current_record_id
      raise
    end

    # Batches are fail-fast: the first error stops the batch, so the records
    # after the failing one are left unprocessed until the batch is retried.
    # Status and diagnostics are written together, so on_batch_failed hooks
    # already see the full error.
    def fail_with!(error)
      update!(
        diagnostic_attributes(
          status: :failed,
          error_message: error.message,
          error_class: error.class.name,
          error_backtrace: error.backtrace&.first(BACKTRACE_LINES)&.join("\n"),
          failed_record_id: @failed_record_id&.to_s
        )
      )
    end

    # Puts a failed batch back in line, clearing what the failed attempt left
    # behind; the retry runs the whole batch again and logs afresh.
    def reset_for_retry!
      update!(
        diagnostic_attributes(
          status: :pending,
          error_message: nil,
          error_class: nil,
          error_backtrace: nil,
          failed_record_id: nil,
          output: nil
        )
      )
    end

    def append_output(line)
      return unless self.class.diagnostics_supported?

      current = output.to_s
      return if current.end_with?(TRUNCATION_NOTICE)

      appended = "#{current}#{line}\n"
      appended = "#{current}#{TRUNCATION_NOTICE}" if appended.bytesize > OUTPUT_LIMIT

      update_column(:output, appended)
    end

    def self.diagnostics_supported?
      (DIAGNOSTIC_COLUMNS - column_names).empty?
    end

    private

    def diagnostic_attributes(attributes)
      return attributes if self.class.diagnostics_supported?

      attributes.except(*DIAGNOSTIC_COLUMNS.map(&:to_sym))
    end

    def run_hooks
      return unless status_previously_changed?

      hook_name = "on_batch_#{status}"
      if backfill_run.backfill_class.respond_to?(hook_name)
        backfill_run.backfill_class.send(hook_name, self)
      elsif DataDrip.hooks_handler_class.present? &&
            DataDrip.hooks_handler_class.respond_to?(hook_name)
        DataDrip.hooks_handler_class.send(hook_name, self)
      end
    end
  end
end
