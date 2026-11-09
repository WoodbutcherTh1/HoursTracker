// Shared by apple-token-exchange and delete-account. Not deployed as its own
// function — Supabase skips directories starting with "_".
//
// Builds the "client_secret" Sign in with Apple's token/revoke endpoints
// require: a short-lived ES256 JWT signed with the Apple Developer "Sign in
// with Apple" key (.p8), not a fixed secret string. Needs three Supabase
// secrets: APPLE_PRIVATE_KEY (the .p8 file's contents, PEM), APPLE_TEAM_ID,
// APPLE_KEY_ID.
export const APPLE_CLIENT_ID = "com.hourstracker.app"

export async function appleClientSecret(): Promise<string> {
  const teamId = Deno.env.get("APPLE_TEAM_ID")
  const keyId = Deno.env.get("APPLE_KEY_ID")
  const privateKeyPem = Deno.env.get("APPLE_PRIVATE_KEY")
  if (!teamId || !keyId || !privateKeyPem) {
    throw new Error("Apple Sign In secrets not configured (APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY)")
  }

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  )

  const now = Math.floor(Date.now() / 1000)
  const header = { alg: "ES256", kid: keyId }
  // Only used for one immediate request (token exchange or revoke), never
  // stored — a short lifetime limits the blast radius if it ever leaked.
  const payload = { iss: teamId, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: APPLE_CLIENT_ID }

  const encoder = new TextEncoder()
  const signingInput = `${base64url(encoder.encode(JSON.stringify(header)))}.${base64url(encoder.encode(JSON.stringify(payload)))}`
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput))
  return `${signingInput}.${base64url(new Uint8Array(signature))}`
}

function pemToDer(pem: string): Uint8Array {
  const base64 = pem.replace(/-----BEGIN PRIVATE KEY-----/, "").replace(/-----END PRIVATE KEY-----/, "").replace(/\s+/g, "")
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

function base64url(bytes: Uint8Array): string {
  let binary = ""
  for (const b of bytes) binary += String.fromCharCode(b)
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}
