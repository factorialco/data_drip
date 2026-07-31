import { Controller } from "@hotwired/stimulus"

// Debounced auto-submit for filter forms.
//
// These forms live inside the very Turbo Frame they navigate, so each submit
// replaces the form — including the field being typed into, which drops focus
// (and discards any keystroke that landed while the request was in flight).
// Snapshot the focused field on submit, keep that snapshot current until the
// response lands, and restore focus/caret/value when the replacement form
// connects. The snapshot outlives the controller instance, hence module scope.
let pendingRestore = null

export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  connect() {
    this.#restore()
  }

  submit() {
    // Keystrokes typed while a submit is in flight would be thrown away by the
    // incoming render, so keep the pending snapshot up to date.
    if (pendingRestore) pendingRestore = this.#snapshot()

    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.#requestSubmit(), this.delayValue)
  }

  now() {
    clearTimeout(this.timer)
    this.#requestSubmit()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  #requestSubmit() {
    pendingRestore = this.#snapshot()
    this.element.requestSubmit()
  }

  #snapshot() {
    const field = document.activeElement
    if (!field || !field.name || !this.element.contains(field)) return null

    return {
      form: this.element.action,
      name: field.name,
      value: field.value,
      // Absent on <select> and other fields without a text caret.
      selectionStart: field.selectionStart,
      selectionEnd: field.selectionEnd
    }
  }

  #restore() {
    if (!pendingRestore || pendingRestore.form !== this.element.action) return

    const snapshot = pendingRestore
    pendingRestore = null

    const field = this.element.elements[snapshot.name]
    if (!field || typeof field.focus !== "function") return

    field.focus()

    // The response reflects the value as it was when the request went out.
    const stale = field.value !== snapshot.value
    if (stale) field.value = snapshot.value

    if (typeof snapshot.selectionStart === "number" && field.setSelectionRange) {
      field.setSelectionRange(snapshot.selectionStart, snapshot.selectionEnd)
    }

    // Keystrokes we just put back still need filtering for.
    if (stale) this.submit()
  }
}
