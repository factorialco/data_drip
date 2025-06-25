module DataDrip
  class BackfillRun < ApplicationRecord
    self.table_name = "data_drip_backfill_runs"

    has_many :batches, class_name: "DataDrip::BackfillRunBatch", dependent: :destroy

    validates :backfill_class_name, presence: true
    validate :backfill_class_exists
    validate :backfill_class_properly_configured?
    validate :validate_scope, on: :create
    validate :start_at_must_be_valid_datetime
    validates :start_at, presence: true
    validates :batch_size, presence: true, numericality: { greater_than: 0 }

    after_commit :enqueue

    enum :status, %i[pending enqueued running completed failed], validate: true, default: :pending

    def backfill_class
      @backfill_class ||= DataDrip.all.find { |klass| klass.name == backfill_class_name }
    end

    def enqueue
      return unless pending?

      DataDrip::Dripper.set(wait_until: start_at).perform_later(self)
      enqueued!
    end

    private

    def backfill_class_exists
      return if backfill_class

      errors.add(:backfill_class_name, "must be a valid DataDrip backfill class")
    end

    def backfill_class_properly_configured?
      return unless backfill_class

      return if backfill_class < DataDrip::Backfill

      errors.add(:backfill_class_name, "must inherit from DataDrip::Backfill")
    end

    def validate_scope
      return unless backfill_class

      backfill = backfill_class.new
      scope = backfill.scope
      return unless scope.count.zero?

      errors.add(:backfill_class_name, "No records to process for #{backfill_class.name}. No jobs enqueued.")
    end

    def start_at_must_be_valid_datetime
      DateTime.parse(start_at.to_s)
    rescue ArgumentError, TypeError
      errors.add(:start_at, "must be a valid datetime")
    end
  end
end
