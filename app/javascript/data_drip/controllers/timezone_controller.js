import { Controller } from "@hotwired/stimulus"

// Detects the browser timezone, stores it in the session (so timestamps
// render in local time) and fills any timezone form fields/labels.
export default class extends Controller {
  static targets = ["field", "label"]
  static values = { url: String, current: String }

  connect() {
    this.#syncSession()
  }

  fieldTargetConnected(field) {
    field.value = this.timezone
  }

  labelTargetConnected(label) {
    label.textContent = this.timezone
  }

  get timezone() {
    this._timezone ||= Intl.DateTimeFormat().resolvedOptions().timeZone
    return this._timezone
  }

  #syncSession() {
    if (!this.hasUrlValue || this.currentValue === this.timezone) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({ timezone: this.timezone })
    }).catch(() => {})

    this.currentValue = this.timezone
  }
}
