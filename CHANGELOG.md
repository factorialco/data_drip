## [Unreleased]

### Added
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
- Boolean option checkboxes now submit an explicit `"0"` when unchecked. Previously, an unchecked checkbox dropped the key from the form params entirely, causing the attribute's `default:` to silently re-apply server-side. Pairs the `check_box_tag` with a `hidden_field_tag` (the same idiom Rails' `form.check_box` uses internally).

## [0.1.0] - 2025-05-05

- Initial release
