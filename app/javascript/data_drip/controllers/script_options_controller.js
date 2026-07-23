import { Controller } from "@hotwired/stimulus"

// Fetches the per-script input fields when the script class changes.
// The returned HTML contains its own Stimulus controllers (enum-select),
// which connect automatically once inserted.
export default class extends Controller {
  static targets = ["container"]
  static values = { url: String }

  async refresh(event) {
    const className = event.target.value.trim()

    if (!className) {
      this.containerTarget.innerHTML = ""
      return
    }

    try {
      const url = `${this.urlValue}?script_class_name=${encodeURIComponent(className)}`
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return

      const data = await response.json()
      this.containerTarget.innerHTML = data.html || ""
    } catch {
      // Leave the previous inputs in place; validation catches bad classes.
    }
  }
}
