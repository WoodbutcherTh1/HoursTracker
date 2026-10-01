// Device registry for owner announcements (plan Phase 6).
//
// Called by every app install (signed in or not) with a random install id —
// never the vendor id — plus the push token, in-app language and app version,
// so broadcasts reach each user in their own language. Also returns the
// announcements addressed to this device that it hasn't shown yet, and lets
// the device acknowledge them or remove itself (Settings → Delete all data).
//
// Deployed with verify_jwt = false (see ../../config.toml) because the app's
// publishable key is not a JWT. The caller's account, when there is one, is
// taken ONLY from a valid session token checked with auth.getUser — never from
// the request body.
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected by the Edge
// Runtime. Tables are RLS-locked with no policies (see ../../migrations).
import { createClient } from "jsr:@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
})

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const APNS_TOKEN_RE = /^[0-9a-f]{64,200}$/i
const LANGUAGES = new Set(["en", "he", "ar"])

interface RegisterPayload {
  action?: "register" | "ack" | "forget"
  deviceId?: string
  apnsToken?: string | null
  apnsEnv?: string
  language?: string
  appVersion?: string
  build?: string
  osVersion?: string
  hasWatch?: boolean
  hasWidget?: boolean
  announcementsEnabled?: boolean
  onShift?: boolean
  seenIds?: string[]
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)

  let body: RegisterPayload
  try {
    body = await req.json()
  } catch {
    return json({ error: "Invalid JSON" }, 400)
  }

  const deviceId = body.deviceId ?? ""
  if (!UUID_RE.test(deviceId)) return json({ error: "Invalid device" }, 400)

  const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "0.0.0.0"
  if (!(await allowed("register-device:ip", clientIp, 120)) ||
      !(await allowed("register-device:device", deviceId, 30))) {
    return json({ error: "Too many requests" }, 429)
  }

  switch (body.action ?? "register") {
    case "forget": {
      const { error } = await supabase.from("devices").delete().eq("id", deviceId)
      if (error) return failure("forget", error)
      return json({ success: true }, 200)
    }
    case "ack": {
      const ids = (body.seenIds ?? []).filter((id) => UUID_RE.test(id)).slice(0, 50)
      if (ids.length > 0) {
        const { error } = await supabase
          .from("announcement_targets")
          .update({ seen_at: new Date().toISOString() })
          .eq("device_id", deviceId)
          .in("announcement_id", ids)
        if (error) return failure("ack", error)
      }
      return json({ success: true }, 200)
    }
    case "register":
      return await register(req, deviceId, body)
    default:
      return json({ error: "Unknown action" }, 400)
  }
})

async function register(req: Request, deviceId: string, body: RegisterPayload) {
  const language = LANGUAGES.has(body.language ?? "") ? body.language! : "en"
  const apnsToken = body.apnsToken && APNS_TOKEN_RE.test(body.apnsToken) ? body.apnsToken.toLowerCase() : null

  const row = {
    id: deviceId,
    user_id: await sessionUserId(req),
    apns_token: apnsToken,
    apns_env: body.apnsEnv === "sandbox" ? "sandbox" : "production",
    language,
    app_version: clip(body.appVersion, 20),
    build: clip(body.build, 20),
    os_version: clip(body.osVersion, 20),
    has_watch: body.hasWatch === true,
    has_widget: body.hasWidget === true,
    announcements_enabled: body.announcementsEnabled !== false,
    // Bare yes/no for the owner's live "on a shift now" count; older builds
    // don't send it and count as not on a shift.
    on_shift: body.onShift === true,
    last_seen_at: new Date().toISOString(),
  }
  const { error } = await supabase.from("devices").upsert(row, { onConflict: "id" })
  if (error) return failure("upsert", error)

  // The in-app copy of recent announcements addressed to this device.
  const { data, error: pendingError } = await supabase
    .from("announcement_targets")
    .select("announcement_id, announcements!inner(id, title, body, created_at, expires_at, in_app)")
    .eq("device_id", deviceId)
    .is("seen_at", null)
    .eq("announcements.in_app", true)
    .gt("announcements.expires_at", new Date().toISOString())
    .limit(5)
  if (pendingError) return failure("pending", pendingError)

  const announcements = (data ?? []).map((row) => {
    // deno-lint-ignore no-explicit-any
    const a = (row as any).announcements
    return {
      id: a.id,
      title: localized(a.title, language),
      body: localized(a.body, language),
      createdAt: a.created_at,
    }
  })
  return json({ success: true, announcements }, 200)
}

/// The signed-in account behind the request, or null for the publishable key /
/// an expired or forged token.
async function sessionUserId(req: Request): Promise<string | null> {
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? ""
  if (token.split(".").length !== 3) return null
  const { data, error } = await supabase.auth.getUser(token)
  if (error || !data.user) return null
  return data.user.id
}

function localized(texts: Record<string, string> | null, language: string): string {
  if (!texts) return ""
  return texts[language]?.trim() || texts["en"]?.trim() || Object.values(texts).find((t) => t?.trim()) || ""
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

function clip(value: string | undefined, max: number): string | null {
  const trimmed = value?.trim()
  return trimmed ? trimmed.slice(0, max) : null
}

function failure(step: string, error: { message: string }) {
  console.error(`register-device ${step} failed`, error.message)
  return json({ error: "Server error" }, 500)
}

function json(data: unknown, status: number) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}
