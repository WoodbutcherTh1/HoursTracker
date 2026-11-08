// Admin operations: live overview, kill switches, audit log. Same rule as admin-api:
// the caller must be signed in and listed in public.admins, checked on every call.
//
// POST {"action": ...}
//   overview                       → aggregate numbers only (admin_overview())
//   set_switch {key, enabled}      → { ok }   key: ai_enabled | chat_enabled (logged)
//   audit_log                      → { entries } (latest 50)
import { createClient } from "jsr:@supabase/supabase-js@2"

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
)

const SWITCHES = ["ai_enabled", "chat_enabled"]

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
      case "overview": {
        const { data, error } = await supabase.rpc("admin_overview")
        if (error) throw error
        return json(data, 200)
      }
      case "set_switch": {
        const key = String(body.key ?? "")
        if (!SWITCHES.includes(key) || typeof body.enabled !== "boolean") return json({ error: "invalid_switch" }, 400)
        const { error } = await supabase
          .from("app_config")
          .upsert({ key, value: body.enabled, updated_at: new Date().toISOString() })
        if (error) throw error
        await supabase.from("admin_audit_log").insert({
          admin_id: userId,
          action: "set_switch",
          details: { key, enabled: body.enabled },
        })
        return json({ ok: true }, 200)
      }
      case "audit_log": {
        const { data, error } = await supabase
          .from("admin_audit_log")
          .select("id, action, details, created_at")
          .order("created_at", { ascending: false })
          .limit(50)
        if (error) throw error
        return json({ entries: data ?? [] }, 200)
      }
      default:
        return json({ error: "unknown_action" }, 400)
    }
  } catch (error) {
    console.error("admin-ops failed", (error as Error).message ?? error)
    return json({ error: "server_error" }, 500)
  }
})

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
