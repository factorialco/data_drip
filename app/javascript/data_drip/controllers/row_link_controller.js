import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Makes a whole table row clickable while keeping real links/buttons usable.
export default class extends Controller {
  static values = { url: String }

  visit(event) {
    if (event.target.closest("a, button, input, select, label")) return

    Turbo.visit(this.urlValue)
  }
}
