import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "processedCount", "totalCount", "batchesTable"]
  static values = {
    backfillRunId: Number
  }

  connect() {
    this.startSSE()
  }

  disconnect() {
    this.stopSSE()
  }

  startSSE() {
    try {
      this.eventSource = new EventSource(`/data_drip/backfill_runs/${this.backfillRunIdValue}/stream`)

      this.eventSource.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data)

          if (data.error) {
            console.error("SSE error:", data.error)
            return
          }

          this.updateUI(data)

          if (data.status === 'completed' || data.status === 'failed' || data.status === 'stopped') {
            console.log(`Backfill ${data.status}, stopping SSE`)
            this.stopSSE()
          }
        } catch (error) {
          console.error("Error parsing SSE data:", error)
        }
      }

      this.eventSource.onerror = (error) => {
        console.error("SSE connection error:", error)
      }
    } catch (error) {
      console.error("Error starting SSE:", error)
    }
  }

  stopSSE() {
    if (this.eventSource) {
      this.eventSource.close()
      this.eventSource = null
    }
  }

  updateUI(data) {
    if (this.hasStatusTarget) {
      this.statusTarget.innerHTML = data.status_html
    }

    if (this.hasProcessedCountTarget) {
      this.processedCountTarget.textContent = data.processed_count
    }

    if (this.hasTotalCountTarget) {
      this.totalCountTarget.textContent = data.total_count
    }

    if (this.hasBatchesTableTarget) {
      this.batchesTableTarget.innerHTML = data.batches_html
    }
  }
}
