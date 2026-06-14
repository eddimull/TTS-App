# Event-Day "Leave By" Notifications — Phase 2 (Location Enrichment) Design

**Date:** 2026-06-14
**Status:** Approved for planning
**Scope of this spec:** Flutter app (`tts_bandmate`) only. Builds on Phase 1 (push plumbing + time-based notifications). The Laravel backend push-sending service remains a separate spec.
**Phase 1 spec:** `docs/superpowers/specs/2026-06-13-event-leave-by-notifications-design.md`
**Phase 1 plan:** `docs/superpowers/plans/2026-06-13-leave-by-notifications-phase1.md`

## Summary

Phase 2 adds the device-side location intelligence that turns Phase 1's time-based reminders into the headline feature: a precise "leave by [time]" departure reminder computed from where the user actually is, and suppression of that reminder when the user has already left.

All computation happens on-device. Nothing new is sent to the server — the device never reports its location. The server's Phase 1 time-based push remains the guaranteed delivery floor; the device upgrades or suppresses it locally when it has location access.

## Goals

- When the app has location access, the "leave in 15 minutes" reminder fires 15 minutes before the user must depart (by live, traffic-aware travel time) to make the first timeline item.
- Suppress that reminder when the user has already left / arrived.
- Degrade gracefully across permission tiers, always falling back to Phase 1 behavior.
- Keep location on the device (privacy); add no backend endpoints.

## Non-Goals

- Server-side location enrichment / `POST /api/mobile/location` (dropped — superseded by on-device computation).
- Continuous background location tracking or geofencing.
- A buffer beyond live travel time (departure math is literal: `firstItem − travel`).
- Backend push-sending (separate spec).

## Architecture

Phase 2 adds three on-device capabilities on top of Phase 1's push plumbing:

1. **Location access** (`geolocator`) — tiered "always" permission with graceful degradation:
   - *always* granted → background push enrichment + already-left suppression
   - *while-in-use* only → foreground enrichment only (no background compute)
   - *denied* → Phase 1 server time-based push remains the floor; no enrichment
   Each tier degrades to the one below with no errors.

2. **Travel time** (Google **Routes API**, `computeRoutes`, traffic-aware driving) — a REST client mirroring the existing `geocodeAddress()` pattern in `lib/features/bookings/widgets/venue_picker.dart`: a separate Dio with no auth header, keyed by `AppConfig.googlePlacesApiKey`, returning null on any failure.

3. **Enrichment + scheduling** — computes `departure = firstItemTime − travelDuration`, schedules a precise local "leave in 15 min" notification at `departure − 15min`, and runs the already-left check.

**Two trigger paths**, both feeding the same enrichment logic:
- **Foreground (primary, reliable):** on app resume during an event day, enrich today's rostered events and schedule local notifications. Works whenever location is granted at any tier.
- **Data-push (best-effort):** the `event_departure` data push wakes the FCM handler, which runs the same enrichment when the OS grants execution time (reliable only with *always* permission; iOS background execution is time-limited).

The server's time-based push (Phase 1) is the guaranteed floor. Dedup stays keyed on `eventKey + type`, so an enriched local notification replaces the server one rather than stacking.

## Components & File Structure

All new code lives in the existing `lib/features/notifications/` slice. Pure logic is isolated and unit-tested; plugin/network glue is thin and platform-guarded (Phase 1 conventions).

### New files

- `lib/features/notifications/data/routes_client.dart` — `RoutesClient` wrapping Google Routes API. Method: `Future<Duration?> driveDuration({required LatLng origin, required String destinationAddress})`. Geocodes the destination (via the shared geocode helper), then POSTs to `computeRoutes` with traffic-aware driving and `departureTime=now`. Separate Dio, no auth header, null on any failure. Mirrors `geocodeAddress()`.

- `lib/features/notifications/data/leave_by.dart` — **pure** logic (most-tested file). All date math takes an injected `now`/clock; never calls `DateTime.now()` directly.
  - `DateTime departureTime({required DateTime firstItem, required Duration travel})` → `firstItem − travel`.
  - `DateTime remindAt(DateTime departure)` → `departure − 15min`.
  - `bool hasAlreadyLeft({required Duration travelToVenue, required Duration timeUntilFirstItem, required double metersToVenue, required bool pastDeparture})` → suppress when at/near the venue or comfortably en route (see Already-Left Decision).
  - `String buildLeaveByBody({required String? venue, required String firstItemTitle, required DateTime departure})` → enriched body with the "Leave by [time]" line, extending Phase 1's `buildReminderBody`.

- `lib/features/notifications/services/location_service.dart` — `LocationService` wrapping `geolocator`. Tiered permission: request while-in-use, then escalate to always. `Future<LocationGrant> ensurePermission()` returning enum `LocationGrant { always, whileInUse, denied }`; `Future<Position?> current()`. Platform-guarded (iOS/Android only; no-op elsewhere).

- `lib/features/notifications/services/enrichment_service.dart` — orchestrator used by both trigger paths. Given an event (key, venue, firstItemTime), reads location → Routes duration → computes departure/remindAt → already-left check → schedules or cancels the local notification via Phase 1's `PushService`.

### Modified files

- `lib/features/notifications/services/push_service.dart` — add `scheduleLocal({required int id, required String title, required String body, required DateTime when})` and `cancel(int id)` around `flutter_local_notifications`' zoned-schedule API (the reason core-library desugaring was needed in Phase 1).
- `lib/features/notifications/providers/notifications_provider.dart` — providers for `LocationService`, `RoutesClient`, `EnrichmentService`; an `enrichTodaysEvents()` entry point for the foreground path.
- `lib/main.dart` / app lifecycle — observe app resume; on an event day, call `enrichTodaysEvents()`. The background data-push path calls `EnrichmentService` from the FCM handler.
- iOS `Info.plist` + `Runner.entitlements`, Android manifest — location usage strings + background-location permission/justification (see Native Config).

### Shared refactor

Extract the existing `geocodeAddress()` from `lib/features/bookings/widgets/venue_picker.dart` into a shared helper (e.g. `lib/core/network/geocoding.dart`) so both venue-picking and `RoutesClient` reuse it. Update `venue_picker.dart` to import the shared version. No behavior change.

## Data Flow

**Foreground enrichment (primary path):**

```
App resumes → is today an event day with rostered events? (reuse bandEventsProvider)
  → for each such event with a venue + first timeline item:
      LocationService.ensurePermission()
        denied      → do nothing (server time-based push is the floor)
        granted     → LocationService.current()
                      → RoutesClient.driveDuration(current, venue)
                          null (geocode/route fails) → do nothing (floor remains)
                          duration → departure = firstItem − duration
                                     remindAt  = departure − 15min
                                     already-left? → cancel any local + skip
                                     remindAt in the past? → skip (too late)
                                     else → PushService.scheduleLocal(remindAt, enriched body)
```

**Background data-push (`event_departure`, best-effort):** the FCM handler runs the same `EnrichmentService` call for the single event in the payload. On iOS, if the OS withholds background execution time, nothing happens — the server's time-based push already fired as the floor. Nothing surfaces to the user.

## Already-Left Decision

`hasAlreadyLeft` (pure, tested) suppresses the departure reminder when either:

- `metersToVenue ≤ arrivalRadius` (≈ at the venue), **or**
- `travelToVenue ≤ timeUntilFirstItem` AND `pastDeparture` is true (they've left and are comfortably en route to arrive on time).

Both `arrivalRadius` and the comparison are named constants, tuned during implementation against real device readings.

## Error Handling

Consistent with Phase 1:

- Every external call (`geolocator`, Routes, geocode) returns null/empty on failure and degrades to the floor — never throws to the user.
- Enrichment is **idempotent**: re-running for the same event reschedules the same `eventKey + type` slot (dedup), so foreground + push paths cannot double-notify.
- "Too late" guard: if `remindAt` is already past at compute time, skip silently.
- Permission is re-checked on each run (the user may change it in Settings between runs).

## Permission Tiers (degradation)

| Grant | Behavior |
|---|---|
| always | Foreground enrichment + background push enrichment + already-left suppression |
| while-in-use | Foreground enrichment only; no background compute |
| denied | No enrichment; Phase 1 server time-based push only |

iOS requires the two-step prompt: request while-in-use first, then escalate to always (separate OS dialog). Many users grant only while-in-use or deny; the table above is the full fallback contract.

## Testing

**Unit tests (pure logic — bulk of coverage; `ProviderContainer` + fakes per Phase 1):**
- `leave_by.dart`: `departureTime`, `remindAt`, `hasAlreadyLeft` across the matrix (at-venue radius, en-route past departure, not-yet-left, exactly-on-threshold), `buildLeaveByBody` formatting with/without travel.
- `routes_client.dart`: parse a captured Routes API JSON sample into a `Duration` via a stubbed Dio adapter (like Phase 1's `device_repository_test.dart`); null on error/empty/malformed.
- Enrichment decision logic: inject `FakeLocationService`, `FakeRoutesClient`, and a fixed clock; assert schedule-vs-suppress-vs-skip outcomes.

**Time handling:** all date math takes an injected `now`/clock — never `DateTime.now()` in pure functions (avoids time-bomb tests). Tests pin the clock.

**Fakes:** `FakeLocationService` (canned grant + position), `FakeRoutesClient` (canned duration/null). No live GPS or network in tests.

**Not unit-tested (manual, on device):** `geolocator` permission prompts, real GPS reads, real Routes API calls, background data-push execution, zoned local-notification firing. Need real iOS + Android hardware.

**Verification gate:** `flutter test` + `flutter analyze` + `flutter build apk --debug`. iOS build + on-device behavior are your-machine steps.

## Prerequisites (manual, external — like Phase 1's Firebase setup)

- **Enable the Routes API** on the existing Google Cloud key (currently only Places/Geocoding are enabled). Without it, `driveDuration` returns null and the feature silently degrades to the floor.
- **Android Play Store background-location justification** — `ACCESS_BACKGROUND_LOCATION` requires a declared justification in the Play Console submission.
- **iOS App Review** — "always" location requires clear usage strings and may draw review scrutiny; copy must explain the leave-by reminder use.

## Open Items / Tuning (implementation-time)

- `arrivalRadius` (meters) and the en-route comparison thresholds for `hasAlreadyLeft`.
- The exact app-lifecycle hook for "on resume during an event day" (likely a `WidgetsBindingObserver` added at the app shell).
- Routes API request/response shape: confirm the `computeRoutes` field mask and the duration field (`routes[].duration`) against the live API when enabling it.
