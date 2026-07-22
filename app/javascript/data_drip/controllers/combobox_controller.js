import { Controller } from "@hotwired/stimulus"

// Filterable combobox over the backfill classes. Fuzzy-ranks matches against
// the class name (with match highlighting), its component, and the full name;
// keeps a "Recent" section on top; and reorders results best-first.
// Selecting an option fills the input and dispatches a bubbling "change" event
// so other controllers (backfill-options) can react.
export default class extends Controller {
  static targets = [
    "input",
    "list",
    "option",
    "empty",
    "recentHeader",
    "allHeader",
    "count"
  ]

  connect() {
    const options = this.optionTargets
    this.recentOptions = options.filter((o) => o.dataset.recent === "true")
    this.allOptions = options.filter((o) => o.dataset.recent !== "true")
  }

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

    // Recents keep their (server-provided) order; just show/hide + highlight.
    let recentVisible = 0
    this.recentOptions.forEach((el) => {
      const result = this.#match(query, el)
      el.classList.toggle("hidden", !result.visible)
      if (result.visible) {
        recentVisible++
        this.#highlight(el, query, result)
      }
    })
    if (this.hasRecentHeaderTarget) {
      this.recentHeaderTarget.classList.toggle("hidden", recentVisible === 0)
    }

    // "All" is scored and reordered best-first (base order when the query is empty).
    const scored = this.allOptions.map((el, index) => ({
      el,
      index,
      result: this.#match(query, el)
    }))

    const ordered = scored.slice().sort((a, b) => {
      if (!query) return a.index - b.index
      const sa = a.result.visible ? a.result.score : -Infinity
      const sb = b.result.visible ? b.result.score : -Infinity
      return sb - sa || a.index - b.index
    })

    let allVisible = 0
    ordered.forEach(({ el, result }) => {
      el.classList.toggle("hidden", !result.visible)
      if (result.visible) {
        allVisible++
        this.#highlight(el, query, result)
      }
      this.listTarget.insertBefore(el, this.emptyTarget)
    })
    if (this.hasAllHeaderTarget) {
      this.allHeaderTarget.classList.toggle("hidden", allVisible === 0)
    }

    this.emptyTarget.classList.toggle("hidden", recentVisible + allVisible > 0)
    if (this.hasCountTarget) {
      this.countTarget.textContent = `${allVisible} of ${this.allOptions.length}`
    }

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

  // Scores an option against the query: the class name (highlighted), then the
  // component, then the full name — each ranked below the previous.
  #match(query, el) {
    if (!query) return { visible: true, score: 0, positions: [] }

    const name = fuzzyScore(query, el.dataset.name || "")
    if (name) return { visible: true, score: name.score, positions: name.positions }

    const component = fuzzyScore(query, el.dataset.component || "")
    if (component) return { visible: true, score: component.score - 20, positions: [] }

    const value = fuzzyScore(query, el.dataset.value || "")
    if (value) return { visible: true, score: value.score - 40, positions: [] }

    return { visible: false, score: -Infinity, positions: [] }
  }

  #highlight(el, query, result) {
    const span = el.querySelector("[data-combobox-name]")
    if (!span) return

    const name = el.dataset.name || ""
    if (!query || result.positions.length === 0) {
      span.textContent = name
      return
    }

    const matched = new Set(result.positions)
    let html = ""
    for (let i = 0; i < name.length; i++) {
      const char = escapeHtml(name[i])
      html += matched.has(i)
        ? `<mark class="bg-transparent font-semibold text-drip-700 dark:text-drip-400">${char}</mark>`
        : char
    }
    span.innerHTML = html
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

// True at the start of a word: string start, a camelCase hump, or after a
// separator — so acronym-ish queries ("dc" -> DeleteCompetencies) score well.
function isBoundary(target, i) {
  if (i === 0) return true
  const char = target[i]
  const prev = target[i - 1]
  if (/[A-Z]/.test(char) && /[a-z0-9]/.test(prev)) return true
  return /[^A-Za-z0-9]/.test(prev)
}

// Subsequence match with positional bonuses. Returns { score, positions } or
// null when the query is not a subsequence of the target.
function fuzzyScore(query, target) {
  if (!query) return { score: 0, positions: [] }

  const lower = target.toLowerCase()
  const positions = []
  let cursor = 0
  let previous = -2
  let score = 0

  for (const char of query) {
    let found = -1
    for (let k = cursor; k < lower.length; k++) {
      if (lower[k] === char) {
        found = k
        break
      }
    }
    if (found === -1) return null

    let bonus = 1
    if (found === 0) bonus += 10
    else if (isBoundary(target, found)) bonus += 7
    if (found === previous + 1) bonus += 5

    score += bonus
    positions.push(found)
    previous = found
    cursor = found + 1
  }

  score -= (lower.length - query.length) * 0.1
  return { score, positions }
}

function escapeHtml(string) {
  return string.replace(
    /[&<>"]/g,
    (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[char]
  )
}
