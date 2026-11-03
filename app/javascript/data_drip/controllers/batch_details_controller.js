import { Controller } from "@hotwired/stimulus"

// Attached to the batches <table>; remembers which batch backtrace/output
// panels the user opened or closed, and how far they scrolled each one, and
// reapplies that after the polling controller re-renders the tbody (which
// would otherwise reset every panel to its server-rendered default while the
// user is reading it).
export default class extends Controller {
  connect() {
    this.openState = new Map()
    this.scrollState = new Map()
  }

  remember(event) {
    const details = event.currentTarget
    if (details.id) this.openState.set(details.id, details.open)
  }

  capture() {
    this.scrollState.clear()
    this.element.querySelectorAll("details[id] pre").forEach((pre) => {
      const id = pre.closest("details").id
      if (pre.scrollTop || pre.scrollLeft) this.scrollState.set(id, [pre.scrollTop, pre.scrollLeft])
    })
  }

  restore() {
    this.openState.forEach((open, id) => {
      const details = this.element.querySelector(`#${CSS.escape(id)}`)
      if (details) details.open = open
    })
    this.scrollState.forEach(([top, left], id) => {
      const pre = this.element.querySelector(`#${CSS.escape(id)} pre`)
      if (pre) {
        pre.scrollTop = top
        pre.scrollLeft = left
      }
    })
  }
}
