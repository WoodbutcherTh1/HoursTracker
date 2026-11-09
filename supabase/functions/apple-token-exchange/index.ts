// Exchanges a native Sign in with Apple authorization code for a refresh
// token and stores it, so delete-account can revoke it later. Must run right
// after signInWithApple — Apple's authorization code expires in minutes and
// can only be exchanged once, so it is useless by the time an account is
// actually deleted.
//
// Deployed with verify_jwt = true (see ../../config.toml): only a signed-in
// session reaches this code. The account is taken ONLY from the verified
// session token — never from the request body.
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected by the Edge
// Runtime. The apple_refresh_tokens table is RLS-locked with no policies
// (see ../../migrations) — only this function and delete-account touch it.
import { createClient } from "jsr:@supabase/supabase-js@2"
import { APPLE_CLIENT_ID, appleClientSecret } from "../_shared/apple.ts"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
})

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? ""
  if (!token) return json({ error: "Not signed in" }, 401)
  const { data, error: userError } = await supabase.auth.getUser(token)
  const userId = data?.user?.id
  if (userError || !userId) return json({ error: "Not signed in" }, 401)

  const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "0.0.0.0"
  const { data: allowed, error: rateLimitError } = await supabase.rpc("check_rate_limit", {
    p_bucket: "apple-token-exchange:ip",
    p_key: clientIp,
    p_limit: 20,
    p_window_minutes: 60,
  })
  if (rateLimitError) console.error("apple-token-exchange: rate limit check failed", rateLimitError.message)
  else if (allowed === false) return json({ error: "rate_limited" }, 429)

  let body: { code?: string }
  try {
    body = await req.json()
  } catch {
    return json({ error: "invalid_body" }, 400)
  }
  const code = (body.code ?? "").trim()
  if (!code || code.length > 2000) return json({ error: "invalid_code" }, 400)

  let clientSecret: string
  try {
    clientSecret = await appleClientSecret()
  } catch (err) {
    console.error("apple-token-exchange: client secret", err)
    return json({ error: "server_misconfigured" }, 500)
  }

  const tokenResponse = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: APPLE_CLIENT_ID,
      client_secret: clientSecret,
      code,
      grant_type: "authorization_code",
    }),
  })
  if (!tokenResponse.ok) {
    console.error("apple-token-exchange: Apple token endpoint", tokenResponse.status, await tokenResponse.text())
    return json({ error: "apple_exchange_failed" }, 502)
  }

  const tokens = (await tokenResponse.json()) as { refresh_token?: string }
  if (!tokens.refresh_token) {
    console.error("apple-token-exchange: no refresh_token in Apple's response")
    return json({ error: "apple_exchange_failed" }, 502)
  }

  const { error: upsertError } = await supabase
    .from("apple_refresh_tokens")
    .upsert({ user_id: userId, refresh_token: tokens.refresh_token, updated_at: new Date().toISOString() })
  if (upsertError) {
    console.error("apple-token-exchange: store", upsertError.message)
    return json({ error: "server_error" }, 500)
  }

  return json({ success: true }, 200)
})

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}
