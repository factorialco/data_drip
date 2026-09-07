import { Controller } from "@hotwired/stimulus"

// Searchable multi-select for :enum backfill options. Keeps the hidden
// field's comma-separated value, the counter, and the select-all checkbox
// in sync with the individual checkboxes.
export default class extends Controller {
  static targets = ["hidden", "search", "selectAll", "counter", "row", "checkbox", "noResults"]
  static values = { name: String, dependsOn: String }

  connect() {
    if (this.hasDependsOnValue) this.#applyDependency(this.#dependencyFieldValue())
    this.sync()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  filter() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.#applyFilter(), 150)
  }

  singleChanged(event) {
    window.dispatchEvent(
      new CustomEvent("data-drip:enum-change", {
        detail: { name: this.nameValue, value: event.target.value }
      })
    )
  }

  dependencyChanged(event) {
    if (!this.hasDependsOnValue || event.detail.name !== this.dependsOnValue) return

    this.#applyDependency(event.detail.value)
    this.sync()
  }

  toggleAll() {
    const checked = this.selectAllTarget.checked

    this.checkboxTargets.forEach((checkbox) => {
      const row = checkbox.closest("[data-search]")
      if (!row.classList.contains("hidden")) checkbox.checked = checked
    })

    this.sync()
  }

  clear() {
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = false
    })
    this.searchTarget.value = ""
    this.#applyFilter()
    this.sync()
  }

  sync() {
    if (!this.hasHiddenTarget) return

    const values = this.checkboxTargets
      .filter((checkbox) => checkbox.checked)
      .map((checkbox) => checkbox.value)

    this.hiddenTarget.value = values.join(",")
    const visible = this.checkboxTargets.filter(
      (checkbox) => !checkbox.closest("[data-search]").classList.contains("hidden")
    )
    this.counterTarget.textContent = `${values.length}/${visible.length} selected`
    this.selectAllTarget.checked = visible.length > 0 && values.length === visible.length
    this.selectAllTarget.indeterminate = values.length > 0 && values.length < visible.length
  }

  #applyFilter() {
    const query = this.searchTarget.value.trim().toLowerCase()
    let visible = 0

    this.rowTargets.forEach((row) => {
      const dependencyMatch = !this.hasDependsOnValue || row.dataset.dependency === this.currentDependency
      const match = dependencyMatch && (!query || row.dataset.search.includes(query))
      row.classList.toggle("hidden", !match)
      if (match) visible++
    })

    this.noResultsTarget.classList.toggle("hidden", visible > 0)
  }

  #dependencyFieldValue() {
    const field = this.element
      .closest("form")
      ?.querySelector(`[name$="[${this.dependsOnValue}]"]`)
    return field?.value || ""
  }

  #applyDependency(value) {
    this.currentDependency = value
    this.checkboxTargets.forEach((checkbox) => {
      const row = checkbox.closest("[data-search]")
      const matches = row.dataset.dependency === value
      row.classList.toggle("hidden", !matches)
      checkbox.checked = matches
    })
    this.#applyFilter()
  }
}
