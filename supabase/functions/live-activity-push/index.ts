// Keeps the running-shift Live Activity (Dynamic Island / Lock Screen) fresh
// while the app is fully suspended. The in-process 60s refresh loop
// (AppViewModel.startLiveActivityRefreshLoop) freezes the moment iOS actually
// suspends the app, and the sole "last push at backgrounding" was leaving the
// banner stale for hours on a real device (user report). This re-delivers the
// SAME content-state the app already computed — never recomputes pay or
// elapsed time server-side — purely so SpringBoard keeps recompositing the
// activity; the client's own Text(timerInterval:) does the actual ticking.
//
// POST {"action": ...}
//   update  {deviceId, pushToken?, apnsEnv?, contentState?}  → { ok }
//     Called by the app: once with a push token when the activity starts (and
//     whenever ActivityKit rotates it), and on every regular update with the
//     freshly-computed contentState. Either field alone is fine — this only
//     touches the fields it's given.
//   clear   {deviceId}                                        → { ok }
//     Called on clock-out / activity end — stops future ticks for this device.
//   tick    (no body fields; authenticated by the x-cron-secret header)       → { sent, failed }
//     Called ONLY by the pg_cron job added in
//     20261116160000_live_activity_push.sql, every 60s. Re-delivers every
//     stored content-state via APNs push-type "liveactivity".
//
// Required secrets (`supabase secrets set`, never committed, never in chat):
//   APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID   — same APNs key as admin-api/support-admin
//   APNS_BUNDLE_ID                            — com.hourstracker.app (default)
//   CRON_SECRET                               — shared secret for the "tick" action;
//                                                must match `app.settings.cron_secret`
//                                                (set by hand, see the migration)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected.
//
// Deployed with verify_jwt = false (see ../../config.toml) — "update"/"clear" use
// the publishable key like register-device, "tick" uses the cron secret header.
import { createClient } from "jsr:@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
const APNS_KEY_P8 = Deno.env.get("APNS_KEY_P8")
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID")
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID")
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "com.hourstracker.app"
const CRON_SECRET = Deno.env.get("CRON_SECRET")

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
})

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const TOKEN_RE = /^[0-9a-f]{64,200}$/i

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405)

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json({ error: "invalid_json" }, 400)
  }

  try {
    switch (body.action) {
      case "update":
        return await update(req, body)
      case "clear":
        return await clear(body)
      case "tick": {
        const provided = req.headers.get("x-cron-secret")
        if (!CRON_SECRET || !provided || provided !== CRON_SECRET) {
          return json({ error: "forbidden" }, 403)
        }
        return await tick()
      }
      default:
        return json({ error: "unknown_action" }, 400)
    }
  } catch (error) {
    console.error("live-activity-push failed", (error as Error).message ?? error)
    return json({ error: "server_error" }, 500)
  }
})

async function update(req: Request, body: Record<string, unknown>) {
  const deviceId = String(body.deviceId ?? "")
  if (!UUID_RE.test(deviceId)) return json({ error: "invalid_device" }, 400)

  const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "0.0.0.0"
  if (!(await allowed("live-activity:ip", clientIp, 240)) || !(await allowed("live-activity:device", deviceId, 120))) {
    return json({ error: "too_many_requests" }, 429)
  }

  const pushToken = typeof body.pushToken === "string" && TOKEN_RE.test(body.pushToken) ? body.pushToken.toLowerCase() : null
  const apnsEnv = body.apnsEnv === "sandbox" ? "sandbox" : "production"
  const contentState = isPlainObject(body.contentState) ? body.contentState : null

  if (pushToken) {
    // A fresh (or first) token: full upsert, content-state optional — the
    // token observation stream and the regular update loop can arrive as two
    // separate calls, in either order.
    const row: Record<string, unknown> = { device_id: deviceId, push_token: pushToken, apns_env: apnsEnv, updated_at: new Date().toISOString() }
    if (contentState) row.content_state = contentState
    const { error } = await supabase.from("live_activity_tokens").upsert(row, { onConflict: "device_id" })
    if (error) return failure("upsert", error)
    return json({ ok: true }, 200)
  }

  if (contentState) {
    // No token in this call — just refresh the cached state for whatever
    // token is already on file. Zero rows affected (no token registered yet)
    // is a harmless no-op; the next token-bearing call will catch up.
    const { error } = await supabase
      .from("live_activity_tokens")
      .update({ content_state: contentState, updated_at: new Date().toISOString() })
      .eq("device_id", deviceId)
    if (error) return failure("update", error)
    return json({ ok: true }, 200)
  }

  return json({ error: "nothing_to_update" }, 400)
}

async function clear(body: Record<string, unknown>) {
  const deviceId = String(body.deviceId ?? "")
  if (!UUID_RE.test(deviceId)) return json({ error: "invalid_device" }, 400)
  const { error } = await supabase.from("live_activity_tokens").delete().eq("device_id", deviceId)
  if (error) return failure("clear", error)
  return json({ ok: true }, 200)
}

async function tick() {
  const jwt = await apnsJWT()
  if (!jwt) return json({ error: "apns_not_configured" }, 200)

  const { data, error } = await supabase
    .from("live_activity_tokens")
    .select("device_id, push_token, apns_env, content_state")
    // An empty object means only the token has arrived so far — nothing worth
    // re-delivering yet.
    .neq("content_state", "{}")
  if (error) return failure("tick_select", error)

  let sent = 0
  let failed = 0
  const now = Math.floor(Date.now() / 1000)
  await Promise.all((data ?? []).map(async (row) => {
    const host = row.apns_env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com"
    const res = await fetch(`https://${host}/3/device/${row.push_token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": `${APNS_BUNDLE_ID}.push-type.liveactivity`,
        "apns-push-type": "liveactivity",
        "apns-priority": "10",
        "apns-expiration": String(now + 60),
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: {
          timestamp: now,
          event: "update",
          "content-state": row.content_state,
        },
      }),
    }).catch(() => null)

    if (res?.ok) {
      sent++
      return
    }
    failed++
    const reason = (await res?.json().catch(() => ({})))?.reason ?? ""
    // Same cleanup as the alert-push paths in admin-api/support-admin: a dead
    // token should stop being retried every minute.
    if (res?.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
      await supabase.from("live_activity_tokens").delete().eq("device_id", row.device_id)
    }
  }))

  return json({ sent, failed }, 200)
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

async function allowed(bucket: string, key: string, limit: number): Promise<boolean> {
  const { data, error } = await supabase.rpc("check_rate_limit", {
    p_bucket: bucket,
    p_key: key,
    p_limit: limit,
    p_window_minutes: 60,
  })
  if (error) {
    console.error("rate limit check failed", error.message)
    return true
  }
  return data !== false
}

function failure(step: string, error: { message: string }) {
  console.error(`live-activity-push ${step} failed`, error.message)
  return json({ error: "server_error" }, 500)
}

let cachedJWT: { token: string; issuedAt: number } | null = null

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
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput))
  const token = `${signingInput}.${base64url(new Uint8Array(signature))}`
  cachedJWT = { token, issuedAt: now }
  return token
}

function base64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

function json(data: unknown, status: number) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}
