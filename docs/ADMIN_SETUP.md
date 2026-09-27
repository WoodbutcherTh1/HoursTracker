# Owner dashboard — one-time setup (Phase 6)

The code is in the repo; these steps turn it on. None of them put a secret in
the repo or in chat.

## 1. Apple Push key (`.p8`)

1. developer.apple.com → Certificates, IDs & Profiles → **Keys** → **+**.
2. Name it e.g. "HoursTracker Push", tick **Apple Push Notifications service (APNs)**,
   Continue → Register → **Download** `AuthKey_XXXXXXXXXX.p8` (downloadable once — keep it safe).
3. Note the **Key ID** (10 characters) and your **Team ID** (`FQUC6DU87N`).
4. Identifiers → `com.hourstracker.app` → make sure **Push Notifications** is ticked
   (Xcode's automatic signing usually does this after the new entitlement).

## 2. Supabase secrets (Dashboard → Edge Functions → Secrets)

| Name | Value |
|---|---|
| `APNS_KEY_P8` | the whole contents of the `.p8` file (including the BEGIN/END lines) |
| `APNS_KEY_ID` | the Key ID |
| `APNS_TEAM_ID` | `FQUC6DU87N` |
| `APNS_BUNDLE_ID` | `com.hourstracker.app` |

Paste the `.p8` only here — never in chat, Git, or the app.

## 3. Database + functions

1. Apply `supabase/migrations/20260927100000_admin_devices_announcements.sql`.
2. Deploy `register-device` and `admin-api` **with JWT verification off**
   (`supabase/config.toml`; the functions verify the session themselves).
3. Make the owner accounts admins (run once in the SQL editor). Both are
   `owner`; more admins can be added the same way with role `admin`:

```sql
insert into public.admins (user_id, role)
select id, 'owner' from auth.users
where lower(email) in ('hmam.kaadna@gmail.com', 'info.hourstracker@gmail.com')
on conflict (user_id) do update set role = 'owner';
```

## 4. Use it

Sign in to that account in the app → Settings → **Admin** → Owner dashboard.
Write the message in one language, tap *Translate* (uses your Gemini key from
Settings → Smart scanner), review the other two, pick the audience, check the
count, confirm.

Notes:
- Debug builds from Xcode register as `sandbox`, TestFlight/App Store as
  `production`; APNs is chosen per device automatically.
- Until the secrets are set, sending still works for the in-app banner and the
  result says push isn't configured.
- Sends are limited to 10 per hour per admin.
