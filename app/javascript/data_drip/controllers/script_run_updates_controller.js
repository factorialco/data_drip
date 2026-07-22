import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "output", "errorSection", "errorMessage", "errorBacktrace", "startedAt", "finishedAt"]
  static values = {
    url: String,
    status: String
  }

  connect() {
    if (this.isTerminal(this.statusValue)) return

    this.poller = setInterval(() => this.poll(), 3000)
  }

  disconnect() {
    this.stopPolling()
  }

  isTerminal(status) {
    return status === "completed" || status === "failed"
  }

  stopPolling() {
    if (this.poller) {
      clearInterval(this.poller)
      this.poller = null
    }
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) return

      const data = await response.json()
      this.updateUI(data)

      if (this.isTerminal(data.status)) {
        this.stopPolling()
      }
    } catch (error) {
      console.error("Error polling script run updates:", error)
    }
  }

  updateUI(data) {
    if (this.hasStatusTarget) {
      this.statusTarget.innerHTML = data.status_html
    }

    if (this.hasOutputTarget) {
      this.outputTarget.textContent = data.output
    }

    if (this.hasStartedAtTarget) {
      this.startedAtTarget.textContent = data.started_at
    }

    if (this.hasFinishedAtTarget) {
      this.finishedAtTarget.textContent = data.finished_at
    }

    if (data.status === "failed") {
      if (this.hasErrorSectionTarget) {
        this.errorSectionTarget.classList.remove("hidden")
      }
      if (this.hasErrorMessageTarget) {
        this.errorMessageTarget.textContent = data.error_message
      }
      if (this.hasErrorBacktraceTarget) {
        this.errorBacktraceTarget.textContent = data.error_backtrace
      }
    }
  }
}
