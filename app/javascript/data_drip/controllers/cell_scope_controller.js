import { Controller } from "@hotwired/stimulus"

// Shows the per-cell checkbox list only when "Choose cells…" is picked.
// Disabled checkboxes are not submitted, so "All cells" / "Only this cell"
// submit no target_cell_ids and the server derives the list from cell_scope.
export default class extends Controller {
  static targets = ["custom", "checkbox"]

  toggle(event) {
    const custom = event.target.value === "custom"

    this.customTarget.hidden = !custom
    this.checkboxTargets.forEach((box) => {
      box.disabled = !custom
    })
  }
}
