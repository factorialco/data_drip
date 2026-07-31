# frozen_string_literal: true

module DataDrip
  class ScriptRun < ApplicationRecord
    self.table_name = "data_drip_script_runs"

    include DataDrip::MultiCellRun

    validates :script_class_name, presence: true
    validate :script_class_exists
    validate :script_class_properly_configured?
    validate :validate_inputs, on: :create
    validate :start_at_must_be_valid_datetime
    validates :start_at, presence: true

    before_validation :default_start_at, on: :create

    after_commit :enqueue
    after_commit :run_hooks

    DataDrip.cross_rails_enum(
      self,
      :status,
      %i[pending enqueued running completed failed]
    )

    # `output` is a MEDIUMTEXT column (16MB) but a runaway script can still
    # outgrow it, and every appended line rewrites the whole blob — so a log
    # that big is slow long before the database complains. Keep the first
    # OUTPUT_LIMIT bytes and replace the rest with a single notice.
    OUTPUT_LIMIT = 1.megabyte
    TRUNCATION_NOTICE = "[output truncated: reached the #{OUTPUT_LIMIT} byte limit]\n"

    # Still safe to delete: the run has not started executing yet. Once it is
    # running or terminal we keep it as history and no longer allow deletion.
    def not_yet_run?
      pending? || enqueued?
    end

    # Whether the given backfiller owns this run. Actions (delete) are
    # restricted to the run's own author.
    def owned_by?(backfiller)
      backfiller.present? && backfiller_id == backfiller.id
    end

    def script_class
      @script_class ||=
        DataDrip.scripts.find { |klass| klass.name == script_class_name }
    end

    def enqueue
      return unless pending?

      # The transition MUST commit before the job is enqueued. A worker can pick
      # the job up the instant it is visible, and ScriptRunner starts work immediately,
      # so enqueueing first leaves a window where the job sees the stale state.
      enqueued!
      DataDrip::ScriptRunner.set(wait_until: start_at).perform_later(self)
    end

    def append_output(line)
      current = output.to_s
      return if current.end_with?(TRUNCATION_NOTICE)

      appended = "#{current}#{line}\n"
      if appended.bytesize > OUTPUT_LIMIT
        appended = "#{current}#{TRUNCATION_NOTICE}"
      end

      update_column(:output, appended)
    end

    private

    def default_start_at
      self.start_at ||= Time.current
    end

    def run_hooks
      return unless status_previously_changed?

      hook_name = "on_script_run_#{status}"
      if script_class.respond_to?(hook_name)
        script_class.send(hook_name, self)
      elsif DataDrip.hooks_handler_class.present? && DataDrip.hooks_handler_class.respond_to?(hook_name)
        DataDrip.hooks_handler_class.send(hook_name, self)
      end
    end

    def script_class_exists
      return if script_class

      errors.add(:script_class_name, "must be a valid DataDrip script class")
    end

    def script_class_properly_configured?
      return unless script_class

      return if script_class < DataDrip::Script

      errors.add(:script_class_name, "must inherit from DataDrip::Script")
    end

    def validate_inputs
      return unless script_class

      begin
        inputs_object = script_class.inputs_class.new(inputs || {})
        return if inputs_object.valid?

        inputs_object.errors.each do |error|
          errors.add(:inputs, "#{error.attribute} #{error.message}")
        end
      rescue ActiveModel::UnknownAttributeError => e
        errors.add(:inputs, "contains unknown attributes: #{e.message}")
      end
    end

    def start_at_must_be_valid_datetime
      DateTime.parse(start_at.to_s)
    rescue ArgumentError, TypeError
      errors.add(:start_at, "must be a valid datetime")
    end
  end
end
