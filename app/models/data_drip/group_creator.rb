# frozen_string_literal: true

module DataDrip
  # Creates the coordinator's local run and records one CellDispatch per target
  # remote cell, each delivered by its own background job. The dispatch payload
  # is frozen here so retries re-send exactly what was originally requested.
  #
  # In single-cell mode (DataDrip.multi_cell? false) this reduces to a plain
  # save of the local run.
  class GroupCreator
    def self.call(run:, remote_cell_ids: [])
      new(run: run, remote_cell_ids: remote_cell_ids).call
    end

    def initialize(run:, remote_cell_ids: [])
      @run = run
      @remote_cell_ids = remote_cell_ids
    end

    # Returns whether the local run was saved (mirroring run.save so the
    # controllers keep their render-on-validation-error flow).
    def call
      if DataDrip.multi_cell?
        @run.group_uuid ||= SecureRandom.uuid
        @run.origin = :local
      end

      dispatches = []

      # The run and the record of where else it must go are one fact: a crash
      # between them would leave a run executing here with no trace that other
      # cells were ever meant to run it. The run's own `after_commit :enqueue`
      # therefore also fires only once the dispatches are durable.
      saved =
        @run.class.transaction do
          raise ActiveRecord::Rollback unless @run.save

          dispatches = create_dispatches if DataDrip.multi_cell?
          true
        end

      return false unless saved

      # Enqueued outside the transaction: a worker must never see a job whose
      # row is not yet committed.
      Array(dispatches).each(&:enqueue)
      true
    end

    private

    def create_dispatches
      # Never dispatch to unknown cells or to ourselves, whatever the form said.
      cells = @remote_cell_ids.map(&:to_s) & DataDrip.remote_cell_ids

      cells.map do |cell_id|
        DataDrip::CellDispatch.create!(
          group_uuid: @run.group_uuid,
          cell_id: cell_id,
          runnable_type: script? ? :script : :backfill,
          status: :pending,
          payload: payload
        )
      end
    end

    def script?
      @run.is_a?(DataDrip::ScriptRun)
    end

    def payload
      @payload ||=
        begin
          base = {
            "group_uuid" => @run.group_uuid,
            "origin_cell_id" => DataDrip.resolved_current_cell_id,
            "start_at" => @run.start_at.utc.iso8601,
            "backfiller_id" => @run.backfiller_id,
            "backfiller_name" => @run.backfiller_name
          }

          if script?
            base.merge(
              "script_class_name" => @run.script_class_name,
              "inputs" => @run.inputs || {}
            )
          else
            base.merge(
              "backfill_class_name" => @run.backfill_class_name,
              "options" => @run.options || {},
              "batch_size" => @run.batch_size,
              "amount_of_elements" => @run.amount_of_elements
            )
          end
        end
    end
  end
end
