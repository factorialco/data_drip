# frozen_string_literal: true

module DataDrip
  class ScriptRun < ApplicationRecord
    self.table_name = "data_drip_script_runs"

    belongs_to :backfiller, class_name: DataDrip.backfiller_class

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

    def backfiller_name
      @backfiller_name ||=
        backfiller.send(DataDrip.backfiller_name_attribute.to_sym)
    end

    def script_class
      @script_class ||=
        DataDrip.scripts.find { |klass| klass.name == script_class_name }
    end

    def enqueue
      return unless pending?

      DataDrip::ScriptRunner.set(wait_until: start_at).perform_later(self)
      enqueued!
    end

    def append_output(line)
      update_column(:output, "#{output}#{line}\n")
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
