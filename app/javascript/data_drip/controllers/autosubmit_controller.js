import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  submit() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  now() {
    clearTimeout(this.timer)
    this.element.requestSubmit()
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
