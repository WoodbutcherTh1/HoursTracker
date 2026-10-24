// In-app support chat, user side. A conversation is keyed by the per-install id (the
// same one register-device uses), so chatting works without an account. When the
// request carries a signed-in session token the account is attached to the
// conversation — read from the verified token on the server, never from the body.
// Messages live in support_threads / support_messages, which only the service role
// can read.
//
// POST {"action": "send", "deviceId", "body", "language", "context"} → { messages }
// POST {"action": "list", "deviceId", "markRead"?}                   → { messages }
// POST {"action": "status", "deviceId"}                              → { unread, preview }
//
// `context` = { model, osVersion, appVersion, build, locale } — what the owner sees
// next to each message. Stored on the thread (latest) and on the message (snapshot).
//
// Sending is limited to 10 messages per install per hour (check_rate_limit), and is
// switched off when app_config.chat_enabled is false (admin kill switch).
// A matching auto-reply (support_auto_replies) is added right after the message.
// Admins get one push when a conversation goes from read to unread (APNs secrets as in
// admin-api); a failed push never blocks the message.
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

const MAX_BODY = 1000
const LANGUAGES = ["en", "he", "ar"]

interface Message {
  id: string
  sender: string
  body: string
  created_at: string
}

interface Context {
  model: string | null
  osVersion: string | null
  appVersion: string | null
  build: string | null
  locale: string | null
}

interface Identity {
  userId: string | null
  email: string | null
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405)

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json({ error: "invalid_json" }, 400)
  }

  const deviceId = String(body.deviceId ?? "").trim()
  if (deviceId.length < 16 || deviceId.length > 64) return json({ error: "invalid_device" }, 400)

  try {
    if (body.action === "list") {
      const thread = await findThread(deviceId)
      if (thread && body.markRead === true) {
        await supabase.from("support_threads").update({ unread_user: false }).eq("id", thread.id)
      }
      return json({ messages: thread ? await messagesFor(thread) : [] }, 200)
    }
    if (body.action === "status") {
      const { data } = await supabase
        .from("support_threads")
        .select("id, unread_user")
        .eq("device_id", deviceId)
        .maybeSingle()
      if (!data || !data.unread_user) return json({ unread: false, preview: null }, 200)
      const { data: last } = await supabase
        .from("support_messages")
        .select("body")
        .eq("thread_id", data.id)
        .eq("sender", "admin")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle()
      return json({ unread: true, preview: last?.body ? String(last.body).slice(0, 140) : null }, 200)
    }
    if (body.action === "send") return await send(req, deviceId, body)
    return json({ error: "unknown_action" }, 400)
  } catch (error) {
    console.error("support-chat failed", (error as Error).message ?? error)
    return json({ error: "server_error" }, 500)
  }
})

async function send(req: Request, deviceId: string, body: Record<string, unknown>) {
  const { data: config } = await supabase.from("app_config").select("value").eq("key", "chat_enabled").maybeSingle()
  if (config && config.value === false) return json({ error: "chat_disabled" }, 503)

  const text = String(body.body ?? "").trim()
  if (!text || text.length > MAX_BODY) return json({ error: "invalid_message" }, 400)
  const language = LANGUAGES.includes(String(body.language)) ? String(body.language) : "en"

  const { data: allowed } = await supabase.rpc("check_rate_limit", {
    p_bucket: "support-send",
    p_key: deviceId,
    p_limit: 10,
    p_window_minutes: 60,
  })
  if (allowed === false) return json({ error: "rate_limited" }, 429)

  const identity = await sessionIdentity(req)
  const context = parseContext(body.context)

  const { data: before } = await supabase
    .from("support_threads")
    .select("unread_admin")
    .eq("device_id", deviceId)
    .maybeSingle()
  const shouldNotify = !before || before.unread_admin === false

  const thread = await upsertThread(deviceId, identity, context, language)

  const { error: insertError } = await supabase
    .from("support_messages")
    .insert({ thread_id: thread.id, sender: "user", body: text, context: { ...context, ...identity } })
  if (insertError) throw insertError

  const reply = await autoReplyFor(text, language)
  if (reply) {
    await supabase.from("support_messages").insert({ thread_id: thread.id, sender: "auto", body: reply })
  }

  if (shouldNotify) {
    try {
      await notifyAdmins(text, thread.id, identity, context)
    } catch (error) {
      console.error("admin push failed", (error as Error).message ?? error)
    }
  }

  return json({ messages: await messagesFor(thread) }, 200)
}

async function upsertThread(deviceId: string, identity: Identity, context: Context, language: string) {
  const { data, error } = await supabase
    .from("support_threads")
    .upsert(
      {
        device_id: deviceId,
        unread_admin: true,
        status: "open",
        last_message_at: new Date().toISOString(),
        user_id: identity.userId,
        user_email: identity.email,
        device_model: context.model,
        os_version: context.osVersion,
        app_version: context.appVersion,
        build: context.build,
        locale: context.locale,
        language,
      },
      { onConflict: "device_id" },
    )
    .select("id")
    .single()
  if (error) throw error
  return data as { id: string }
}

async function findThread(deviceId: string) {
  const { data } = await supabase.from("support_threads").select("id").eq("device_id", deviceId).maybeSingle()
  return data as { id: string } | null
}

async function messagesFor(thread: { id: string }): Promise<Message[]> {
  const { data, error } = await supabase
    .from("support_messages")
    .select("id, sender, body, created_at")
    .eq("thread_id", thread.id)
    .order("created_at", { ascending: true })
    .limit(200)
  if (error) throw error
  return (data ?? []) as Message[]
}

async function autoReplyFor(text: string, language: string): Promise<string | null> {
  const { data } = await supabase
    .from("support_auto_replies")
    .select("keywords, reply_en, reply_he, reply_ar")
    .eq("enabled", true)
  const lower = text.toLowerCase()
  for (const rule of (data ?? []) as Record<string, unknown>[]) {
    const keywords = (rule.keywords as string[]) ?? []
    if (!keywords.some((k) => lower.includes(k.toLowerCase()))) continue
    const picked = (rule[`reply_${language}`] as string | null) || (rule.reply_en as string | null)
    if (picked) return picked
  }
  return null
}

// MARK: - Who is writing

/// The account behind the session token, if any. The app's publishable key is not
/// a user token, so an anonymous install simply has no identity.
async function sessionIdentity(req: Request): Promise<Identity> {
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? ""
  if (token.split(".").length !== 3) return { userId: null, email: null }
  const { data, error } = await supabase.auth.getUser(token)
  if (error || !data.user) return { userId: null, email: null }
  return { userId: data.user.id, email: data.user.email ?? null }
}

function clip(value: unknown, max: number): string | null {
  const text = String(value ?? "").trim().slice(0, max)
  return text || null
}

function parseContext(value: unknown): Context {
  const raw = (value && typeof value === "object" ? value : {}) as Record<string, unknown>
  return {
    model: clip(raw.model, 40),
    osVersion: clip(raw.osVersion, 20),
    appVersion: clip(raw.appVersion, 20),
    build: clip(raw.build, 20),
    locale: clip(raw.locale, 20),
  }
}

// MARK: - Admin push

async function notifyAdmins(text: string, threadId: string, identity: Identity, context: Context) {
  const jwt = await apnsJWT()
  if (!jwt) return
  const { data: admins } = await supabase.from("admins").select("user_id")
  const ids = (admins ?? []).map((a) => a.user_id)
  if (ids.length === 0) return
  const { data: devices } = await supabase
    .from("devices")
    .select("id, apns_token, apns_env")
    .in("user_id", ids)
    .not("apns_token", "is", null)
  const preview = text.length > 80 ? `${text.slice(0, 80)}…` : text
  const who = identity.email ?? "no account"
  const device = [context.model, context.osVersion ? `iOS ${context.osVersion}` : null,
    context.appVersion ? `v${context.appVersion}${context.build ? ` (${context.build})` : ""}` : null]
    .filter(Boolean).join(" · ")
  const title = `Support · ${who}`
  const bodyText = device ? `${preview}\n${device}` : preview
  await Promise.all((devices ?? []).map((d) => deliver(jwt, d, title, bodyText, threadId)))
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

async function deliver(
  jwt: string,
  device: { id: string; apns_token: string; apns_env: string },
  title: string,
  body: string,
  threadId: string,
) {
  const host = device.apns_env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com"
  try {
    const res = await fetch(`https://${host}/3/device/${device.apns_token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: { alert: { title, body }, sound: "default" },
        supportThreadId: threadId,
      }),
    })
    if (!res.ok) console.error("support push failed", res.status, await res.text())
  } catch (error) {
    console.error("support push error", (error as Error).message)
  }
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
