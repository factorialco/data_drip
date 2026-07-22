import { Controller } from "@hotwired/stimulus"

// Searchable multi-select for :enum backfill options. Keeps the hidden
// field's comma-separated value, the counter, and the select-all checkbox
// in sync with the individual checkboxes.
export default class extends Controller {
  static targets = ["hidden", "search", "selectAll", "counter", "row", "checkbox", "noResults"]

  connect() {
    this.sync()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  filter() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.#applyFilter(), 150)
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
    const values = this.checkboxTargets
      .filter((checkbox) => checkbox.checked)
      .map((checkbox) => checkbox.value)

    this.hiddenTarget.value = values.join(",")
    this.counterTarget.textContent = `${values.length}/${this.checkboxTargets.length} selected`
    this.selectAllTarget.checked = values.length === this.checkboxTargets.length
    this.selectAllTarget.indeterminate =
      values.length > 0 && values.length < this.checkboxTargets.length
  }

  #applyFilter() {
    const query = this.searchTarget.value.trim().toLowerCase()
    let visible = 0

    this.rowTargets.forEach((row) => {
      const match = !query || row.dataset.search.includes(query)
      row.classList.toggle("hidden", !match)
      if (match) visible++
    })

    this.noResultsTarget.classList.toggle("hidden", visible > 0)
  }
}
