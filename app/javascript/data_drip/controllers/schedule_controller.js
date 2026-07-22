import { Controller } from "@hotwired/stimulus"

// Enables the start-at datetime field only when "Schedule for later" is
// picked. A disabled field is not submitted, and a blank start_at means
// "run immediately" on the server.
export default class extends Controller {
  static targets = ["field"]

  toggle(event) {
    const later = event.target.value === "later"

    this.fieldTargets.forEach((field) => {
      field.disabled = !later
    })

    if (later) this.fieldTargets[0]?.focus()
  }
}
