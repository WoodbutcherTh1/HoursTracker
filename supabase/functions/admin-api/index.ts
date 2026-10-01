// Owner/admin dashboard API (plan Phase 6).
//
// Every call must carry a signed-in session token whose account is listed in
// `public.admins` — checked here, server-side, on every request. The app's
// hidden Admin screen is only a convenience; hiding it is not the security.
//
// Actions (POST {"action": ...}):
//   whoami   → { isAdmin, role }                      (any signed-in account)
//   stats    → aggregate counts only (admin_stats())  — no per-user data
//   audience → { recipients, pushReachable, unmatchedEmails } for a target
//   send     → stores an announcement, fans it out, pushes over APNs
//   history  → the latest announcements with delivery counts
//
// Required secrets (`supabase secrets set`, never committed, never in chat):
//   APNS_KEY_P8      contents of the AuthKey_XXXX.p8 file
//   APNS_KEY_ID      the key's 10-character id
//   APNS_TEAM_ID     Apple developer team id
//   APNS_BUNDLE_ID   com.hourstracker.app
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected.
//
// Deployed with verify_jwt = false (see ../../config.toml); the session is
// verified below with auth.getUser instead.
import { createClient } from "jsr:@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
const APNS_KEY_P8 = Deno.env.get("APNS_KEY_P8")
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID")
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID")
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "com.hourstracker.app"

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
})

const LANGUAGES = ["en", "he", "ar"] as const
type Language = typeof LANGUAGES[number]
type Texts = Partial<Record<Language, string>>

interface Target {
  kind: "all" | "language" | "version" | "users"
  languages?: string[]
  versions?: string[]
  emails?: string[]
}

interface Device {
  id: string
  apns_token: string | null
  apns_env: string
  language: string
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)

  const user = await sessionUser(req)
  if (!user) return json({ error: "Not signed in" }, 401)

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json({ error: "Invalid JSON" }, 400)
  }

  const { data: admin } = await supabase.from("admins").select("role").eq("user_id", user).maybeSingle()
  if (body.action === "whoami") {
    return json({ isAdmin: admin != null, role: admin?.role ?? null }, 200)
  }
  if (!admin) return json({ error: "Forbidden" }, 403)

  try {
    switch (body.action) {
      case "stats": {
        const { data, error } = await supabase.rpc("admin_stats")
        if (error) throw error
        return json(data, 200)
      }
      case "audience": {
        const target = parseTarget(body.target)
        if (!target) return json({ error: "Invalid target" }, 400)
        const { devices, unmatchedEmails } = await resolveAudience(target)
        return json({
          recipients: devices.length,
          pushReachable: devices.filter((d) => d.apns_token).length,
          unmatchedEmails,
        }, 200)
      }
      case "send":
        return await send(user, body)
      case "history":
        return await history()
      default:
        return json({ error: "Unknown action" }, 400)
    }
  } catch (error) {
    console.error("admin-api failed", (error as Error).message ?? error)
    return json({ error: "Server error" }, 500)
  }
})

// MARK: - Send

async function send(adminId: string, body: Record<string, unknown>) {
  const title = parseTexts(body.title, 80)
  const text = parseTexts(body.body, 1000)
  const target = parseTarget(body.target)
  if (!title || !text || !target) return json({ error: "Invalid announcement" }, 400)
  const push = body.push !== false
  const inApp = body.inApp !== false
  if (!push && !inApp) return json({ error: "Nothing to deliver" }, 400)

  const { data: ok } = await supabase.rpc("check_rate_limit", {
    p_bucket: "admin-send",
    p_key: adminId,
    p_limit: 10,
    p_window_minutes: 60,
  })
  if (ok === false) return json({ error: "Too many requests" }, 429)

  const { devices } = await resolveAudience(target)
  const { data: announcement, error } = await supabase
    .from("announcements")
    .insert({ created_by: adminId, title, body: text, target, push, in_app: inApp, recipients: devices.length })
    .select("id")
    .single()
  if (error) throw error

  for (let i = 0; i < devices.length; i += 500) {
    const rows = devices.slice(i, i + 500).map((d) => ({ announcement_id: announcement.id, device_id: d.id }))
    const { error: targetError } = await supabase.from("announcement_targets").insert(rows)
    if (targetError) throw targetError
  }

  let pushSent = 0
  let pushFailed = 0
  let pushConfigured = true
  if (push) {
    const reachable = devices.filter((d) => d.apns_token)
    const jwt = await apnsJWT()
    if (!jwt) {
      pushConfigured = false
    } else {
      for (let i = 0; i < reachable.length; i += 20) {
        const results = await Promise.all(
          reachable.slice(i, i + 20).map((d) => deliver(jwt, d, title, text, announcement.id)),
        )
        for (const delivered of results) delivered ? pushSent++ : pushFailed++
      }
    }
    await supabase.from("announcements")
      .update({ push_sent: pushSent, push_failed: pushFailed })
      .eq("id", announcement.id)
  }

  return json({ id: announcement.id, recipients: devices.length, pushSent, pushFailed, pushConfigured }, 200)
}

async function history() {
  const { data, error } = await supabase
    .from("announcements")
    .select("id, title, body, target, push, in_app, recipients, push_sent, push_failed, created_at, expires_at")
    .order("created_at", { ascending: false })
    .limit(20)
  if (error) throw error

  const items = await Promise.all((data ?? []).map(async (a) => {
    const { count } = await supabase
      .from("announcement_targets")
      .select("device_id", { count: "exact", head: true })
      .eq("announcement_id", a.id)
      .not("seen_at", "is", null)
    return { ...a, seen: count ?? 0 }
  }))
  return json({ announcements: items }, 200)
}

// MARK: - Audience

async function resolveAudience(target: Target): Promise<{ devices: Device[]; unmatchedEmails: string[] }> {
  let unmatchedEmails: string[] = []
  let userIds: string[] | null = null
  if (target.kind === "users") {
    const emails = target.emails ?? []
    const { data, error } = await supabase.rpc("admin_user_ids_for_emails", { p_emails: emails })
    if (error) throw error
    const found = (data ?? []) as { user_id: string; email: string }[]
    const foundEmails = new Set(found.map((row) => row.email.toLowerCase()))
    unmatchedEmails = emails.filter((email) => !foundEmails.has(email.toLowerCase()))
    userIds = found.map((row) => row.user_id)
    if (userIds.length === 0) return { devices: [], unmatchedEmails }
  }

  const devices: Device[] = []
  for (let from = 0; ; from += 1000) {
    let query = supabase
      .from("devices")
      .select("id, apns_token, apns_env, language")
      .eq("announcements_enabled", true)
      .order("id")
      .range(from, from + 999)
    if (target.kind === "language") query = query.in("language", target.languages ?? [])
    if (target.kind === "version") query = query.in("app_version", target.versions ?? [])
    if (userIds) query = query.in("user_id", userIds)
    const { data, error } = await query
    if (error) throw error
    devices.push(...(data ?? []))
    if (!data || data.length < 1000 || devices.length >= 20000) break
  }
  return { devices, unmatchedEmails }
}

function parseTarget(value: unknown): Target | null {
  const raw = value as Target | undefined
  switch (raw?.kind) {
    case "all":
      return { kind: "all" }
    case "language": {
      const languages = (raw.languages ?? []).filter((l) => (LANGUAGES as readonly string[]).includes(l))
      return languages.length ? { kind: "language", languages } : null
    }
    case "version": {
      const versions = (raw.versions ?? []).map((v) => String(v).trim().slice(0, 20)).filter(Boolean).slice(0, 20)
      return versions.length ? { kind: "version", versions } : null
    }
    case "users": {
      const emails = (raw.emails ?? [])
        .map((e) => String(e).trim().toLowerCase())
        .filter((e) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e))
        .slice(0, 200)
      return emails.length ? { kind: "users", emails: [...new Set(emails)] } : null
    }
    default:
      return null
  }
}

function parseTexts(value: unknown, max: number): Texts | null {
  if (!value || typeof value !== "object") return null
  const texts: Texts = {}
  for (const language of LANGUAGES) {
    const text = (value as Record<string, unknown>)[language]
    if (typeof text === "string" && text.trim()) texts[language] = text.trim().slice(0, max)
  }
  return Object.keys(texts).length ? texts : null
}

function localized(texts: Texts, language: string): string {
  return texts[language as Language] || texts.en || Object.values(texts).find(Boolean) || ""
}

// MARK: - APNs

let cachedJWT: { token: string; issuedAt: number } | null = null

/// Provider token for APNs, reused for 50 minutes (Apple accepts 20–60).
async function apnsJWT(): Promise<string | null> {
  if (!APNS_KEY_P8 || !APNS_KEY_ID || !APNS_TEAM_ID) return null
  const now = Math.floor(Date.now() / 1000)
  if (cachedJWT && now - cachedJWT.issuedAt < 50 * 60) return cachedJWT.token

  const pem = APNS_KEY_P8.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "")
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"])

  const header = base64url(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID }))
  const claims = base64url(JSON.stringify({ iss: APNS_TEAM_ID, iat: now }))
  const signingInput = `${header}.${claims}`
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  )
  const token = `${signingInput}.${base64url(new Uint8Array(signature))}`
  cachedJWT = { token, issuedAt: now }
  return token
}

async function deliver(jwt: string, device: Device, title: Texts, body: Texts, id: string): Promise<boolean> {
  const host = device.apns_env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com"
  try {
    const res = await fetch(`https://${host}/3/device/${device.apns_token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 3 * 24 * 3600),
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: {
          alert: { title: localized(title, device.language), body: localized(body, device.language) },
          sound: "default",
        },
        announcementId: id,
      }),
    })
    if (res.ok) return true
    const reason = (await res.json().catch(() => ({})))?.reason ?? ""
    if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
      // The app was deleted or the token rotated — stop pushing to it.
      await supabase.from("devices").update({ apns_token: null }).eq("id", device.id)
    } else {
      console.error("apns push failed", res.status, reason)
    }
    return false
  } catch (error) {
    console.error("apns push error", (error as Error).message)
    return false
  }
}

function base64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

// MARK: - Helpers

async function sessionUser(req: Request): Promise<string | null> {
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? ""
  if (token.split(".").length !== 3) return null
  const { data, error } = await supabase.auth.getUser(token)
  if (error || !data.user) return null
  return data.user.id
}

function json(data: unknown, status: number) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}
