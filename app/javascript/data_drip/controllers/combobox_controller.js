import { Controller } from "@hotwired/stimulus"

// A small filterable combobox over a server-rendered option list.
// Selecting an option fills the input and dispatches a bubbling "change"
// event so other controllers (backfill-options) can react.
export default class extends Controller {
  static targets = ["input", "list", "option", "empty"]

  open() {
    this.listTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.filter()
  }

  close() {
    this.listTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.#setActive(null)
  }

  focusout(event) {
    if (this.element.contains(event.relatedTarget)) return

    this.close()
  }

  filter() {
    this.listTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")

    const query = this.inputTarget.value.trim().toLowerCase()
    let visible = 0

    this.optionTargets.forEach((option) => {
      const match = !query || option.dataset.value.toLowerCase().includes(query)
      option.classList.toggle("hidden", !match)
      if (match) visible++
    })

    this.emptyTarget.classList.toggle("hidden", visible > 0)
    this.#setActive(null)
  }

  keydown(event) {
    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp": {
        event.preventDefault()
        if (this.listTarget.hidden) this.open()

        const visible = this.#visibleOptions()
        if (visible.length === 0) return

        const delta = event.key === "ArrowDown" ? 1 : -1
        const index = visible.indexOf(this.active)
        const next = visible[(index + delta + visible.length) % visible.length]
        this.#setActive(next)
        next.scrollIntoView({ block: "nearest" })
        break
      }
      case "Enter":
        if (this.active && !this.listTarget.hidden) {
          event.preventDefault()
          this.#choose(this.active)
        }
        break
      case "Escape":
        this.close()
        break
    }
  }

  select(event) {
    event.preventDefault()
    this.#choose(event.currentTarget)
  }

  #choose(option) {
    this.inputTarget.value = option.dataset.value
    this.close()
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  #visibleOptions() {
    return this.optionTargets.filter((option) => !option.classList.contains("hidden"))
  }

  #setActive(option) {
    this.active = option

    this.optionTargets.forEach((candidate) => {
      const isActive = candidate === option
      candidate.classList.toggle("bg-drip-50", isActive)
      candidate.classList.toggle("dark:bg-white/10", isActive)
      candidate.setAttribute("aria-selected", String(isActive))
    })
  }
}
