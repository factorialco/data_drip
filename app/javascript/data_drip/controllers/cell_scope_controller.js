import { Controller } from "@hotwired/stimulus"

// Shows the cell list only while "Run this in multiple cells" is ticked.
// Disabled checkboxes are not submitted, so an unticked form sends no
// target_cell_ids at all.
export default class extends Controller {
  static targets = ["cells", "checkbox"]

  toggle(event) {
    const enabled = event.target.checked

    this.cellsTarget.hidden = !enabled
    this.checkboxTargets.forEach((box) => {
      box.disabled = !enabled
    })
  }
}
