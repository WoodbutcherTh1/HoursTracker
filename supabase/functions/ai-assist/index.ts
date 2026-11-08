// Free AI for HoursTracker. The Gemini key lives in the secret GEMINI_API_KEY on
// the server, never in the app. Quotas are enforced atomically in Postgres by
// consume_ai_quota (Israel calendar day for the daily limit, rolling 7 days for
// the weekly limit, and a global daily cap that protects the free tier).
//
// Required secret: GEMINI_API_KEY
// Optional: AI_DAILY_LIMIT (default 3), AI_WEEKLY_LIMIT (default 10),
//           AI_GLOBAL_DAILY_CAP (default 800), AI_MODEL (default gemini-3.5-flash-lite)
//
// `deviceId` is the caller's own claim and consume_ai_quota only counts by that
// string — it is never checked against public.devices. Without the per-IP limit
// below, anyone holding the app's publishable key (meant to be public) could mint
// a fresh deviceId per request and both bypass the per-device daily/weekly limits
// and burn through AI_GLOBAL_DAILY_CAP, denying the service to every real user
// for the rest of the day. The IP check is the actual backstop; requiring a
// well-formed install id (the same UUID register-device requires) just removes
// the cheapest way to mint "new" identities.
import { createClient } from "jsr:@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")
const DAILY = Number(Deno.env.get("AI_DAILY_LIMIT") ?? 3)
const WEEKLY = Number(Deno.env.get("AI_WEEKLY_LIMIT") ?? 10)
const GLOBAL = Number(Deno.env.get("AI_GLOBAL_DAILY_CAP") ?? 800)
const MODEL = Deno.env.get("AI_MODEL") ?? "gemini-3.5-flash-lite"

const MAX_PROMPT = 4000
const MAX_IMAGE_B64 = 6_000_000
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
// Generous for one real device (the app calls this at most a handful of times
// a day per its own quota) but tight enough that minting new deviceIds from one
// IP stops paying off well before AI_GLOBAL_DAILY_CAP does.
const IP_LIMIT = 20
const IP_WINDOW_MINUTES = 60

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

interface Payload {
  deviceId?: string
  prompt?: string
  imageBase64?: string
  mimeType?: string
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405)
  if (!GEMINI_API_KEY) return json({ error: "not_configured" }, 503)

  let body: Payload
  try {
    body = await req.json()
  } catch {
    return json({ error: "invalid_json" }, 400)
  }

  const deviceId = (body.deviceId ?? "").trim()
  const prompt = (body.prompt ?? "").trim()
  if (!UUID_RE.test(deviceId)) return json({ error: "invalid_device" }, 400)
  if (!prompt || prompt.length > MAX_PROMPT) return json({ error: "invalid_prompt" }, 400)
  if (body.imageBase64 && body.imageBase64.length > MAX_IMAGE_B64) return json({ error: "image_too_large" }, 413)

  const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "0.0.0.0"
  const { data: ipAllowed, error: ipError } = await supabase.rpc("check_rate_limit", {
    p_bucket: "ai-assist:ip",
    p_key: clientIp,
    p_limit: IP_LIMIT,
    p_window_minutes: IP_WINDOW_MINUTES,
  })
  if (ipError) {
    console.error("ip rate limit check failed", ipError)
  } else if (ipAllowed === false) {
    return json({ error: "quota_exceeded", reason: "ip" }, 429)
  }

  const { data: quota, error: quotaError } = await supabase.rpc("consume_ai_quota", {
    p_device: deviceId,
    p_daily: DAILY,
    p_weekly: WEEKLY,
    p_global: GLOBAL,
  })
  if (quotaError) {
    console.error("quota check failed", quotaError)
    return json({ error: "temporarily_unavailable" }, 503)
  }
  const q = quota as { allowed: boolean; reason?: string; remaining_day?: number; remaining_week?: number }
  if (!q.allowed) {
    return json({ error: "quota_exceeded", reason: q.reason ?? "daily" }, 429)
  }

  const parts: unknown[] = [{ text: prompt }]
  if (body.imageBase64) {
    parts.unshift({
      inline_data: { mime_type: body.mimeType ?? "image/jpeg", data: body.imageBase64 },
    })
  }

  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
    body: JSON.stringify({
      contents: [{ role: "user", parts }],
      generationConfig: { temperature: 0.2, responseMimeType: "application/json" },
    }),
  })

  if (!res.ok) {
    console.error("gemini failed", res.status, await res.text())
    return json({ error: "provider_failed", remaining_day: q.remaining_day, remaining_week: q.remaining_week }, 502)
  }

  const data = await res.json()
  const text = data?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text ?? "").join("") ?? ""
  return json({ text, remaining_day: q.remaining_day, remaining_week: q.remaining_week }, 200)
})

function json(data: unknown, status: number) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}
