import { Controller } from "@hotwired/stimulus"

// Polls the run's `updates` endpoint while it is active and swaps in the
// server-rendered fragments (status badge, progress hero, batches table).
export default class extends Controller {
  static targets = ["status", "progress", "batchesTable", "batchesMeta"]
  static values = {
    url: String,
    status: String,
    interval: { type: Number, default: 3000 }
  }

  connect() {
    // When the user paginated or filtered the batches table, leave it alone —
    // the updates payload always contains the first, unfiltered page.
    const params = new URLSearchParams(window.location.search)
    this.skipBatches = Boolean(params.get("batch_page") || params.get("batch_status"))

    if (this.#active()) this.#schedule()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  #active() {
    return ["pending", "enqueued", "running"].includes(this.statusValue)
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
      if (!data.terminal) this.#schedule()
    } catch {
      this.#schedule()
    }
  }

  #render(data) {
    if (this.hasStatusTarget) this.statusTarget.innerHTML = data.status_html
    if (this.hasProgressTarget) this.progressTarget.innerHTML = data.progress_html

    if (this.skipBatches) return

    if (this.hasBatchesMetaTarget) this.batchesMetaTarget.innerHTML = data.batches_meta_html
    if (this.hasBatchesTableTarget) this.batchesTableTarget.innerHTML = data.batches_html
  }
}
