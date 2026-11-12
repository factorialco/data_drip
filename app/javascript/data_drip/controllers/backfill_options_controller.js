import { Controller } from "@hotwired/stimulus"

// Fetches the per-class option inputs when the backfill class changes, and
// pre-fills the parallel batches limit with the class's own (blank when the
// class has none). The returned HTML contains its own Stimulus controllers
// (enum-select), which connect automatically once inserted.
export default class extends Controller {
  static targets = ["container", "maxParallelBatches"]
  static values = { url: String }

  async refresh(event) {
    const className = event.target.value.trim()

    if (!className) {
      this.containerTarget.innerHTML = ""
      this.#fillMaxParallelBatches(null)
      return
    }

    try {
      const url = `${this.urlValue}?backfill_class_name=${encodeURIComponent(className)}`
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return

      const data = await response.json()
      this.containerTarget.innerHTML = data.html || ""
      // Absent for an unknown class: keep what the field holds.
      if ("max_parallel_batches" in data) this.#fillMaxParallelBatches(data.max_parallel_batches)
    } catch {
      // Leave the previous options in place; validation catches bad classes.
    }
  }

  #fillMaxParallelBatches(value) {
    if (!this.hasMaxParallelBatchesTarget) return

    this.maxParallelBatchesTarget.value = value ?? ""
  }
}
