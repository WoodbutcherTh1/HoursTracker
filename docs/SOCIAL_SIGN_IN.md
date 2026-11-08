# Sign in with Google & Apple — setup

The code is in `SupabaseAuthManager` (`signInWithGoogle`, `signInWithApple`) and
`AccountSheet.swift` (`AccountWelcomeView`'s Apple/Google buttons,
`SocialSignInFinisher`, `AppleSignInCoordinator`).

## Google — done, live

1. **Google Cloud Console**: OAuth consent screen (External, scopes
   `openid`/`email`/`profile` only — Google's non-sensitive tier, so
   publishing to Production needs no verification review) + a **Web
   application** OAuth client, with the Supabase callback
   (`https://rocjprrvrvmtisxnvopg.supabase.co/auth/v1/callback`) as its
   Authorized redirect URI.
2. **Supabase dashboard**: Authentication → Providers → **Google** → enabled,
   Web client ID + secret pasted in. Authentication → URL Configuration →
   Redirect URLs → `hourstracker://auth-callback` added.
3. **App**: no Info.plist change needed — `hourstracker://` is already a
   registered URL scheme (used for widget/quick-action deep links), and
   `supabase-swift`'s `signInWithOAuth` drives the whole
   `ASWebAuthenticationSession` round-trip internally.
4. Before publishing the consent screen to Production: it needs a public
   **privacy policy URL** (`docs/privacy-policy.html` in this repo, hosted via
   GitHub Pages or similar — the in-app `PrivacyPolicyView.swift` isn't
   reachable by Google's crawler).

## Apple — code ready, blocked on a paid Developer account

1. **Xcode / Apple Developer**: `com.apple.developer.applesignin` needs to be
   added to `HoursTracker.entitlements`, and the App ID
   (`com.hourstracker.app`) needs the Sign in with Apple capability enabled at
   developer.apple.com. **Both require a paid Apple Developer Program
   membership** — unlike App Groups (used for the widget), which works on a
   free/personal team. Do this only after upgrading; adding the entitlement
   on a free team breaks code signing.
2. **Supabase dashboard**: Authentication → Sign In / Providers → **Apple** →
   enable, put `com.hourstracker.app` in **Client IDs**. No secret needed for
   native iOS sign-in. Safe to do anytime — doesn't touch the Apple Developer
   account.
3. **App**: the button, `AppleSignInCoordinator`, and
   `SupabaseAuthManager.signInWithApple` are already wired and compile. Until
   step 1 is done, tapping "Continue with Apple" fails at the OS layer with an
   `ASAuthorizationError` (the button's error banner will show
   `L10n.accountErrorSocial`) — this is expected, not a bug to chase.

## Behaviour (both providers)

- First tap creates the account; later taps sign back in. No password, no
  code.
- After sign-in: an existing backup is restored and merged into the device
  (`SocialSignInFinisher`); a brand-new account gets this device's data
  uploaded (same pattern as email sign-up).
- Apple may give a private relay e-mail (`…@privaterelay.appleid.com`) —
  treated like any other address.
- Apple sends the person's name only on the first authorization; it is saved
  to the account's metadata immediately.
- "Forgot password" only applies to e-mail accounts. Google/Apple users have
  no HoursTracker password.

## Still to do

- **Account deletion with Apple**: once Apple sign-in is live, Apple requires
  revoking the user's Apple token when an account created with Sign in with
  Apple is deleted. The `delete-account` Edge Function must call Apple's
  `/auth/revoke` endpoint (needs a Sign in with Apple key `.p8`, Key ID and
  Team ID as function secrets). Not implemented yet.
- **Same e-mail on two methods**: Supabase links identities that share a
  verified e-mail automatically; check this matches what we want once more
  than one provider is actually live.
