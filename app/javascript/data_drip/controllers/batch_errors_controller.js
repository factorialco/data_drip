import { Controller } from "@hotwired/stimulus"

// Attached to the batches <table>; toggles the hidden error-detail row that
// follows a failed batch. Lives on the table (not the rows) so it survives
// the tbody being re-rendered by the polling controller.
export default class extends Controller {
  toggle(event) {
    const row = this.element.querySelector(`#batch_error_${event.params.id}`)
    if (!row) return

    row.hidden = !row.hidden
    event.target.textContent = row.hidden ? "Show error" : "Hide error"
    event.target.setAttribute("aria-expanded", String(!row.hidden))
  }
}
