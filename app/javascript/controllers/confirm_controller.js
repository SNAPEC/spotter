import { Controller } from "@hotwired/stimulus"

// Asks before a native (non-Turbo) form submission, where data-turbo-confirm does not apply.
export default class extends Controller {
  static values = { message: String }

  ask(event) {
    if (!window.confirm(this.messageValue)) event.preventDefault()
  }
}
