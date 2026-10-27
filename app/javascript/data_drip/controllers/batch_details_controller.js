import { Controller } from "@hotwired/stimulus"

// Attached to the batches <table>; remembers which batch backtrace/output
// panels the user opened or closed, and reapplies that after the polling
// controller re-renders the tbody (which would otherwise reset every panel to
// its server-rendered default while the user is reading it).
export default class extends Controller {
  connect() {
    this.openState = new Map()
  }

  remember(event) {
    const details = event.currentTarget
    if (details.id) this.openState.set(details.id, details.open)
  }

  restore() {
    this.openState.forEach((open, id) => {
      const details = this.element.querySelector(`#${CSS.escape(id)}`)
      if (details) details.open = open
    })
  }
}
