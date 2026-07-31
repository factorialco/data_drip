# frozen_string_literal: true

module DataDrip
  # Shared multi-cell behavior for BackfillRun and ScriptRun.
  #
  # A run belongs to a "group" (group_uuid) when it was created as part of a
  # multi-cell fan-out: the cell whose UI created it holds the `local` run and
  # one CellDispatch per remote cell; each remote cell holds a `remote` run
  # created through the Cell API. Legacy/single-cell runs have a nil group_uuid
  # and behave exactly as before.
  module MultiCellRun
    extend ActiveSupport::Concern

    DELETED_BACKFILLER_LABEL = "Deleted user"

    included do
      belongs_to :backfiller, class_name: DataDrip.backfiller_class, optional: true

      DataDrip.cross_rails_enum(self, :origin, %i[local remote])

      validates :backfiller_id, presence: true
      # `remote` runs store the coordinator's backfiller_id verbatim: ids are
      # assumed globally unique across cells, but the record itself only exists
      # in the coordinator's cell. Only `local` runs require a resolvable one.
      validate :backfiller_must_exist_locally, if: :local?

      before_validation :assign_current_cell, on: :create
      before_create :capture_backfiller_name
    end

    # backfiller_name is snapshotted onto the row at creation so it survives
    # the backfiller being deleted (or, for remote runs, never existing in this
    # cell's database). Use this for display: it falls back to the live
    # association (for rows created before the column existed), then a
    # placeholder.
    def backfiller_display_name
      backfiller_name.presence ||
        backfiller&.send(DataDrip.backfiller_name_attribute.to_sym) ||
        DELETED_BACKFILLER_LABEL
    end

    # The coordinator's per-cell dispatch records for this run's group.
    def dispatches
      return DataDrip::CellDispatch.none if group_uuid.blank?

      DataDrip::CellDispatch.where(group_uuid: group_uuid).order(:cell_id)
    end

    # Whether this run is the coordinator of a fan-out to other cells.
    def multi_cell_group?
      local? && group_uuid.present? && dispatches.exists?
    end

    private

    def assign_current_cell
      self.cell_id ||= DataDrip.resolved_current_cell_id
    end

    # Snapshot the backfiller's display name so it survives the record's
    # deletion. Remote runs arrive with the name already filled in by the
    # coordinator — keep it.
    def capture_backfiller_name
      return if backfiller_name.present?

      self.backfiller_name =
        backfiller&.send(DataDrip.backfiller_name_attribute.to_sym)
    end

    def backfiller_must_exist_locally
      return if backfiller_id.blank?
      return if backfiller.present?

      errors.add(:backfiller, "must exist")
    end
  end
end
