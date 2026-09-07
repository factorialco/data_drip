## [Unreleased]

### Added
- **Multi-cell support** (opt-in): the same backfill or script can be triggered once and executed in every cell of a multi-deployment ("cell") architecture. The creating cell coordinates: it stores one dispatch record per target cell, delivers each over HTTPS to that cell's new machine-to-machine **Cell API** (`DataDrip::CellApi::Engine`, bearer-token auth, idempotent per `(group_uuid, cell_id)`), and its show page renders live per-cell cards (status, progress, errors, script output) fetched from each cell. Includes cell targeting on the new-run forms ("All cells / Only this cell / Choose cells…"), fan-out of stop/delete actions, per-cell retry of failed batches, a "Retry dispatch" flow for rejected deliveries, and origin badges in the run lists. A run's reported status is the group's worst-of status, cross-cell fan-out is concurrent under one shared deadline, and per-cell statuses are cached on the dispatch records and refreshed by a background job — so the coordinator's pages render from cache and never make a cross-cell call (or a write) while serving a request. Tunable via `cell_fanout_concurrency`, `cell_fanout_deadline`, `cell_status_refresh_interval` and `script_output_tail_bytes`. Configured via `DataDrip.current_cell_id`, `cell_ids`, `cell_transport`, `cell_api_tokens`, and optional `cell_ui_url`; with the defaults nothing changes. Existing installs add the new columns and the `data_drip_cell_dispatches` table with `rails generate data_drip:add_multi_cell`.
- Backfill options can be declared as mandatory with `attribute :name, :string, required: true`. The form marks required fields and the server rejects runs with blank required options (also guarding `scope` from running with missing options).
- Full UI redesign: slim header shell (replaces the empty sidebar), stats strip, tabbed runs list with class-name search and status filter, progress bars, relative timestamps, empty states, and dark mode support (follows the OS preference).
- Run detail page now shows a live progress hero (percent, throughput, estimated time remaining, elapsed) that auto-refreshes while the run is active, plus a metadata panel with the run's options.
- Per-batch errors are collapsible in the batches table, and a new **Retry failed batches** action re-enqueues only the failed batches (`POST :retry_failed_batches`).
- Runs created without a start time now run immediately; the form offers an explicit "Run immediately / Schedule for later" choice.
- `rake data_drip:css` compiles the engine's Tailwind CSS; CI verifies the checked-in `tailwind.css` is up to date.

### Changed
- Status badges, buttons, and option inputs are now styled with Tailwind utilities (no inline styles) and meet WCAG contrast.
- All inline `<script>` blocks were replaced with Stimulus controllers (timezone sync, class combobox, dynamic options, enum multi-select, live updates via polling).
- Failure responses from `POST /backfill_runs` now return HTTP 422 instead of 200.

### Removed
- The unused SSE `GET :stream` endpoint (live updates now poll the existing `updates` endpoint).

### Fixed
- Scripts that log a lot no longer die mid-run with `Mysql2::Error: Data too long for column 'output'`. The `data_drip_script_runs.output` column is created as `MEDIUMTEXT` on MySQL (`limit: 1.megabyte`; ignored by PostgreSQL and SQLite), and `rails generate data_drip:widen_script_run_output` migrates existing installs. `ScriptRun#append_output` also caps a run's log at 1MB — every line rewrites the whole blob, so a log that big is slow long before the database complains — and ends it with a truncation notice instead of raising.
- A run whose scope matches no records now completes instead of hanging in `running` forever. With an empty scope the dripper creates no batches, and since only `DripperChild` settled a run to a terminal state, nothing ever finished it — leaving a zombie run that also blocked any later identical run (the duplicate-run guard treats `running` as active) and could not be deleted. The dripper now finalizes the run itself once batches are created. The dripper also derives `total_count` from the batch sizes it already plucked instead of issuing a second `scope.count`.
- Large option/input values on the run detail pages no longer stretch the page sideways: the values wrap and the block scrolls past `max-h-64`.
- The runs list search field keeps focus (and the caret position) when the debounced filter refreshes the results. The form lives inside the Turbo Frame it navigates, so each submit replaced the very input being typed into; the `autosubmit` controller now restores focus, caret, and any keystroke that landed while the request was in flight.
- Boolean option checkboxes now submit an explicit `"0"` when unchecked. Previously, an unchecked checkbox dropped the key from the form params entirely, causing the attribute's `default:` to silently re-apply server-side. Pairs the `check_box_tag` with a `hidden_field_tag` (the same idiom Rails' `form.check_box` uses internally).

## [0.1.0] - 2025-05-05

- Initial release
