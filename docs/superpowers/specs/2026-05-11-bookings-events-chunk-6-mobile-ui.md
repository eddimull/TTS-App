# Chunk 6 — Mobile UI

**Date:** 2026-05-11
**Parent spec:** [2026-05-03 bookings-events relationship design](2026-05-03-bookings-events-relationship-design.md) — Mobile App UX section (lines 264–309).
**Prior chunk:** [Chunk 5 mobile data layer](2026-05-11-bookings-events-chunk-5-mobile-data-layer.md) — shipped on the same branch (`feature/bookings-events-mobile`); 67 analyze errors remain across screens / widgets that this chunk fixes.

## Context

Chunk 5 updated Flutter models, repositories, and providers to consume the post-Chunk-1 mobile API. The data layer is clean (`flutter analyze` reports zero issues across `lib/features/bookings/data/`, `lib/features/events/data/`, `lib/shared/cache/`, and `lib/core/network/`); 14 new unit tests pass. The screens and widgets, however, still reference dropped legacy fields (`booking.date`, `booking.venueName`, `booking.parsedDate`, `event.time` as a top-level value, etc.) and a few tests construct `BookingSummary` with the old constructor — yielding 63 errors and a handful of warnings across `bookings_screen.dart`, `booking_detail_screen.dart`, `booking_form_screen.dart`, `event_edit_screen.dart`, `bookings_provider.dart`, `bookings_window_provider.dart`, `booking_month_strip.dart`, `booking_search.dart`, and four test files.

This chunk fixes those, rewrites booking detail + booking form for the multi-event conceptual model, surfaces the multi-event chip on list cards and the engagement summary on the detail header, adds a "Part of:" backlink to event detail when the event belongs to a booking, softens the contract screen's "no contract" wording, and lands the partial-failure save flow that the parent spec describes in detail. Comprehensive widget + logic tests cover every visible behavior.

## Goal

Restore the mobile app to a compile-able, runnable state on the new backend shape, and implement the full Mobile App UX described in the parent spec — including the polished iOS partial-failure save flow on the booking form.

## Non-Goals

- Backend changes — Chunks 1–3 merged.
- Contract-state lock on `signed`/`sent` bookings (parent-spec future-risk item; deferred).
- Calendar grouping of events belonging to one booking (deferred per parent spec).
- Pusher real-time push for booking-event changes.
- Auth, setlist, media, more, rehearsals features.

## Scope

### 1. New extracted widgets and services

The booking form's complexity (already ~1,449 lines pre-Chunk-6) plus the partial-failure save flow plus the multi-event sub-form list would push the screen file well past 2,000 lines. Extract the focused pieces:

#### `lib/features/bookings/widgets/event_sub_form_card.dart`

A single event row in the booking form. Cupertino-styled. Props (Dart record-like):

- `EventDraft` row state (or `EventSummary` + `id` for existing events) — uses a local `EventFormRow` wrapper to unify the two cases inside the form's state.
- `bool canDelete` — when `false`, the delete trash button is rendered disabled.
- `String? saveError` — when non-null, renders an `exclamationmark.circle` indicator and the literal copy `"Save failed — tap to retry"` immediately under the row title.
- Callbacks: `onChange(updatedRow)`, `onDelete()`, `onRetryRow()` (fires when the user taps the inline error indicator).

Approx. 200–300 lines including the date/time pickers and venue autocomplete trigger.

#### `lib/features/bookings/services/booking_save_orchestrator.dart`

Pure Dart, no Flutter dependency. Owns the sequential save state machine that the parent spec describes. Two value types and one class:

```dart
sealed class OperationStatus {
  const OperationStatus();
}
class OperationPending extends OperationStatus { const OperationPending(); }
class OperationSuccess extends OperationStatus { const OperationSuccess(); }
class OperationFailure extends OperationStatus {
  const OperationFailure(this.message);
  final String message;
}

class BookingFormSnapshot {
  // What the form looked like at save time. Holds:
  // - booking-level field diffs (only the keys the user changed)
  // - eventUpdates: Map<int eventId, EventDraft> (existing events the user edited)
  // - eventCreates: Map<String localKey, EventDraft> (new rows added)
  // - eventDeletes: Set<int eventId> (rows the user removed)
}

class BookingSaveResult {
  final OperationStatus bookingPatch;
  final Map<int, OperationStatus> eventUpdates;
  final Map<String, OperationStatus> eventCreates;
  final Map<int, OperationStatus> eventDeletes;

  bool get allSucceeded;
  bool get allFailed;
  bool get partiallySucceeded;
  int get failedCount;
  Iterable<MapEntry<String, OperationFailure>> get failureKeys;
  // Returns "BOOKING" for the booking patch failure, "EVT-{id}" for
  // existing-event ops, "NEW-{localKey}" for create ops. Used by the
  // UI to highlight rows.
}

class BookingSaveOrchestrator {
  BookingSaveOrchestrator({
    required this.bookingsRepository,
    required this.eventsRepository,
  });

  /// Runs the booking PATCH first; if it fails, the event sub-ops are
  /// skipped. Otherwise runs each event sub-op sequentially. Each sub-op's
  /// failure is captured in the result; subsequent sub-ops still run
  /// (so a 422 on a DELETE doesn't block an unrelated PUT).
  Future<BookingSaveResult> save({
    required int bandId,
    required int bookingId,
    required BookingFormSnapshot snapshot,
  });
}
```

Retry semantics: on a second `save` call with the same `BookingFormSnapshot`, the orchestrator runs every sub-op again. The caller (booking form screen) builds the snapshot from current dirty state; successful ops won't be in the snapshot (no diff) and won't re-fire.

Approx. 200 lines.

#### `lib/features/bookings/widgets/booking_form_partial_failure_banner.dart`

Cupertino banner shown only on the "all sub-ops failed" path. Single-purpose, ~50 lines. Copy: "No changes saved — check your connection." With a tap-to-dismiss affordance.

#### `lib/features/bookings/widgets/booking_form_navigation_guard.dart`

Exposes:

```dart
class BookingFormNavigationGuard {
  /// Returns true if the user is allowed to leave (no pending failures
  /// OR they explicitly tapped Discard). Returns false if the user
  /// elected to stay and retry (the form should remain mounted).
  ///
  /// When [result] is null or has no failures, returns true synchronously.
  static Future<bool> shouldAllowLeave(
    BuildContext context,
    BookingSaveResult? result,
  ) async { ... }
}
```

Shows a `CupertinoAlertDialog` titled "Unsaved changes" with body `"$saved changes saved, $failed still failed. Leave anyway?"` and two actions: `"Discard"` (destructive, returns `true`) and `"Stay & Retry"` (default, returns `false`). The form screen wires this into a `PopScope` (the modern replacement for the deprecated `WillPopScope`).

Approx. 80 lines.

### 2. Screen rewrites

#### `lib/features/bookings/screens/booking_form_screen.dart` (major rewrite)

Replaces today's single-date/time/venue input block with:

- **Engagement section** — name (existing field), status, total price, event type, contract option, notes. No date/start_time/end_time/venue_name/venue_address inputs at the booking level — those are now per-event.
- **Events section** — a `ListView`/`Column` of `EventSubFormCard` rows. Each row is keyed by either the event's stable `id` (existing) or a local `_localKey` counter (new). Adding a row appends an `EventFormRow(_localKey: nextKey, draft: EventDraft(date: lastRow.date, title: '${booking.name} Event'))`. Removing a row deletes from local state (or marks for deletion if the row corresponds to an existing event id; the orchestrator's `BookingFormSnapshot.eventDeletes` then captures the id).
- **Save flow** — on save tap, build a `BookingFormSnapshot` from current form state vs the original loaded values, fire `BookingSaveOrchestrator.save`. Handle the result:
  - **`allSucceeded`** → close the screen, return the updated `BookingDetail` via `Navigator.pop`.
  - **`allFailed`** → render the partial-failure banner inline at the top of the form. Save button stays as **"Save Booking"** (since nothing succeeded, there's nothing to "retry" vs reattempt).
  - **`partiallySucceeded`** → keep the failed rows marked with `saveError` (using the orchestrator's `failureKeys` mapping); transform the Save button copy to **"Retry Failed (N)"** with destructive tint via `CupertinoButton`'s standard destructive styling; successful changes persist (the local snapshot is rebuilt so a second save retries only the still-pending diffs).
- **Navigation guard** — `PopScope(canPop: false, onPopInvoked: (didPop) async { if (didPop) return; final allow = await BookingFormNavigationGuard.shouldAllowLeave(context, _latestResult); if (allow) Navigator.pop(...); })`. The guard returns `true` immediately when `_latestResult` is null or has no failures.

#### `lib/features/bookings/screens/booking_detail_screen.dart` (major rewrite)

Top-to-bottom structure per the parent spec:

1. **Header + engagement summary strip** — band identity chip at top; below the booking name, a subtitle of the form `"$eventCount events · $displayDateRange · $venueSummary"`, with `"1 event · ..."` retained for single-event bookings (the spec explicitly calls for this to teach the model). A small `[N events]` Cupertino chip appears next to the title only when `isMultiEvent` is true.
2. **Status & financials** — keep the existing rendering; swap legacy field reads (`amountPaid` → `displayAmountPaid`, etc.; field names unchanged, only `date`/`venueName` reads broken).
3. **Events section** — vertical stack of tappable cards, each rendered as a Cupertino-styled `GestureDetector` showing event title, formatted date + time range, venue, roster status chip, optional per-event price. Tap → existing event detail screen (`/events/${event.key}/edit` → `/events/${event.key}` for view).  "+ Add event" Cupertino button at the bottom of the stack.
4. **Itemization summary** — visible only when `isMultiEvent` AND `events.any((e) => e.price != null && double.tryParse(e.price!) != 0)`. Renders the breakdown: "Total: $X" then per-event "Sat 6/13 — $Y" entries, then "Other / Unallocated: $Z" if there's a non-zero delta.
5. **Payments, Contacts, Contract, Notes, History** — existing sections preserved; field-name fixes only.

#### `lib/features/bookings/screens/booking_contract_screen.dart`

When `booking.contractOption == 'none'`, replace the current copy with: "Verbal agreement — no contract on file." Add a secondary `CupertinoButton.filled(child: Text('Change to a contract type'))` that triggers the existing contract-option editor / picker. For `default` / `external` options, keep today's rendering.

#### `lib/features/events/screens/event_detail_screen.dart`

Add a "Part of: $bookingName" row near the top of the event metadata block, rendered only when `event.eventableType == 'Bookings'` and the booking name is resolvable (via a lightweight repo lookup or by passing the parent booking name as a route extra when navigating from booking detail). Tappable — navigates to `/bands/$bandId/bookings/$bookingId`.

If looking up the booking name would require an extra API call here, accept the trade-off: pass the booking name as a `Navigator.push` extra from booking detail (the natural source), and render the row only when that extra is present. Event detail opened from other entry points (dashboard, search) won't show the row; that's fine — the row's primary value is reinforcing the relationship for users navigating from the booking, not advertising it everywhere.

#### `lib/features/events/screens/event_edit_screen.dart`

Currently uses a single `time` field; the new event model has `startTime` and `endTime`. Replace the single time picker with two side-by-side time pickers ("Start time" and "End time"). Reads from `EventDetail.startTime` / `.endTime` (which Chunk 5 already populates with the `time` fallback for older payloads). Save payload through `EventsRepository.updateEvent(key, startTime: ..., endTime: ...)`.

If venue editing is also present here, leave it as-is — venue fields didn't change shape.

#### `lib/features/bookings/screens/bookings_screen.dart`

List card rendering: replace any `booking.date` reads with `displayDateRange`; replace `booking.venueName` with `venueSummary`; render the `[N events]` Cupertino chip next to the booking title when `isMultiEvent` is true. Subtitle format matches the spec:

- Single-event: `"$displayDateRange · $startTime · $venueSummary"` (with `startTime` derived from `events.first.startTime` if available).
- Multi-event: `"$eventCount events · $displayDateRange · $venueSummary"`.

Month strip + filter wiring keys off `startDate`.

### 3. Provider and utility fixes

- **`booking_search.dart`** — predicate matches if any of: booking name, `events[].title`, `events[].venueName`, or the date range `[startDate, endDate]` overlaps the search range. Mirrors the web's any-event-in-range semantics.
- **`booking_month_strip.dart`** — month bucketing keys off `startDate`. Tolerates `endDate > startDate` by emitting the booking under its `startDate` month only (single bucket per booking, matching today's behavior for single-event bookings).
- **`bookings_window_provider.dart`** — the window is keyed by `startDate`; semantic unchanged, just fix the dirty field reads.
- **`bookings_provider.dart`** — fix dirty field reads.

### 4. Test plan

Per the user's choice of "comprehensive widget coverage" (option 3 from brainstorming).

#### Pure-Dart unit tests

**`test/features/bookings/services/booking_save_orchestrator_test.dart`** — exhaustive permutations:

- **Empty snapshot** → save succeeds, zero API calls made.
- **Booking PATCH only succeeds, no event ops** → `allSucceeded` true.
- **Booking PATCH fails** → orchestrator halts, no event ops fire; `allFailed` true.
- **All event PUTs succeed** → `allSucceeded` true.
- **All event POSTs succeed** → `allSucceeded` true.
- **All event DELETEs succeed** → `allSucceeded` true.
- **Mixed success/failure** → one PUT fails, one POST succeeds, one DELETE succeeds → `partiallySucceeded` true; per-op failures captured.
- **DELETE last-event 422** → server returns the cannot-delete-last-event error; orchestrator captures the message in `OperationFailure.message`.
- **Network-out (every call throws DioException)** → all-fail result distinguishes from partial.
- **Retry semantics** — after a partial-failure, caller builds a new snapshot with only the still-dirty diffs; orchestrator's second invocation re-runs only those.

Uses the same `_StubAdapter` pattern Chunk 5 used; constructs concrete `BookingsRepository` and `EventsRepository` against the mock.

#### Widget tests

**`test/features/bookings/widgets/event_sub_form_card_test.dart`** — renders inline error indicator and "Save failed — tap to retry" when `saveError` non-null; trash button is disabled when `canDelete: false`; `onChange` fires when the user edits a field; `onRetryRow` fires when the user taps the inline error.

**`test/features/bookings/screens/booking_detail_engagement_summary_test.dart`** — pumps `BookingDetailScreen` with a single-event fixture; expects subtitle text `"1 event · …"`, no `[N events]` chip; pumps with a multi-event fixture; expects `"3 events · …"` subtitle and chip with `Find.text('3 events')`.

**`test/features/bookings/screens/bookings_list_card_test.dart`** — pumps `BookingsScreen` with a list containing one single-event and one multi-event booking; verifies subtitle formats and chip presence/absence.

**`test/features/bookings/widgets/booking_form_partial_failure_banner_test.dart`** — pumps the banner; verifies copy "No changes saved — check your connection."; tap dismisses.

**`test/features/bookings/widgets/booking_form_navigation_guard_test.dart`** — guard returns `true` immediately when `BookingSaveResult` is `null` or has no failures; pumps a host widget that triggers `shouldAllowLeave` with a partial-failure result; asserts `CupertinoAlertDialog` appears with the correct copy; tapping "Discard" resolves the future to `true`, tapping "Stay & Retry" resolves to `false`.

**`test/features/bookings/screens/booking_form_save_button_test.dart`** — pristine state shows "Save Booking"; after pumping a state that includes a `BookingSaveResult` with two failures, the button reads "Retry Failed (2)" and renders with destructive styling.

**`test/features/events/screens/event_detail_part_of_row_test.dart`** — "Part of: $bookingName" row renders when the event's `eventableType` is `Bookings` and the booking name is provided; absent when the event isn't booking-attached.

**`test/features/bookings/screens/booking_contract_screen_test.dart`** — `contract_option == 'none'` renders "Verbal agreement — no contract on file" and the "Change to a contract type" action; `default`/`external` don't show the new copy.

#### Pre-existing test fixups

- **`booking_search_test.dart`** — fixture rewrites for new `BookingSummary` constructor; new any-event-in-range assertions.
- **`booking_month_strip_test.dart`** — fixtures use `startDate`.
- **`bookings_window_provider_test.dart`** — fixtures use new `BookingSummary` constructor.
- **`events_provider_test.dart`** — `FakeEventsRepository.updateEvent` override matches the new named-parameter signature.

#### Coverage targets

- **`flutter analyze`** — must report **zero** issues across the entire project after this chunk.
- **`flutter test`** — full suite must pass. New tests add roughly 30 cases on top of the pre-existing baseline.

### 5. Branch & commit strategy

Continue on `feature/bookings-events-mobile`. Commit prefix:
- `feat(mobile/ui):` — screen / widget work
- `feat(mobile):` — cross-cutting (e.g., service extraction)
- `test(mobile):` — test files
- `refactor(mobile/ui):` — pre-existing utility fixes (booking_search etc.)

Suggested commit shape (roughly 12–14 commits):

1. Extract `BookingSaveOrchestrator` service + tests.
2. Extract `EventSubFormCard` widget + test.
3. Extract partial-failure banner widget + test.
4. Extract navigation guard widget + test.
5. Rewrite `booking_form_screen.dart` wiring everything together.
6. Rewrite `booking_detail_screen.dart` (engagement strip + events stack + itemization).
7. Update `bookings_screen.dart` (subtitle + chip).
8. Update `booking_contract_screen.dart` (verbal agreement wording).
9. Update `event_detail_screen.dart` ("Part of:" row).
10. Update `event_edit_screen.dart` (split start/end time).
11. Fix utility tests (booking_search, booking_month_strip, bookings_window_provider).
12. Fix `events_provider_test.dart` fake override.
13. Add booking detail engagement summary widget test.
14. Add bookings list card widget test.

### 6. Final PR

Bundled `feat(mobile): bookings/events catch-up — data layer + UI rewrite` against `main`. PR body summarizes both Chunk 5 and Chunk 6; manual smoke list (run-on-device checklist):

- Cold-launch the app against the dev backend; bookings list loads. Single-event and multi-event bookings render with correct subtitle and chip.
- Tap a single-event booking → detail screen shows the new layout (engagement strip, events section, financials, etc.); no broken bindings.
- Tap a multi-event booking → multi-event rendering throughout. Itemization summary visible if any event has a price set.
- Open the booking form on a multi-event booking → events render as a sub-form list; delete disabled on the last remaining event.
- Edit a multi-event booking: rename, change one event's date, add a new event, delete a third → save → all four operations succeed and the detail screen reflects the new state.
- Force a partial-failure (e.g., toggle airplane mode mid-save) → per-row error indicators appear, Save button transforms to "Retry Failed (N)"; tap to retry succeeds.
- Try to back out of the form with failures pending → navigation guard `CupertinoAlertDialog` appears with the spec's copy. "Stay & Retry" keeps the form mounted; "Discard" leaves.
- Open an event detail screen from a multi-event booking → "Part of: $bookingName" row at the top; tap returns to booking detail.
- Open a booking with `contract_option == 'none'` → contract screen reads "Verbal agreement — no contract on file" with the "Change to a contract type" action.

## Risks

- **Booking form save flow is the riskiest piece** — five distinct partial-failure behaviors, navigation guard interaction with `PopScope`, button copy/styling state machine. Mitigated by:
  - Extracting the orchestrator into a pure-Dart service with exhaustive unit tests (10 cases).
  - Widget-testing each visual state (banner, save button copy, nav guard alert) independently.
  - Manual smoke against the dev backend with intentional partial failures (airplane-mode toggle).
- **`PopScope` vs `WillPopScope`** — Flutter has been migrating away from `WillPopScope`. Use `PopScope` per the modern API; if any pre-existing screens use `WillPopScope`, leave them as-is (no unrelated refactor in this chunk).
- **Event-detail "Part of:" backlink needs the booking name** — passing it via route extras keeps the surface simple. Skip the row entirely on entry points that don't have it (dashboard, search). Documented in spec.
- **`EventFormRow` is a local UI wrapper, not a model** — confusion with `EventDraft` / `EventSummary` is the most likely refactor-time mistake. Mitigated by keeping the wrapper private to `booking_form_screen.dart` and the orchestrator's `BookingFormSnapshot` accepts the model types directly, not the wrapper.

## Out of scope

- Contract-state lock on signed/sent bookings (parent-spec deferred).
- Calendar grouping (parent-spec deferred).
- Pusher real-time push for booking-event changes.
- Auth, setlist, media, more, rehearsals.
- Backend changes — Chunks 1–3 already merged.
