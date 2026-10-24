// Support inbox for admins. Same rule as admin-api: the caller must be signed in and
// listed in public.admins, checked on every request.
//
// POST {"action": ...}
//   threads                      → { threads } (newest first, with unread flag and who wrote)
//   messages   {threadId}        → { messages } (user messages carry the sender's context)
//   reply      {threadId, body}  → { messages }   (marks the thread answered, pushes the user)
//   mark_read  {threadId}        → { ok }
//   auto_replies                 → { rules }
//   auto_reply_save {rule}       → { ok }         (insert, or update when rule.id is set)
//   auto_reply_delete {id}       → { ok }
//
// A reply sets support_threads.unread_user and sends one APNs alert to the install
// that owns the thread (APNs secrets as in admin-api). The app also polls
// support-chat "status" when it opens, so a missed push still shows the reply.
import { createClient } from "jsr:@supabase/supabase-js@2"

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
)
const APNS_KEY_P8 = Deno.env.get("APNS_KEY_P8")
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID")
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID")
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "com.hourstracker.app"

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const REPLY_TITLE: Record<string, string> = {
  en: "Reply from HoursTracker support",
  he: "תשובה מצוות התמיכה של HoursTracker",
  ar: "رد من دعم HoursTracker",
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405)

  const userId = await sessionUser(req)
  if (!userId) return json({ error: "not_signed_in" }, 401)

  const { data: admin } = await supabase.from("admins").select("role").eq("user_id", userId).maybeSingle()
  if (!admin) return json({ error: "forbidden" }, 403)

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json({ error: "invalid_json" }, 400)
  }

  try {
    switch (body.action) {
      case "threads": {
        const { data, error } = await supabase
          .from("support_threads")
          .select(
            "id, status, unread_admin, last_message_at, created_at, device_id, user_id, user_email, device_model, os_version, app_version, build, locale",
          )
          .order("last_message_at", { ascending: false })
          .limit(100)
        if (error) throw error
        // The device id is only a shortened reference here, never shown in full.
        const threads = (data ?? []).map(({ device_id, ...t }) => ({
          ...t,
          device_ref: String(device_id).slice(0, 8),
          has_account: t.user_id != null,
        }))
        return json({ threads }, 200)
      }
      case "messages":
        return json({ messages: await messagesFor(String(body.threadId ?? "")) }, 200)
      case "reply": {
        const text = String(body.body ?? "").trim()
        const threadId = String(body.threadId ?? "")
        if (!text || text.length > 2000 || !threadId) return json({ error: "invalid_reply" }, 400)
        const { error } = await supabase.from("support_messages").insert({ thread_id: threadId, sender: "admin", body: text })
        if (error) throw error
        const now = new Date().toISOString()
        await supabase.from("support_threads").update({
          unread_admin: false,
          unread_user: true,
          status: "answered",
          last_message_at: now,
          last_admin_reply_at: now,
        }).eq("id", threadId)
        try {
          await notifyUser(threadId, text)
        } catch (error) {
          console.error("user push failed", (error as Error).message ?? error)
        }
        return json({ messages: await messagesFor(threadId) }, 200)
      }
      case "mark_read": {
        const { error } = await supabase.from("support_threads").update({ unread_admin: false }).eq("id", String(body.threadId ?? ""))
        if (error) throw error
        return json({ ok: true }, 200)
      }
      case "auto_replies": {
        const { data, error } = await supabase.from("support_auto_replies").select("*").order("created_at", { ascending: true })
        if (error) throw error
        return json({ rules: data ?? [] }, 200)
      }
      case "auto_reply_save": {
        const rule = (body.rule ?? {}) as Record<string, unknown>
        const keywords = Array.isArray(rule.keywords)
          ? rule.keywords.map((k) => String(k).trim()).filter(Boolean).slice(0, 20)
          : []
        if (keywords.length === 0) return json({ error: "invalid_rule" }, 400)
        const row = {
          keywords,
          reply_en: clip(rule.reply_en),
          reply_he: clip(rule.reply_he),
          reply_ar: clip(rule.reply_ar),
          enabled: rule.enabled !== false,
        }
        const query = rule.id
          ? supabase.from("support_auto_replies").update(row).eq("id", String(rule.id))
          : supabase.from("support_auto_replies").insert(row)
        const { error } = await query
        if (error) throw error
        return json({ ok: true }, 200)
      }
      case "auto_reply_delete": {
        const { error } = await supabase.from("support_auto_replies").delete().eq("id", String(body.id ?? ""))
        if (error) throw error
        return json({ ok: true }, 200)
      }
      default:
        return json({ error: "unknown_action" }, 400)
    }
  } catch (error) {
    console.error("support-admin failed", (error as Error).message ?? error)
    return json({ error: "server_error" }, 500)
  }
})

async function messagesFor(threadId: string) {
  if (!threadId) return []
  const { data, error } = await supabase
    .from("support_messages")
    .select("id, sender, body, created_at, context")
    .eq("thread_id", threadId)
    .order("created_at", { ascending: true })
    .limit(300)
  if (error) throw error
  return data ?? []
}

function clip(value: unknown): string | null {
  const text = String(value ?? "").trim().slice(0, 1000)
  return text || null
}

// MARK: - User push

async function notifyUser(threadId: string, text: string) {
  const jwt = await apnsJWT()
  if (!jwt) return
  const { data: thread } = await supabase
    .from("support_threads")
    .select("device_id, language")
    .eq("id", threadId)
    .maybeSingle()
  if (!thread || !UUID_RE.test(String(thread.device_id))) return
  const { data: device } = await supabase
    .from("devices")
    .select("id, apns_token, apns_env, language")
    .eq("id", thread.device_id)
    .not("apns_token", "is", null)
    .maybeSingle()
  if (!device) return
  const language = thread.language || device.language || "en"
  const preview = text.length > 140 ? `${text.slice(0, 140)}…` : text
  const host = device.apns_env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com"
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
      aps: { alert: { title: REPLY_TITLE[language] ?? REPLY_TITLE.en, body: preview }, sound: "default" },
      supportReply: true,
      supportThreadId: threadId,
    }),
  })
  if (res.ok) return
  const reason = (await res.json().catch(() => ({})))?.reason ?? ""
  if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
    await supabase.from("devices").update({ apns_token: null }).eq("id", device.id)
  } else {
    console.error("user push failed", res.status, reason)
  }
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
