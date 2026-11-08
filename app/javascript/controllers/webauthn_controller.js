import { Controller } from "@hotwired/stimulus"

// Runs a WebAuthn ceremony, then submits the form natively with the credential as JSON.
export default class extends Controller {
  static targets = ["credential", "error"]
  static values = { ceremony: String, optionsUrl: String }

  async start(event) {
    event.preventDefault()
    this.errorTarget.hidden = true

    try {
      const options = await this.#fetchOptions()
      const credential = this.ceremonyValue === "create"
        ? await navigator.credentials.create({ publicKey: creationOptions(options) })
        : await navigator.credentials.get({ publicKey: requestOptions(options) })

      this.credentialTarget.value = JSON.stringify(serialize(credential))
      this.element.submit()
    } catch {
      this.errorTarget.hidden = false
    }
  }

  async #fetchOptions() {
    const response = await fetch(this.optionsUrlValue, {
      method: "POST",
      headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
      credentials: "same-origin"
    })
    if (!response.ok) throw new Error(`options request failed: ${response.status}`)
    return response.json()
  }
}

function creationOptions(options) {
  return {
    ...options,
    challenge: decode(options.challenge),
    user: { ...options.user, id: decode(options.user.id) },
    excludeCredentials: (options.excludeCredentials || []).map(descriptor => ({ ...descriptor, id: decode(descriptor.id) }))
  }
}

function requestOptions(options) {
  return {
    ...options,
    challenge: decode(options.challenge),
    allowCredentials: (options.allowCredentials || []).map(descriptor => ({ ...descriptor, id: decode(descriptor.id) }))
  }
}

function serialize(credential) {
  const { response } = credential
  const serialized = {
    type: credential.type,
    id: credential.id,
    rawId: encode(credential.rawId),
    authenticatorAttachment: credential.authenticatorAttachment,
    clientExtensionResults: credential.getClientExtensionResults(),
    response: { clientDataJSON: encode(response.clientDataJSON) }
  }

  if (response.attestationObject) {
    serialized.response.attestationObject = encode(response.attestationObject)
    serialized.response.transports = response.getTransports?.() || []
  } else {
    serialized.response.authenticatorData = encode(response.authenticatorData)
    serialized.response.signature = encode(response.signature)
    serialized.response.userHandle = response.userHandle ? encode(response.userHandle) : null
  }

  return serialized
}

function decode(base64url) {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(base64url.length / 4) * 4, "=")
  return Uint8Array.from(atob(base64), character => character.charCodeAt(0)).buffer
}

function encode(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}
