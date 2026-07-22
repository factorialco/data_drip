# frozen_string_literal: true

module DataDrip
  class BackfillRun < ApplicationRecord
    self.table_name = "data_drip_backfill_runs"

    has_many :batches,
             class_name: "DataDrip::BackfillRunBatch",
             dependent: :destroy
    belongs_to :backfiller, class_name: DataDrip.backfiller_class

    validates :backfill_class_name, presence: true
    validate :backfill_class_exists
    validate :backfill_class_properly_configured?
    validate :validate_scope, on: :create
    validate :start_at_must_be_valid_datetime
    validates :start_at, presence: true
    validates :batch_size, presence: true, numericality: { greater_than: 0 }
    validates :amount_of_elements,
              numericality: {
                greater_than_or_equal_to: 0
              },
              allow_nil: true

    after_commit :enqueue
    after_commit :run_hooks

    DataDrip.cross_rails_enum(
      self,
      :status,
      %i[pending enqueued running completed failed stopped]
    )

    def backfiller_name
      @backfiller_name ||=
        backfiller.send(DataDrip.backfiller_name_attribute.to_sym)
    end

    def terminal?
      completed? || failed? || stopped?
    end

    def progress_percent
      return 100 if completed?
      return 0 if total_count.to_i.zero?

      [ (processed_count.to_f / total_count) * 100, 100 ].min.floor
    end

    # When the first batch was created, i.e. when processing actually began
    # (start_at is only when the run was scheduled to be picked up).
    def processing_started_at
      @processing_started_at ||= batches.minimum(:created_at)
    end

    def last_activity_at
      @last_activity_at ||= batches.maximum(:updated_at)
    end

    def elapsed_seconds
      return nil unless processing_started_at

      reference = terminal? ? (last_activity_at || updated_at) : Time.current
      (reference - processing_started_at).to_f
    end

    def throughput_per_minute
      elapsed = elapsed_seconds
      return nil if elapsed.nil? || elapsed < 1 || processed_count.to_i.zero?

      processed_count * 60.0 / elapsed
    end

    def eta_seconds
      return nil unless running? && total_count.to_i.positive?

      rate = throughput_per_minute
      return nil unless rate

      remaining = total_count - processed_count
      return nil if remaining.negative?

      remaining * 60.0 / rate
    end

    def backfill_class
      @backfill_class ||=
        DataDrip.all.find { |klass| klass.name == backfill_class_name }
    end

    def enqueue
      return unless pending?

      DataDrip::Dripper.set(wait_until: start_at).perform_later(self)
      enqueued!
    end

    private

    def run_hooks
      return unless status_previously_changed?

      hook_name = "on_run_#{status}"
      if backfill_class.respond_to?(hook_name)
        backfill_class.send(hook_name, self)
      elsif DataDrip.hooks_handler_class.present? && DataDrip.hooks_handler_class.respond_to?(hook_name)
        DataDrip.hooks_handler_class.send(hook_name, self)
      end
    end

    def backfill_class_exists
      return if backfill_class

      errors.add(
        :backfill_class_name,
        "must be a valid DataDrip backfill class"
      )
    end

    def backfill_class_properly_configured?
      return unless backfill_class

      return if backfill_class < DataDrip::Backfill

      errors.add(:backfill_class_name, "must inherit from DataDrip::Backfill")
    end

    def validate_scope
      return unless backfill_class_name.present?
      return unless backfill_class

      begin
        backfill =
          backfill_class.new(
            batch_size: batch_size || 100,
            sleep_time: 5,
            backfill_options: options || {}
          )
        scope = backfill.scope

        scope =
          scope.limit(amount_of_elements) if amount_of_elements.present? &&
          amount_of_elements.positive?

        final_count = scope.count
        return unless final_count.zero?

        errors.add(
          :base,
          "No records to process with the current configuration. Please adjust your options or select a different backfill class."
        )
      rescue ActiveModel::UnknownAttributeError => e
        errors.add(:options, "contains unknown attributes: #{e.message}")
      end
    end

    def start_at_must_be_valid_datetime
      DateTime.parse(start_at.to_s)
    rescue ArgumentError, TypeError
      errors.add(:start_at, "must be a valid datetime")
    end
  end
end
