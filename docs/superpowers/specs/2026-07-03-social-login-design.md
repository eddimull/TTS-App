# Social Login — Design

**Date:** 2026-07-03
**Scope:** Google, Apple, and Facebook sign-in across the Flutter mobile app (`tts_bandmate`) and the Laravel web app + mobile API (`TTS`).
**Approach:** Native SDKs on mobile with server-side token verification; Laravel Socialite redirect flow on web. One shared resolution service on the backend.

## Goals

- Users can sign in / sign up with Google, Apple, or Facebook on the mobile app and on the web login/register pages.
- A social sign-in with an email that already has a password account **auto-links by email** and logs into that account (providers verify emails, so this is safe).
- Social signup honors pending band invitations / event-sub invitations exactly like email signup does.
- The mobile API response envelope is unchanged — the Flutter parsing layer (`{token, user, bands}`) stays as-is.

## Non-goals (YAGNI)

- No "unlink provider" or account-management UI. A social-only user who wants password login uses the existing "Forgot password" reset flow, which sets a password.
- No avatar sync into the app UI (we store `avatar_url` on the link row for future use; `TokenService::formatUser` keeps returning what it returns today).
- No email verification gate — mobile login has none today; social providers verify emails anyway.
- No web-JS SDKs; web is pure server-side redirect flow.

## Backend (TTS Laravel repo)

### Packages

- `laravel/socialite`
- `socialiteproviders/apple` (Apple is not a first-party Socialite driver)
- Credentials in `config/services.php` under `google`, `apple`, `facebook` keys (client id/secret, redirect URLs), fed by `.env`.

### Schema

Migration 1 — `social_accounts` table:

| column | type | notes |
|---|---|---|
| id | bigint PK | |
| user_id | FK → users.id, cascade delete | |
| provider | string | `google` \| `apple` \| `facebook` |
| provider_id | string | provider's stable user id (Google `sub`, Apple `sub`, Facebook id) |
| avatar_url | string nullable | stored for future use |
| timestamps | | |

Unique index on `(provider, provider_id)`. Index on `user_id`.

Migration 2 — make `users.password` nullable (ALTER; the users table is legacy/externally managed and has no create migration, which is fine).

### `SocialAuthService`

Single entry point shared by web and mobile controllers:

```
resolveUser(string $provider, Socialite\Contracts\User $providerUser): User
```

1. Look up `social_accounts` by `(provider, provider_id)` → return the linked user.
2. Else look up `users` by the provider-supplied email → create the `social_accounts` row (auto-link) and return that user.
3. Else create a new user (`name`, `email` from the provider; `password = null`), create the link row, and run the shared pending-invitation acceptance logic.

In cases 2 and 3, also set `email_verified_at` if null — providers verify email ownership, and the web dashboard sits behind the `verified` middleware, so a social user with a NULL `email_verified_at` would be bounced to the verify-email page.

The invitation logic currently lives inline in `OnboardingController@register` (auto-accepts `EventSubs` and band `Invitations` matching the email, assigning roles). **Extract it** into a shared method (e.g., on a service or the User model) so email register and social register call the same code and cannot drift.

Apple caveat: Apple only supplies the user's name on the *first* authorization. If name is empty, fall back to the email local-part.

### Mobile endpoint

`POST /api/mobile/auth/social` (public) — request: `{provider, token, device_name}`.

- `provider` ∈ google|apple|facebook. Google and Apple send an **id_token**; Facebook sends an **access token**.
- Controller verifies the token **server-side** via `Socialite::driver($provider)->userFromToken(...)` (Apple id_tokens verified against Apple's JWKS via the socialiteproviders driver). Client-supplied profile data is never trusted.
- On success: `SocialAuthService::resolveUser(...)` → issue a Sanctum token via the existing `TokenService` (same abilities logic) → return the **identical** `{token, user, bands}` envelope as `POST /api/mobile/auth/token`.
- Invalid/expired provider token → 422 with a validation-style error message (matches existing login error shape).

Note: the Google id_token audience must accept the mobile OAuth client IDs (Android/iOS clients), not just the web client — the config needs the list of allowed client IDs.

### Web endpoints

- `GET /auth/{provider}/redirect` → `Socialite::driver($provider)->redirect()`
- `GET /auth/{provider}/callback` → `Socialite::driver($provider)->user()` → `SocialAuthService::resolveUser` → `Auth::login($user, remember: true)` → redirect to dashboard.
- Callback failure (user cancels, invalid state, provider error) → redirect to login page with a flash error message.
- Apple's callback is a `POST` (form_post response mode) — route and CSRF-exempt it accordingly.

## Web frontend (TTS Breeze pages)

- Login and register pages get an "or continue with" divider plus three buttons (Google, Apple, Facebook), each a plain link to `/auth/{provider}/redirect`.
- Buttons follow each provider's brand guidelines (official logos, approved colors/shape).
- A social-only user attempting password login gets the normal "credentials don't match" error; password reset flow works for them and doubles as "add a password".

## Mobile app (tts_bandmate Flutter repo)

### Packages

`google_sign_in`, `sign_in_with_apple`, `flutter_facebook_auth` (verify current versions at implementation time).

### UI

- `welcome_screen.dart`, `login_screen.dart`, `sign_up_screen.dart` each show the provider buttons; identical behavior on all three (backend find-or-creates).
- Apple button renders on iOS only. Google + Facebook render on Android and iOS.
- Cupertino styling consistent with the app; provider brand rules respected.
- Cancelling the native sheet returns silently — no error state.

### Flow

1. New `AuthNotifier.socialLogin(provider)`.
2. Native SDK returns the provider credential (Google/Apple → id_token, Facebook → access token).
3. New `AuthRepository.socialLogin(provider, token, deviceName)` posts to `/api/mobile/auth/social`.
4. Response parsed by the existing `(token, AuthUser, List<BandSummary>)` record path; token storage, push-token registration, and state transitions unchanged.
5. Backend/network failure → `AuthUnauthenticated(errorMessage)` like password login.

### Platform config

- **Android:** Google client via existing `google-services.json` (project `tts-band`); Facebook app id + client token in manifest/strings.
- **iOS:** Sign in with Apple capability in `Runner.entitlements`; `GIDClientID` + reversed-client-id URL scheme in `Info.plist`; Facebook `Info.plist` entries (FacebookAppID, client token, URL scheme, LSApplicationQueriesSchemes).

### Provider console prerequisites (human steps)

- **Google Cloud:** OAuth clients for Android (SHA-1), iOS (bundle id), and Web (for the Laravel web flow + server-side audience check).
- **Apple Developer:** Sign in with Apple capability on the app ID; a Services ID + private key for the web flow.
- **Meta Developer:** Facebook app with Facebook Login product, Android/iOS platforms configured, and app review/live mode for public use.

These will be a checklist in the implementation plan; several steps only the account owner can perform.

## Error handling summary

| Case | Behavior |
|---|---|
| User cancels native sheet (mobile) | Return to screen silently |
| Invalid/expired provider token (mobile API) | 422 validation-style error → error banner like bad password |
| Provider/callback error (web) | Redirect to login with flash message |
| Same email, existing password account | Auto-link, log in |
| Same provider account, different email than linked user | Provider link wins (lookup is by provider_id first) |
| Apple returns no name | Fall back to email local-part |

## Testing

- **Backend (Pest/PHPUnit, in Docker):** feature tests for `/api/mobile/auth/social` and web callback: new-user creation, auto-link by email, existing-link login, pending-invitation acceptance, invalid token → 422, null-password user can't password-login. Socialite faked/mocked at the driver boundary.
- **Flutter:** unit tests for `AuthRepository.socialLogin` and `AuthNotifier.socialLogin` transitions using the existing fake patterns; no attempt to unit-test native SDKs.
- **On-device:** manual verification of each provider flow (Google on Android + iOS, Apple on iOS, Facebook on both) once consoles are configured.

## Rollout order

1. Backend: migrations + Socialite + `SocialAuthService` + mobile endpoint + web routes (deployable dark — no UI links yet).
2. Web UI buttons (staging PR; staging auto-deploys).
3. Flutter: packages, repository/notifier, UI buttons, platform config.
4. Console/credential setup and on-device verification.
