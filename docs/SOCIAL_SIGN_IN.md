# Sign in with Apple & Google — setup

The code is in `SupabaseAuthManager` (`signInWithApple`, `signInWithGoogle`) and
`AccountSheet.swift` (`SocialSignInButtons`, shown on the Welcome and Sign-in
steps). Nothing works until the steps below are done once.

## 1. Apple

1. **Xcode / Apple Developer:** the entitlement `com.apple.developer.applesignin`
   is already in `HoursTracker.entitlements`. With automatic signing, Xcode turns
   on the *Sign in with Apple* capability for `com.hourstracker.app` on the next
   build. If it doesn't: developer.apple.com → Identifiers → com.hourstracker.app →
   enable **Sign in with Apple**.
2. **Supabase dashboard:** Authentication → Sign In / Providers → **Apple** →
   enable, and put `com.hourstracker.app` in **Client IDs**. For native iOS
   sign-in no secret key is needed.

## 2. Google

1. **Google Cloud Console** → APIs & Services → Credentials → *Create OAuth
   client ID* → type **Web application**.
   - Authorized redirect URI: `https://<project-ref>.supabase.co/auth/v1/callback`
     (copy it from the Supabase Google provider page).
   - OAuth consent screen: app name *HoursTracker*, support email, logo,
     privacy-policy URL.
2. **Supabase dashboard:** Authentication → Providers → **Google** → enable,
   paste the Web client ID and secret.
3. **Supabase dashboard:** Authentication → URL Configuration → **Redirect URLs**
   → add `hourstracker://auth-callback`.
4. **Assets:** add Google's official "G" logo (from Google's sign-in branding
   guidelines) to `Assets.xcassets` as an image set named **`GoogleG`**. Until
   then the button shows text only.

## 3. Behaviour

- First tap creates the account; later taps sign back in. No password, no code.
- After sign-in: an existing backup is restored and merged into the device; a
  brand-new account gets this device's data uploaded (same as email sign-up).
- Apple may give a private relay e-mail (`…@privaterelay.appleid.com`) — treated
  like any other address.
- Apple sends the person's name only on the first authorization; it is saved to
  the account's metadata immediately.
- "Forgot password" only applies to e-mail accounts. Apple/Google users have no
  HoursTracker password.

## 4. Still to do

- **Account deletion with Apple:** Apple requires revoking the user's Apple
  token when an account created with Sign in with Apple is deleted. The
  `delete-account` Edge Function must call Apple's `/auth/revoke` endpoint
  (needs a Sign in with Apple key `.p8`, Key ID and Team ID as function
  secrets). Not implemented yet.
- **Same e-mail on two methods:** Supabase links identities that share a
  verified e-mail automatically; check this matches what we want.
