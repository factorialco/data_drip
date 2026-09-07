import { Controller } from "@hotwired/stimulus"

// Polls the run's `updates` endpoint while anything in its group may still
// change, and swaps in the server-rendered fragments.
//
// Each poll is scheduled only after the previous one answers. A multi-cell
// group's `updates` fans out to the other cells, so a response can take as long
// as that fan-out's deadline — on a fixed interval the requests would overlap
// and pile up, each holding a web worker and a socket per cell.
export default class extends Controller {
  static targets = ["status", "output", "errorSection", "errorMessage", "errorBacktrace", "startedAt", "finishedAt", "cells"]
  static values = {
    url: String,
    status: String,
    active: { type: Boolean, default: false },
    interval: { type: Number, default: 3000 }
  }

  connect() {
    if (this.activeValue) this.#schedule()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  #schedule() {
    this.timer = setTimeout(() => this.#poll(), this.intervalValue)
  }

  async #poll() {
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) {
        this.#schedule()
        return
      }

      const data = await response.json()
      this.#render(data)
      this.statusValue = data.status
      if (data.active) this.#schedule()
    } catch {
      this.#schedule()
    }
  }

  #render(data) {
    if (this.hasStatusTarget) this.statusTarget.innerHTML = data.status_html
    if (this.hasCellsTarget && data.cells_html) this.cellsTarget.innerHTML = data.cells_html
    if (this.hasOutputTarget) this.outputTarget.textContent = data.output
    if (this.hasStartedAtTarget) this.startedAtTarget.textContent = data.started_at
    if (this.hasFinishedAtTarget) this.finishedAtTarget.textContent = data.finished_at

    if (data.status === "failed") {
      if (this.hasErrorSectionTarget) this.errorSectionTarget.classList.remove("hidden")
      if (this.hasErrorMessageTarget) this.errorMessageTarget.textContent = data.error_message
      if (this.hasErrorBacktraceTarget) this.errorBacktraceTarget.textContent = data.error_backtrace
    }
  }
}
