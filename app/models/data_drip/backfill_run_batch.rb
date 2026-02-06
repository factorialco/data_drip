# frozen_string_literal: true

module DataDrip
  class BackfillRunBatch < ApplicationRecord
    include DataDrip::Hookable

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

    after_commit :enqueue, on: :create
    after_commit :run_status_change_hooks

    def enqueue
      return unless pending?

      with_action_hooks(:enqueued) do
        DataDrip::DripperChild.perform_later(self)
        enqueued!
      end
    end

    def run!
      with_action_hooks(:running) do
        running!
        migration =
          backfill_run.backfill_class.new(
            batch_size: batch_size,
            sleep_time: 5,
            backfill_options: backfill_run.options
          )

        migration
          .scope
          .in_batches(
            of: batch_size,
            start: start_id,
            finish: finish_id
          ) do |batch|
            migration.send(:process_batch, batch)
            sleep 5
          end
      end
    end

    private

    def hook_target_for(hook_name)
      backfill_class = backfill_run.backfill_class
      return backfill_class if backfill_class.respond_to?(hook_name)

      handler = DataDrip.hooks_handler_class
      return handler if handler&.respond_to?(hook_name)

      nil
    end

    def hook_prefix
      "batch"
    end
  end
end
