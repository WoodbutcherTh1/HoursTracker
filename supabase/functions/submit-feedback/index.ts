// Proxies HoursTracker's in-app feedback to Telegram so the bot token never
// ships inside the app bundle. The app has no user accounts (see the app's
// own code — there's no sign-in), so this can't be gated on a Supabase Auth
// session; abuse control instead comes from a per-IP rate limit backed by
// `public.feedback_rate_limit` (see ../../migrations).
//
// Required secrets (set with `supabase secrets set`, never committed):
//   TELEGRAM_BOT_TOKEN
//   TELEGRAM_CHAT_ID
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected by the
// Supabase Edge Runtime.
import { createClient } from "jsr:@supabase/supabase-js@2"

const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN")
const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID")
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

const RATE_LIMIT_COUNT = 10
const RATE_LIMIT_WINDOW_MINUTES = 60

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

interface FeedbackPayload {
  text?: string
  documentBase64?: string
  documentName?: string
  caption?: string
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405)
  }
  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    return json({ error: "Not configured" }, 503)
  }

  const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "0.0.0.0"
  const { data: allowed, error: rlError } = await supabase.rpc("check_feedback_rate_limit", {
    client_ip: clientIp,
    limit_count: RATE_LIMIT_COUNT,
    window_minutes: RATE_LIMIT_WINDOW_MINUTES,
  })
  if (rlError) {
    console.error("rate limit check failed", rlError)
  } else if (allowed === false) {
    return json({ error: "Too many requests" }, 429)
  }

  let body: FeedbackPayload
  try {
    body = await req.json()
  } catch {
    return json({ error: "Invalid JSON" }, 400)
  }

  if (!body.text && !(body.documentBase64 && body.documentName)) {
    return json({ error: "Missing text or document" }, 400)
  }

  if (body.text) {
    const sendResult = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      // No parse_mode: the text is free-form user input, and Telegram rejects
      // HTML/MarkdownV2 payloads with unescaped entities.
      body: JSON.stringify({
        chat_id: TELEGRAM_CHAT_ID,
        text: body.text,
        disable_web_page_preview: true,
      }),
    })
    if (!sendResult.ok) {
      console.error("telegram sendMessage failed", sendResult.status, await sendResult.text())
      return json({ error: "Failed to send" }, 502)
    }
  }

  if (body.documentBase64 && body.documentName) {
    // Best-effort: a failed attachment should never fail the whole request.
    try {
      await sendDocument(body.documentBase64, body.documentName, body.caption ?? "")
    } catch (err) {
      console.error("telegram sendDocument failed", err)
    }
  }

  return json({ success: true }, 200)
})

async function sendDocument(base64: string, fileName: string, caption: string) {
  const fileBytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))
  const boundary = `----hourstracker-${crypto.randomUUID()}`
  const enc = new TextEncoder()

  const head = [
    `--${boundary}\r\n`,
    `Content-Disposition: form-data; name="chat_id"\r\n\r\n${TELEGRAM_CHAT_ID}\r\n`,
    ...(caption ? [`--${boundary}\r\n`, `Content-Disposition: form-data; name="caption"\r\n\r\n${caption}\r\n`] : []),
    `--${boundary}\r\n`,
    `Content-Disposition: form-data; name="document"; filename="${fileName}"\r\nContent-Type: text/plain\r\n\r\n`,
  ].join("")
  const tail = `\r\n--${boundary}--\r\n`

  const headBytes = enc.encode(head)
  const tailBytes = enc.encode(tail)
  const body = new Uint8Array(headBytes.length + fileBytes.length + tailBytes.length)
  body.set(headBytes, 0)
  body.set(fileBytes, headBytes.length)
  body.set(tailBytes, headBytes.length + fileBytes.length)

  const res = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument`, {
    method: "POST",
    headers: { "Content-Type": `multipart/form-data; boundary=${boundary}` },
    body,
  })
  if (!res.ok) {
    throw new Error(`sendDocument failed: ${res.status} ${await res.text()}`)
  }
}

function json(data: unknown, status: number) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}
