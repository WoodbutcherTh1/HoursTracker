// Deletes the caller's own account (App Store 5.1.1(v); privacy-law right to
// erasure). The account is taken ONLY from the verified session token — never
// from the request body — so a user can delete nobody but themselves.
//
// Deleting the auth user cascades to `profiles`, `user_backups` and `admins`
// (ON DELETE CASCADE). The user's rows in `devices` are removed first so no
// push token stays linked to the account.
//
// Deployed with verify_jwt = true: only a signed-in session reaches this code.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected by the Edge Runtime.
import { createClient } from "jsr:@supabase/supabase-js@2"

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

  const { error: devicesError } = await supabase.from("devices").delete().eq("user_id", userId)
  if (devicesError) {
    console.error("delete-account: devices", devicesError.message)
    return json({ error: "Could not delete account" }, 500)
  }

  // Support inbox: drop the account's email/link from its conversations (the
  // message text stays). Best-effort — a deployment without the support tables
  // must still be able to delete accounts.
  const { error: supportError } = await supabase.rpc("support_forget_user", { p_user_id: userId })
  if (supportError) console.error("delete-account: support", supportError.message)

  const { error: deleteError } = await supabase.auth.admin.deleteUser(userId)
  if (deleteError) {
    console.error("delete-account: user", deleteError.message)
    return json({ error: "Could not delete account" }, 500)
  }

  return json({ success: true }, 200)
})

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}
