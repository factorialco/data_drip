# frozen_string_literal: true

module DataDrip
  class BackfillRun < ApplicationRecord
    include DataDrip::Hookable

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
    after_commit :run_status_change_hooks

    DataDrip.cross_rails_enum(
      self,
      :status,
      %i[pending enqueued running completed failed stopped]
    )

    def pending!(*args, &block)
      with_action_hooks(:pending) { super(*args, &block) }
    end

    def enqueued!(*args, &block)
      with_action_hooks(:enqueued) { super(*args, &block) }
    end

    def running!(*args, &block)
      with_action_hooks(:running) { super(*args, &block) }
    end

    def completed!(*args, &block)
      with_action_hooks(:completed) { super(*args, &block) }
    end

    def failed!(*args, &block)
      with_action_hooks(:failed) { super(*args, &block) }
    end

    def stopped!(*args, &block)
      with_action_hooks(:stopped) { super(*args, &block) }
    end

    def backfiller_name
      @backfiller_name ||=
        backfiller.send(DataDrip.backfiller_name_attribute.to_sym)
    end

    def backfill_class
      @backfill_class ||=
        DataDrip.all.find { |klass| klass.name == backfill_class_name }
    end

    def enqueue
      return unless pending?

      with_action_hooks(:enqueued) do
        DataDrip::Dripper.set(wait_until: start_at).perform_later(self)
        enqueued!
      end
    end

    def with_run_hooks(status_value)
      with_action_hooks(status_value) { yield }
    end

    private

    def hook_target_for(hook_name)
      return backfill_class if backfill_class.respond_to?(hook_name)

      handler = DataDrip.hooks_handler_class
      return handler if handler&.respond_to?(hook_name)

      nil
    end

    def hook_prefix
      "run"
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
