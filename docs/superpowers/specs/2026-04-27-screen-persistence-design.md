# Screen Persistence Design

**Date:** 2026-04-27
**Status:** Approved

## Goal

When the user relaunches the app after a cold start, return them to the last screen they were on — including nested routes (e.g., `/bookings/42`) — provided it was visited within the last 24 hours and the user is still authenticated with a valid band selected. Clear the stored route on logout.

---

## Storage Layer

A new `RouteStorage` class lives in `lib/core/storage/route_storage.dart`, mirroring the existing `SecureStorage` pattern. It wraps `SharedPreferences` (already a project dependency) and manages two keys:

| Key | Value |
|-----|-------|
| `last_route` | Full path string, e.g. `/bookings/42` |
| `last_route_timestamp` | Epoch milliseconds as a string |

**Methods:**
- `readLastRoute()` → `String?`
- `readLastRouteTimestamp()` → `DateTime?`
- `writeLastRoute(String path)` — writes path + current timestamp atomically
- `clearLastRoute()` — deletes both keys

A `routeStorageProvider` exposes a `RouteStorage` instance via Riverpod (`FutureProvider<RouteStorage>`), since `SharedPreferences.getInstance()` is async. The `_RouterRefreshNotifier` awaits this provider before the redirect function reads from storage — if the provider is still loading, the redirect returns `null` (stay put) just like the existing auth-loading guard.

**Rationale for SharedPreferences over SecureStorage:** Route paths are not sensitive data. Using encrypted storage for them would be unnecessary. SharedPreferences is already a declared dependency.

---

## Route Tracking

A `RouteStorage` write is triggered on every navigation event inside the authenticated shell. This is implemented via a custom `NavigatorObserver` (`LastRouteObserver`) registered in GoRouter's `observers` list.

`LastRouteObserver` overrides `didPush`, `didReplace`, and `didPop`, reading the current route name from the `Route` argument and calling `routeStorage.writeLastRoute(path)`.

**Pre-auth routes are excluded.** The observer only writes routes that begin with a shell route prefix:
- `/dashboard`, `/search`, `/bookings`, `/library`, `/more`, `/band-settings`, `/finances`

Routes beginning with `/login`, `/signup`, `/bands`, `/events`, `/rehearsals`, `/media` are not persisted.

---

## Startup Restore Logic

The existing redirect function in `router.dart` already enforces auth and band-selection guards in sequence. A final step is added at the end of that chain:

1. Auth guard passes (user is authenticated)
2. Band-selection guard passes (valid band is selected)
3. Read `last_route` and `last_route_timestamp` from `RouteStorage`
4. If both exist, timestamp is within 24 hours, and path starts with a valid shell prefix → redirect to stored path
5. Otherwise → fall through to `/dashboard` as today

The `_RouterRefreshNotifier` watches `routeStorageProvider` so the router re-evaluates once `SharedPreferences` has initialised.

---

## Logout Cleanup

`authProvider.logout()` calls `routeStorage.clearLastRoute()` alongside its existing token/band-ID cleanup. This ensures a logged-out user always starts fresh at `/dashboard` after re-authenticating.

---

## Edge Cases

| Scenario | Behaviour |
|----------|-----------|
| Stored path points to deleted record (e.g. `/bookings/42`, booking no longer exists) | Navigate there; the feature screen handles the 404 normally — no special router logic needed |
| App relaunched after >24 hours | Timestamp check fails; fall through to `/dashboard` |
| User switches band | Band-selection guard runs before restore; restore still fires after guard passes (stored path may be from the previous band — acceptable, the screen will load or 404) |
| Pre-auth route somehow stored | Prefix check prevents restore; fall through to `/dashboard` |

---

## Files Touched

| File | Change |
|------|--------|
| `lib/core/storage/route_storage.dart` | New file — `RouteStorage` class + `routeStorageProvider` |
| `lib/core/config/router.dart` | Add `LastRouteObserver`, wire `routeStorageProvider` into `_RouterRefreshNotifier`, add restore step to redirect logic |
| `lib/features/auth/providers/auth_provider.dart` | Call `routeStorage.clearLastRoute()` in `logout()` |
| `pubspec.yaml` | No change — `shared_preferences` already declared |
