import { Controller } from "@hotwired/stimulus"
import { renderInstructions } from "markdown"

// Drives the "New Backfill Run" form:
//   - captures the browser timezone into a hidden field
//   - when a backfill class is picked, fetches its option inputs + instructions
//     and renders them
//   - disables the submit button while the form is being submitted
export default class extends Controller {
  static targets = ["classInput", "optionsContainer", "instructionsContainer", "timezone", "submit"]
  static values = { optionsUrl: String }

  connect() {
    if (this.hasTimezoneTarget) {
      this.timezoneTarget.value = Intl.DateTimeFormat().resolvedOptions().timeZone
    }
  }

  classChanged() {
    const selectedClass = this.classInputTarget.value

    this.optionsContainerTarget.innerHTML = ""
    if (this.hasInstructionsContainerTarget) this.instructionsContainerTarget.innerHTML = ""

    if (!selectedClass || selectedClass === "Select a backfill class") return

    fetch(`${this.optionsUrlValue}?backfill_class_name=${encodeURIComponent(selectedClass)}`, {
      method: "GET",
      headers: {
        Accept: "application/json",
        "X-Requested-With": "XMLHttpRequest",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
      }
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Network response was not ok: ${response.status}`)
        return response.json()
      })
      .then((data) => {
        if (data.instructions && this.hasInstructionsContainerTarget) {
          this.instructionsContainerTarget.innerHTML =
            '<div style="margin-bottom:24px;padding:16px;border-radius:8px;background:#eff6ff;border:1px solid #bfdbfe">' +
            '<h3 style="font-size:12px;font-weight:600;color:#1d4ed8;margin-bottom:8px;letter-spacing:0.05em">INSTRUCTIONS</h3>' +
            '<div style="color:#374151;font-size:13px;line-height:1.5">' + renderInstructions(data.instructions) + "</div>" +
            "</div>"
        }
        if (data.html) {
          this.optionsContainerTarget.innerHTML = data.html
          this.optionsContainerTarget.querySelectorAll("script").forEach((oldScript) => {
            const newScript = document.createElement("script")
            newScript.textContent = oldScript.textContent
            oldScript.parentNode.replaceChild(newScript, oldScript)
          })
        }
      })
      .catch((error) => {
        console.error("Error fetching backfill options:", error)
      })
  }

  disableSubmit() {
    if (!this.hasSubmitTarget) return
    this.submitTarget.disabled = true
    this.submitTarget.value = "Creating..."
    this.submitTarget.classList.add("opacity-50", "cursor-not-allowed")
  }
}
