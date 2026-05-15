## [Unreleased]

### Fixed
- Boolean option checkboxes now submit an explicit `"0"` when unchecked. Previously, an unchecked checkbox dropped the key from the form params entirely, causing the attribute's `default:` to silently re-apply server-side. Pairs the `check_box_tag` with a `hidden_field_tag` (the same idiom Rails' `form.check_box` uses internally).

## [0.1.0] - 2025-05-05

- Initial release
