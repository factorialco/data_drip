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
      # `remote` runs store the coordinator's backfiller_id verbatim: the id is
      # meaningful in the coordinator's cell, where the record lives, and is
      # what that cell's Cell API compares its own runs against. Only `local`
      # runs require an id that resolves here. See "Requirements" in the
      # README's multi-cell section on why those ids must not be reused across
      # cells.
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

    # This run together with its remote legs. Ask the group — not the run — for
    # anything that spans cells (status, whether it is still active).
    def group
      @group ||= DataDrip::MultiCellGroup.new(run: self)
    end

    # Whether this run is the coordinator of a fan-out to other cells.
    def multi_cell_group?
      local? && group_uuid.present? && dispatches.exists?
    end

    # Who may stop or delete this run. Ownership decides whenever there is an
    # owner to speak of. A run fanned in from another cell usually has none:
    # backfiller ids identify a record in the coordinator's cell, so nothing
    # here resolves, and requiring ownership would leave the run unstoppable
    # from the only cell that can actually stop it. Reaching this UI already
    # means passing whatever gate the host put in front of DataDrip, so an
    # ownerless run is manageable by any operator who can see it.
    def manageable_by?(backfiller)
      return true if remote? && self.backfiller.nil?

      owned_by?(backfiller)
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
