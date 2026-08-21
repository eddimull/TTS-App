# Offline resilience — fail fast, then fall back to disk

## The report

> "If I'm connected to Wi-Fi that has no internet connection, the app
> immediately stalls and I get infinite loading."

Reproducible on any joined-but-dead network: a router with no upstream, a hotel
or venue captive portal that hasn't been clicked through, a phone that has held
onto an access point it can no longer route through. Venues are full of these,
which is exactly where this app gets used.

## Why it stalled

Four separate causes stacked up. Fixing any one alone still leaves a spinner.

1. **Requests had no hard ceiling.** `connectTimeout` on `dart:io` is applied to
   `HttpClient.connectionTimeout`, whose timer only starts once the host has
   been *resolved*. A DNS lookup that never gets an answer — the normal outcome
   on a dead network — is outside its reach, so a request could hang for as long
   as the platform resolver kept retrying.
2. **Every provider retried forever.** `_retryPolicy` in `main.dart` returned a
   backoff `Duration` for any error without a response, with no attempt cap. A
   provider that failed on a dead network went straight back to loading, in a
   loop, for as long as the network stayed down.
3. **The router waits on auth.** `redirect` returns `null` ("stay put") while
   `authProvider` is loading, and `AuthNotifier.build()` awaits `getMe()`. A
   hung `getMe()` meant the restored route rendered its own spinner with nothing
   behind it.
4. **The offline banner lied.** `connectivity_plus` answers "is this device
   attached to a network?", and a dead Wi-Fi answers yes. So the one piece of UI
   that could have explained the wait stayed hidden.

None of them told the user anything, and there was no cached data to show even
if they had.

## Design

Four layers, each of which independently shortens the stall.

### 1. A hard deadline on every request

`DeadlineHttpClientAdapter` wraps the real adapter and applies a wall-clock
timeout to `fetch`, covering resolution, connect, TLS and time-to-first-byte —
everything `connectTimeout` can't see. 10s for ordinary requests, 5 minutes for
multipart (`fetch` doesn't complete until the whole body has gone out), and a
per-request override via `extra[kRequestDeadlineKey]`.

The response *body* is still governed by `receiveTimeout`, which Dio applies
between chunks, so large downloads on a slow connection are unaffected.

### 2. A circuit breaker on reachability

`Reachability` tracks whether the app can actually reach its API, which is a
different question from the one `connectivity_plus` answers. The only reliable
evidence is a request that completed, so that's what it tracks:

- **closed** (online) — everything goes to the wire.
- **open** (offline, within `retryAfter`) — requests are rejected immediately,
  so a screen renders its offline state at once rather than after a timeout.
- **half-open** (offline, `retryAfter` elapsed) — the next request is let
  through to test the water; siblings behind it still short-circuit, so exactly
  one probe goes out per window.

Any completed round trip closes it, *including a 4xx or 5xx* — the server
answered, so the network is demonstrably fine. Losing the transport entirely
opens it without waiting for a request to fail.

This is what turns the stall from "every screen waits out its own timeout" into
"one bounded wait, then instant answers".

### 3. Disk fallback for reads

`ApiResponseCache` (`SharedPreferences`, mirroring `BookingsCacheStorage`) holds
the last successful response for each GET. `OfflineInterceptor` writes to it on
success and replays from it when a request can't reach the server, so lists and
detail screens still render. Because it lives in the API client, every
repository gets this without changing a line.

Bounded to 64 entries and 192 KB each, least-recently-written evicted first —
`SharedPreferences` is read into memory at startup, so an unbounded cache would
be paid for on every launch.

Deliberately **not** cached: `/api/mobile/auth/`, `/api/mobile/token/`,
`/api/mobile/account`. `SharedPreferences` is not encrypted, and the session
already has an offline home in `SecureStorage` — see
`AuthNotifier._restoreCachedSession`, which is what lets a cold start offline
restore a signed-in session.

Writes are never replayed or queued. A booking edit that never reached the
server must surface as a failure, not silently appear to have worked.

### 4. Honest UI, and recovery

- `connectivityProvider` now combines the device transport with `Reachability`,
  so the offline banner appears on a dead network instead of staying hidden.
- Joining a network doesn't clear the banner on its own — the new network may be
  just as dead. The provider fires `ApiClient.probeReachability()` (an
  unauthenticated `HEAD /`) and lets the answer decide.
- `ErrorView.friendlyMessage` returns connectivity copy with a wifi-slash icon
  for transport failures, instead of `DioException.toString()`. All 35 call
  sites improve without changing any of them.
- When connectivity returns, `AppScaffold` calls
  `BandRealtimeNotifier.refreshAll()` — the same blanket refetch the app already
  does on resume, since screens may be showing replayed data and any realtime
  signal sent while we were dark was missed.
- `_retryPolicy` is capped at 3 attempts, and skips retrying a request the
  client short-circuited (retrying can only reproduce the same instant
  rejection).

## What the user sees now

| | Before | After |
|---|---|---|
| Cold start on dead Wi-Fi | Spinner, indefinitely | One bounded wait (≤10s), then the last-known data with an offline banner |
| Any tap after that | Another spinner | Answered immediately |
| Screen with no cached data | Spinner, indefinitely | "You're offline. Reconnect and try again." with Retry |
| Saving something | Spinner, indefinitely | Fails promptly and says why |
| Reconnecting | Nothing until the next tap | Banner clears, data refetches |

## Known limits / out of scope

- **The first round trip on a dead network still waits.** Nothing can know the
  network is dead until something has tried it. That wait is now bounded by the
  deadline instead of being open-ended, and it is paid once.
- **No offline write queue.** Mutations fail with a clear message. (Media
  uploads keep their own `UploadQueueStorage` retry path.)
- **Replayed data isn't individually marked stale.** The shell's offline banner
  is the caveat. `extra[kFromCacheKey]` / `extra[kCachedAtKey]` are stamped on
  replayed responses for a future "last updated" affordance.
- **A captive portal can briefly answer the probe.** It will report reachable
  until the next real API request fails, which then re-opens the circuit. The
  flap is self-correcting and costs one request.
