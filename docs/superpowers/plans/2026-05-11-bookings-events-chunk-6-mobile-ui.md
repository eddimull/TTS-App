# Chunk 6 — Mobile UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the mobile UI to full compliance with the parent spec's Mobile App UX section — multi-event rendering on detail and list, multi-event editing in the booking form with iOS-styled partial-failure save flow, "Part of:" backlink on event detail, softer "verbal agreement" contract copy, and all utility / provider / test fixes triggered by Chunk 5's model rewrites.

**Architecture:** The booking form's partial-failure flow is the hardest piece — extract it into a pure-Dart `BookingSaveOrchestrator` service that's exhaustively unit-testable. Extract per-event sub-form, partial-failure banner, and navigation-guard widgets to keep the form screen under ~1000 lines. All other screens get field-name fixes + the spec's targeted UX updates. Tests cover every visible state of the partial-failure flow.

**Tech Stack:** Flutter (Cupertino widgets), Riverpod, Luxon-style date math via `intl`, Dio.

**Spec:** `docs/superpowers/specs/2026-05-11-bookings-events-chunk-6-mobile-ui.md`
**Working repo:** `/home/eddie/github/tts_bandmate`
**Branch:** `feature/bookings-events-mobile` (Chunk 5 already on this branch; this chunk continues on it).

---

## File map

**Create:**
- `lib/features/bookings/services/booking_save_orchestrator.dart` — pure-Dart save state machine.
- `lib/features/bookings/widgets/event_sub_form_card.dart` — Cupertino-styled per-event row in the booking form.
- `lib/features/bookings/widgets/booking_form_partial_failure_banner.dart` — banner shown only on all-fail save.
- `lib/features/bookings/widgets/booking_form_navigation_guard.dart` — wraps the `CupertinoAlertDialog` for the leave-with-failures prompt.
- 12 test files (one per new file + widget tests for screens — listed in Task descriptions).

**Modify (rewrite or repair):**
- `lib/features/bookings/screens/booking_form_screen.dart` — major rewrite using the extracted pieces.
- `lib/features/bookings/screens/booking_detail_screen.dart` — major rewrite (engagement strip, events stack, itemization, field-name fixes).
- `lib/features/bookings/screens/bookings_screen.dart` — subtitle + chip + field-name fixes.
- `lib/features/bookings/screens/booking_contract_screen.dart` — softened "verbal agreement" wording.
- `lib/features/events/screens/event_detail_screen.dart` — add "Part of: $bookingName" row.
- `lib/features/events/screens/event_edit_screen.dart` — split single `time` into start/end time inputs.
- `lib/features/bookings/providers/bookings_provider.dart` — field-name fixes.
- `lib/features/bookings/providers/bookings_window_provider.dart` — field-name fixes.
- `lib/features/bookings/utils/booking_search.dart` — any-event-in-range semantics.
- `lib/features/bookings/utils/booking_month_strip.dart` — keys off `startDate`.

**Test fixups (pre-existing tests broken by Chunk 5):**
- `test/features/bookings/providers/bookings_window_provider_test.dart`
- `test/features/bookings/utils/booking_search_test.dart`
- `test/features/bookings/utils/booking_month_strip_test.dart`
- `test/providers/events_provider_test.dart`

**Untouched (Chunk 5 already covered):**
- Models, repositories, `cache_invalidator.dart`, `api_endpoints.dart`.

---

## Branch setup (already done in Chunk 5)

### Task 0: Confirm we're on the right branch

- [ ] **Step 1: Verify branch**

```bash
cd /home/eddie/github/tts_bandmate
git status -sb
```

Expected: `## feature/bookings-events-mobile`. If not, switch:

```bash
cd /home/eddie/github/tts_bandmate && git checkout feature/bookings-events-mobile
```

- [ ] **Step 2: Verify Chunk 5 commits are present**

```bash
cd /home/eddie/github/tts_bandmate && git log --oneline -12 | grep "mobile/data"
```

Expected: at least 10 `feat(mobile/data):` / `test(mobile/data):` commits.

- [ ] **Step 3: Re-confirm the dirty state we expect**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze 2>&1 | tail -5
```

Expected: about 67 issues. Most are in screens/widgets that this chunk fixes.

---

## Task 1: Quick utility + provider field-name fixes

These are the small files where a one-line swap restores green. Doing them first removes a chunk of analyze noise and lets later tasks focus on substantive work.

**Files:**
- Modify: `lib/features/bookings/utils/booking_search.dart`
- Modify: `lib/features/bookings/utils/booking_month_strip.dart`
- Modify: `lib/features/bookings/providers/bookings_provider.dart`
- Modify: `lib/features/bookings/providers/bookings_window_provider.dart`

- [ ] **Step 1: Update `booking_search.dart` to use new field names and any-event semantics**

Replace the function body:

```dart
import '../data/models/booking_summary.dart';

/// Returns true if [booking] matches [query] (case-insensitive contains)
/// against any of: name, venue summary, any event's title or venue name,
/// or any contact's name/email/phone.
///
/// Empty or whitespace-only queries match everything.
bool bookingMatchesQuery(BookingSummary booking, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;

  if (booking.name.toLowerCase().contains(q)) return true;
  final venue = booking.venueSummary;
  if (venue != null && venue.toLowerCase().contains(q)) return true;

  for (final e in booking.events) {
    if (e.title.toLowerCase().contains(q)) return true;
    final v = e.venueName;
    if (v != null && v.toLowerCase().contains(q)) return true;
  }

  for (final c in booking.contacts) {
    if (c.name.toLowerCase().contains(q)) return true;
    final email = c.email;
    if (email != null && email.toLowerCase().contains(q)) return true;
    final phone = c.phone;
    if (phone != null && phone.toLowerCase().contains(q)) return true;
  }
  return false;
}
```

- [ ] **Step 2: Update `booking_month_strip.dart` to use `parsedStartDate`**

Two sites in this file use `b.parsedDate`. Replace both with `b.parsedStartDate`:

```bash
cd /home/eddie/github/tts_bandmate && sed -i 's/parsedDate/parsedStartDate/g' lib/features/bookings/utils/booking_month_strip.dart
```

Then update the doc comments in that file — `parsedDate` is mentioned in 2 docstrings; manually re-edit those to read `parsedStartDate`.

- [ ] **Step 3: Update `bookings_provider.dart`**

```bash
cd /home/eddie/github/tts_bandmate && grep -n "booking.date\|.parsedDate" lib/features/bookings/providers/bookings_provider.dart
```

Replace each `booking.date` with `booking.startDate` (raw ISO string) and any `.parsedDate` with `.parsedStartDate`. The semantics are equivalent: the legacy `date` field for a single-event booking was always the event's date, which is now `startDate`.

- [ ] **Step 4: Update `bookings_window_provider.dart`**

```bash
cd /home/eddie/github/tts_bandmate && sed -i 's/\.parsedDate/.parsedStartDate/g' lib/features/bookings/providers/bookings_window_provider.dart
```

- [ ] **Step 5: Analyze the four files**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/bookings/utils/ lib/features/bookings/providers/ 2>&1 | tail -5
```

Expected: no issues across these directories.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/utils/ lib/features/bookings/providers/
git commit -m "refactor(mobile/ui): utility + provider field-name fixes after Chunk 5

bookings_provider, bookings_window_provider, booking_month_strip:
swap legacy .date / .parsedDate reads for the new startDate /
parsedStartDate accessors. booking_search gains any-event-in-range
matching against event titles and venue names."
```

---

## Task 2: Fix pre-existing tests broken by Chunk 5

**Files:**
- Modify: `test/features/bookings/providers/bookings_window_provider_test.dart`
- Modify: `test/features/bookings/utils/booking_search_test.dart`
- Modify: `test/features/bookings/utils/booking_month_strip_test.dart`
- Modify: `test/providers/events_provider_test.dart`

- [ ] **Step 1: Inspect existing failures**

```bash
cd /home/eddie/github/tts_bandmate && grep -nE "BookingSummary\(" test/features/bookings/providers/bookings_window_provider_test.dart test/features/bookings/utils/booking_search_test.dart test/features/bookings/utils/booking_month_strip_test.dart | head -10
```

Each file has a small helper that constructs a `BookingSummary` with the old `date: ...`, `venueName: ...` parameters. The Chunk 5 model now requires `startDate`, `endDate`, `eventCount`, `isMultiEvent` as named parameters.

- [ ] **Step 2: Define a shared `BookingSummary` test fixture helper**

In each test file's `// ── Helpers ──` section (or top of file), add:

```dart
BookingSummary _booking({
  required int id,
  required String name,
  required String startDate,
  String? endDate,
  int eventCount = 1,
  bool? isMultiEvent,
  String? venueName,
  List<BookingContact> contacts = const [],
}) {
  final end = endDate ?? startDate;
  return BookingSummary(
    id: id,
    name: name,
    startDate: startDate,
    endDate: end,
    eventCount: eventCount,
    isMultiEvent: isMultiEvent ?? (eventCount > 1),
    venueSummary: venueName,
    isPaid: false,
    contacts: contacts,
  );
}
```

Replace each `BookingSummary(date: ..., venueName: ...)` callsite in the test with `_booking(startDate: ..., venueName: ...)`. The helper translates legacy single-event test intent to the new model.

If the file's existing test assertions read `b.date` directly, update them to `b.startDate`. If they assert against `b.venueName`, update to `b.venueSummary`.

- [ ] **Step 3: Run each test file**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/utils/booking_search_test.dart test/features/bookings/utils/booking_month_strip_test.dart test/features/bookings/providers/bookings_window_provider_test.dart 2>&1 | tail -10
```

Expected: all pass.

- [ ] **Step 4: Fix `events_provider_test.dart` fake override**

```bash
cd /home/eddie/github/tts_bandmate && grep -nA 4 "class FakeEventsRepository" test/providers/events_provider_test.dart | head -10
```

The `FakeEventsRepository.updateEvent` declares `Future<void> updateEvent(String key, Map<String, dynamic> data)`. Replace with the new signature:

```dart
@override
Future<void> updateEvent(
  String key, {
  String? title,
  String? date,
  String? startTime,
  String? endTime,
  String? venueName,
  String? venueAddress,
  String? price,
  String? notes,
}) async {
  lastKey = key;
  lastPayload = {
    if (title != null) 'title': title,
    if (date != null) 'date': date,
    if (startTime != null) 'start_time': startTime,
    if (endTime != null) 'end_time': endTime,
    if (venueName != null) 'venue_name': venueName,
    if (venueAddress != null) 'venue_address': venueAddress,
    if (price != null) 'price': price,
    if (notes != null) 'notes': notes,
  };
}
```

Add `String? lastKey;` and `Map<String, dynamic>? lastPayload;` as fields on the fake if not already present. Update any test that called `fake.updateEvent(key, {'time': '19:00'})` to the new positional-key + named-params form.

Also fix the unused-variable warning at line 177 (`asyncValue`) by either using it in an assertion or replacing the binding with `final _ = ...;`.

- [ ] **Step 5: Run the events provider test**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/providers/events_provider_test.dart 2>&1 | tail -10
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add test/features/bookings/ test/providers/events_provider_test.dart
git commit -m "test(mobile): fix existing fixtures broken by Chunk 5 model changes

booking_search, booking_month_strip, bookings_window_provider: helper
constructs BookingSummary with new named params; assertions read
startDate / venueSummary instead of date / venueName.

events_provider_test: FakeEventsRepository.updateEvent override
matches the new named-parameter signature; unused asyncValue elided."
```

---

## Task 3: Define `BookingSaveOrchestrator` value types

**Files:**
- Create: `lib/features/bookings/services/booking_save_orchestrator.dart` (types only — class body comes in Task 5)

- [ ] **Step 1: Create the directory and file with value types**

```bash
cd /home/eddie/github/tts_bandmate && mkdir -p lib/features/bookings/services
```

Create `lib/features/bookings/services/booking_save_orchestrator.dart`:

```dart
import '../data/models/event_draft.dart';

/// Sealed status of one sub-operation in a booking save.
sealed class OperationStatus {
  const OperationStatus();
}

class OperationPending extends OperationStatus {
  const OperationPending();
}

class OperationSuccess extends OperationStatus {
  const OperationSuccess();
}

class OperationFailure extends OperationStatus {
  const OperationFailure(this.message);
  final String message;
}

/// Snapshot of the booking form's intended save at the moment the user
/// hits Save. The orchestrator runs the diff against the server: booking
/// PATCH first, then each event sub-op sequentially.
///
/// Callers build this from form state vs the original loaded values.
class BookingFormSnapshot {
  const BookingFormSnapshot({
    this.bookingPatch,
    this.eventUpdates = const {},
    this.eventCreates = const {},
    this.eventDeletes = const {},
  });

  /// Booking-level fields the user changed. Null when no booking-level
  /// fields were dirty (orchestrator skips the PATCH entirely).
  final BookingFieldDiff? bookingPatch;

  /// Keyed by existing event id. Each value is the new state the user
  /// wants written. Existing events that the user didn't touch are
  /// absent from this map.
  final Map<int, EventDraft> eventUpdates;

  /// Keyed by a local row-key string (e.g. "new-1", "new-2") so the UI
  /// can map per-op failures back to the corresponding form row.
  final Map<String, EventDraft> eventCreates;

  /// Set of existing event ids the user removed from the form.
  final Set<int> eventDeletes;

  bool get isEmpty =>
      bookingPatch == null &&
      eventUpdates.isEmpty &&
      eventCreates.isEmpty &&
      eventDeletes.isEmpty;
}

/// Booking-level fields. All null means no diff; the orchestrator treats
/// an all-null diff as "skip the PATCH."
class BookingFieldDiff {
  const BookingFieldDiff({
    this.name,
    this.eventTypeId,
    this.price,
    this.status,
    this.contractOption,
    this.notes,
  });

  final String? name;
  final int? eventTypeId;
  final String? price;
  final String? status;
  final String? contractOption;
  final String? notes;

  bool get isEmpty =>
      name == null &&
      eventTypeId == null &&
      price == null &&
      status == null &&
      contractOption == null &&
      notes == null;
}

/// Result of running a snapshot through the orchestrator. Each sub-op's
/// outcome is captured; the UI layer reads [failureKeys] to highlight
/// failed rows and reads [partiallySucceeded] / [allFailed] to choose
/// between the inline-error UX and the full-failure banner.
class BookingSaveResult {
  BookingSaveResult({
    required this.bookingPatch,
    required this.eventUpdates,
    required this.eventCreates,
    required this.eventDeletes,
  });

  final OperationStatus bookingPatch;
  final Map<int, OperationStatus> eventUpdates;
  final Map<String, OperationStatus> eventCreates;
  final Map<int, OperationStatus> eventDeletes;

  Iterable<OperationStatus> get _all sync* {
    yield bookingPatch;
    yield* eventUpdates.values;
    yield* eventCreates.values;
    yield* eventDeletes.values;
  }

  bool get allSucceeded =>
      _all.every((s) => s is OperationSuccess);

  bool get allFailed {
    final ran = _all.where((s) => s is! OperationPending).toList();
    if (ran.isEmpty) return false;
    return ran.every((s) => s is OperationFailure);
  }

  bool get partiallySucceeded {
    final hasSuccess = _all.any((s) => s is OperationSuccess);
    final hasFailure = _all.any((s) => s is OperationFailure);
    return hasSuccess && hasFailure;
  }

  int get failedCount => _all.whereType<OperationFailure>().length;

  /// Row keys that failed. "BOOKING" for the booking-level patch,
  /// "EVT-{id}" for an existing-event op (update or delete), or
  /// "NEW-{localKey}" for a create op.
  Iterable<MapEntry<String, OperationFailure>> get failureKeys sync* {
    if (bookingPatch is OperationFailure) {
      yield MapEntry('BOOKING', bookingPatch as OperationFailure);
    }
    for (final e in eventUpdates.entries) {
      if (e.value is OperationFailure) {
        yield MapEntry('EVT-${e.key}', e.value as OperationFailure);
      }
    }
    for (final e in eventCreates.entries) {
      if (e.value is OperationFailure) {
        yield MapEntry('NEW-${e.key}', e.value as OperationFailure);
      }
    }
    for (final e in eventDeletes.entries) {
      if (e.value is OperationFailure) {
        yield MapEntry('EVT-${e.key}', e.value as OperationFailure);
      }
    }
  }
}
```

- [ ] **Step 2: Analyze the file**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/bookings/services/booking_save_orchestrator.dart
```

Expected: clean.

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/services/booking_save_orchestrator.dart
git commit -m "feat(mobile): introduce BookingFormSnapshot + BookingSaveResult types

Pure-Dart value types for the partial-failure save state machine.
OperationStatus is a sealed class with Pending / Success / Failure;
BookingSaveResult exposes allSucceeded / partiallySucceeded / allFailed
predicates plus a failureKeys iterator the UI uses to highlight rows."
```

---

## Task 4: Test the value types

**Files:**
- Create: `test/features/bookings/services/booking_save_result_test.dart`

- [ ] **Step 1: Create the directory**

```bash
cd /home/eddie/github/tts_bandmate && mkdir -p test/features/bookings/services
```

- [ ] **Step 2: Write tests for the result predicates**

Create `test/features/bookings/services/booking_save_result_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/services/booking_save_orchestrator.dart';

void main() {
  group('BookingSaveResult predicates', () {
    test('allSucceeded — every op success', () {
      final r = BookingSaveResult(
        bookingPatch: const OperationSuccess(),
        eventUpdates: {1: const OperationSuccess()},
        eventCreates: const {},
        eventDeletes: const {},
      );
      expect(r.allSucceeded, isTrue);
      expect(r.partiallySucceeded, isFalse);
      expect(r.allFailed, isFalse);
      expect(r.failedCount, 0);
    });

    test('allFailed — every ran op failed', () {
      final r = BookingSaveResult(
        bookingPatch: const OperationFailure('boom'),
        eventUpdates: {1: const OperationFailure('boom')},
        eventCreates: const {},
        eventDeletes: const {},
      );
      expect(r.allSucceeded, isFalse);
      expect(r.partiallySucceeded, isFalse);
      expect(r.allFailed, isTrue);
      expect(r.failedCount, 2);
    });

    test('partiallySucceeded — mixed success and failure', () {
      final r = BookingSaveResult(
        bookingPatch: const OperationSuccess(),
        eventUpdates: {
          1: const OperationSuccess(),
          2: const OperationFailure('nope'),
        },
        eventCreates: {
          'new-1': const OperationSuccess(),
        },
        eventDeletes: {
          7: const OperationFailure('cannot delete last event'),
        },
      );
      expect(r.partiallySucceeded, isTrue);
      expect(r.failedCount, 2);
    });

    test('failureKeys yields BOOKING / EVT- / NEW- prefixed keys', () {
      final r = BookingSaveResult(
        bookingPatch: const OperationFailure('booking failed'),
        eventUpdates: {2: const OperationFailure('update failed')},
        eventCreates: {'new-1': const OperationFailure('create failed')},
        eventDeletes: {9: const OperationFailure('delete failed')},
      );
      final keys = r.failureKeys.map((e) => e.key).toList();
      expect(keys, containsAll(['BOOKING', 'EVT-2', 'NEW-new-1', 'EVT-9']));
    });

    test('all-pending result is not allFailed', () {
      final r = BookingSaveResult(
        bookingPatch: const OperationPending(),
        eventUpdates: const {},
        eventCreates: const {},
        eventDeletes: const {},
      );
      expect(r.allFailed, isFalse,
          reason: 'allFailed requires at least one op to have run');
    });
  });
}
```

- [ ] **Step 3: Run the tests**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/services/booking_save_result_test.dart 2>&1 | tail -10
```

Expected: 5 tests pass.

- [ ] **Step 4: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add test/features/bookings/services/booking_save_result_test.dart
git commit -m "test(mobile): BookingSaveResult predicate coverage"
```

---

## Task 5: Implement `BookingSaveOrchestrator.save`

**Files:**
- Modify: `lib/features/bookings/services/booking_save_orchestrator.dart` (append the orchestrator class)

- [ ] **Step 1: Append the orchestrator implementation**

Add to `lib/features/bookings/services/booking_save_orchestrator.dart` after the existing types:

```dart
import 'package:dio/dio.dart';
import '../../events/data/events_repository.dart';
import '../data/bookings_repository.dart';

/// Runs a [BookingFormSnapshot] sequentially against the server, capturing
/// each sub-op's outcome. The booking PATCH runs first; if it fails the
/// event sub-ops are skipped (they may depend on the booking-level diff).
/// Event sub-ops run in the order: updates → creates → deletes; failures
/// in one don't block subsequent ops in the chain.
class BookingSaveOrchestrator {
  BookingSaveOrchestrator({
    required this.bookingsRepository,
    required this.eventsRepository,
  });

  final BookingsRepository bookingsRepository;
  final EventsRepository eventsRepository;

  Future<BookingSaveResult> save({
    required int bandId,
    required int bookingId,
    required BookingFormSnapshot snapshot,
  }) async {
    OperationStatus bookingPatch = const OperationPending();
    final eventUpdates = <int, OperationStatus>{};
    final eventCreates = <String, OperationStatus>{};
    final eventDeletes = <int, OperationStatus>{};

    // ── Booking PATCH ──────────────────────────────────────────────────
    final patch = snapshot.bookingPatch;
    if (patch == null || patch.isEmpty) {
      bookingPatch = const OperationSuccess();
    } else {
      try {
        await bookingsRepository.updateBooking(
          bandId,
          bookingId,
          name: patch.name,
          eventTypeId: patch.eventTypeId,
          price: patch.price,
          status: patch.status,
          contractOption: patch.contractOption,
          notes: patch.notes,
        );
        bookingPatch = const OperationSuccess();
      } catch (e) {
        bookingPatch = OperationFailure(_messageFor(e));
        // Skip every event sub-op; mark them all pending so the UI
        // knows they haven't run.
        for (final id in snapshot.eventUpdates.keys) {
          eventUpdates[id] = const OperationPending();
        }
        for (final k in snapshot.eventCreates.keys) {
          eventCreates[k] = const OperationPending();
        }
        for (final id in snapshot.eventDeletes) {
          eventDeletes[id] = const OperationPending();
        }
        return BookingSaveResult(
          bookingPatch: bookingPatch,
          eventUpdates: eventUpdates,
          eventCreates: eventCreates,
          eventDeletes: eventDeletes,
        );
      }
    }

    // ── Event updates ──────────────────────────────────────────────────
    for (final entry in snapshot.eventUpdates.entries) {
      try {
        final draft = entry.value;
        await eventsRepository.updateEvent(
          // Existing events are identified by id on the form side, but
          // EventsRepository.updateEvent takes the event's `key` string.
          // The form stores the key alongside the id in EventFormRow;
          // the snapshot's eventUpdates key is the id, and the draft
          // carries the title/date/etc. The orchestrator's caller
          // resolves id→key via the original BookingDetail.events list.
          //
          // For testability we accept the key directly via an
          // EventDraft.key field… but EventDraft has no key. To avoid
          // changing EventDraft, callers must construct snapshot
          // entries with the event's key encoded into the orchestrator
          // payload. For simplicity here, we treat the int key in
          // eventUpdates as the event ID and rely on the booking
          // detail caller to resolve. Tests use a small fake repo
          // that ignores the key argument anyway.
          entry.key.toString(),
          title: draft.title,
          date: draft.date,
          startTime: draft.startTime,
          endTime: draft.endTime,
          venueName: draft.venueName,
          venueAddress: draft.venueAddress,
          price: draft.price,
        );
        eventUpdates[entry.key] = const OperationSuccess();
      } catch (e) {
        eventUpdates[entry.key] = OperationFailure(_messageFor(e));
      }
    }

    // ── Event creates ──────────────────────────────────────────────────
    for (final entry in snapshot.eventCreates.entries) {
      try {
        await bookingsRepository.addEventToBooking(
          bandId,
          bookingId,
          entry.value,
        );
        eventCreates[entry.key] = const OperationSuccess();
      } catch (e) {
        eventCreates[entry.key] = OperationFailure(_messageFor(e));
      }
    }

    // ── Event deletes ──────────────────────────────────────────────────
    for (final id in snapshot.eventDeletes) {
      try {
        await bookingsRepository.removeEventFromBooking(
          bandId,
          bookingId,
          id,
        );
        eventDeletes[id] = const OperationSuccess();
      } catch (e) {
        eventDeletes[id] = OperationFailure(_messageFor(e));
      }
    }

    return BookingSaveResult(
      bookingPatch: bookingPatch,
      eventUpdates: eventUpdates,
      eventCreates: eventCreates,
      eventDeletes: eventDeletes,
    );
  }

  /// Best-effort error message extraction for the inline UI.
  String _messageFor(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        final msg = data['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
      return e.message ?? 'Network error';
    }
    return e.toString();
  }
}
```

**Note for the implementer:** the comment in `eventUpdates` about id-vs-key resolution exists because `EventsRepository.updateEvent` takes a `String key` (the event's UUID), but snapshots map by id. The cleanest fix is to introduce a small `EventFormRow { int? id; String? key; EventDraft draft }` in the form screen and a snapshot key that's a record `({int id, String key})`. For this plan we keep the orchestrator API id-keyed and rely on the form screen to pass the right value; the test in Task 6 uses a fake repo that doesn't care.

**Alternative (simpler):** change `BookingFormSnapshot.eventUpdates` to `Map<String /*event key*/, EventDraft>` and the orchestrator passes the key through directly. This works cleanly because `failureKeys` already emits `"EVT-${k}"` strings.

Pick whichever feels right when implementing — both are mentioned for the implementer's awareness. **Default: use the simpler alternative — `Map<String, EventDraft>` for eventUpdates, where the string is the event's `key`.** Update the value type in Task 3 accordingly if you go this route; mention the choice in the commit message.

- [ ] **Step 2: Analyze**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/bookings/services/booking_save_orchestrator.dart
```

Expected: clean.

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/services/booking_save_orchestrator.dart
git commit -m "feat(mobile): implement BookingSaveOrchestrator.save

Sequential save state machine: booking PATCH first (failure short-
circuits the chain since event ops may depend on booking-level diff);
then event updates → creates → deletes in order. Per-op failures
captured into BookingSaveResult; subsequent ops in the chain still
run so a 422 on a DELETE doesn't block an unrelated PUT."
```

---

## Task 6: Test `BookingSaveOrchestrator.save`

**Files:**
- Create: `test/features/bookings/services/booking_save_orchestrator_test.dart`

- [ ] **Step 1: Write the orchestrator tests**

Create the file with the following structure (10 cases per spec):

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_draft.dart';
import 'package:tts_bandmate/features/bookings/services/booking_save_orchestrator.dart';
import 'package:tts_bandmate/features/events/data/events_repository.dart';

/// Records every HTTP call and returns canned responses keyed by
/// (method, path) → response. Lets us simulate per-op success/failure.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);
  final Map<String, ResponseBody Function()> script;
  final List<RequestOptions> calls = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    calls.add(options);
    final key = '${options.method} ${options.path}';
    final builder = script[key];
    if (builder == null) {
      return _json(500, {'message': 'Unscripted request: $key'});
    }
    return builder();
  }
}

ResponseBody _json(int status, Object body) {
  final encoded = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(encoded, status, headers: {
    'content-type': ['application/json'],
  });
}

Dio _dio(_ScriptedAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;

BookingSaveOrchestrator _orchestrator(_ScriptedAdapter adapter) {
  final dio = _dio(adapter);
  return BookingSaveOrchestrator(
    bookingsRepository: BookingsRepository(dio),
    eventsRepository: EventsRepository(dio),
  );
}

Map<String, dynamic> _bookingFixture() => {
      'id': 42,
      'name': 'Test',
      'start_date': '2026-06-13',
      'end_date': '2026-06-13',
      'event_count': 1,
      'is_multi_event': false,
      'is_paid': false,
      'contacts': [],
      'events': [],
      'payments': [],
    };

Map<String, dynamic> _eventFixture(int id) => {
      'id': id,
      'key': 'evt_$id',
      'title': 'E',
      'date': '2026-06-13',
      'event_source': 'booking',
      'can_write': false,
      'members': [],
      'timeline': [],
      'lodging': [],
      'contacts': [],
      'attachments': [],
    };

void main() {
  group('BookingSaveOrchestrator.save', () {
    test('empty snapshot — no API calls, result allSucceeded', () async {
      final adapter = _ScriptedAdapter({});
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(),
      );
      expect(adapter.calls, isEmpty);
      expect(result.allSucceeded, isTrue);
    });

    test('booking patch only succeeds', () async {
      final adapter = _ScriptedAdapter({
        'PATCH /api/mobile/bands/7/bookings/42': () =>
            _json(200, {'booking': _bookingFixture()}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(
          bookingPatch: BookingFieldDiff(name: 'Renamed'),
        ),
      );
      expect(adapter.calls, hasLength(1));
      expect(result.allSucceeded, isTrue);
    });

    test('booking patch fails — event sub-ops skipped', () async {
      final adapter = _ScriptedAdapter({
        'PATCH /api/mobile/bands/7/bookings/42': () =>
            _json(422, {'message': 'Validation failed'}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(
          bookingPatch: BookingFieldDiff(name: 'Bad'),
          eventDeletes: {99},
        ),
      );
      // Only the PATCH was attempted; the DELETE did not fire.
      expect(adapter.calls, hasLength(1));
      expect(result.bookingPatch, isA<OperationFailure>());
      expect(result.eventDeletes[99], isA<OperationPending>());
    });

    test('all event PUTs succeed (using event keys, not ids)', () async {
      // If the implementer chose Map<String,EventDraft> for eventUpdates,
      // the orchestrator PUTs to /api/mobile/events/{key}.
      final adapter = _ScriptedAdapter({
        'PUT /api/mobile/events/evt_1': () => _json(200, {'event': _eventFixture(1)}),
        'PUT /api/mobile/events/evt_2': () => _json(200, {'event': _eventFixture(2)}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: BookingFormSnapshot(
          eventUpdates: {
            'evt_1': const EventDraft(title: 'A', date: '2026-06-13'),
            'evt_2': const EventDraft(title: 'B', date: '2026-06-14'),
          },
        ),
      );
      expect(adapter.calls, hasLength(2));
      expect(result.allSucceeded, isTrue);
    });

    test('all event POSTs succeed', () async {
      final adapter = _ScriptedAdapter({
        'POST /api/mobile/bands/7/bookings/42/events': () =>
            _json(200, {'event': _eventFixture(99)}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: BookingFormSnapshot(
          eventCreates: {
            'new-1': const EventDraft(title: 'New', date: '2026-06-15'),
          },
        ),
      );
      expect(result.allSucceeded, isTrue);
    });

    test('event DELETE 422 — captured as OperationFailure with message',
        () async {
      final adapter = _ScriptedAdapter({
        'DELETE /api/mobile/bands/7/bookings/42/events/9': () => _json(422, {
              'message': 'Cannot delete the last event of a booking.',
            }),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(eventDeletes: {9}),
      );
      final status = result.eventDeletes[9];
      expect(status, isA<OperationFailure>());
      expect((status as OperationFailure).message,
          contains('Cannot delete'));
    });

    test('mixed success/failure — partiallySucceeded', () async {
      final adapter = _ScriptedAdapter({
        'PATCH /api/mobile/bands/7/bookings/42': () =>
            _json(200, {'booking': _bookingFixture()}),
        'PUT /api/mobile/events/evt_1': () => _json(200, {'event': _eventFixture(1)}),
        'POST /api/mobile/bands/7/bookings/42/events': () =>
            _json(500, {'message': 'Server error'}),
        'DELETE /api/mobile/bands/7/bookings/42/events/9': () =>
            _json(200, {'success': true}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: BookingFormSnapshot(
          bookingPatch: const BookingFieldDiff(name: 'X'),
          eventUpdates: {'evt_1': const EventDraft(title: 'A', date: '2026-06-13')},
          eventCreates: {'new-1': const EventDraft(title: 'N', date: '2026-06-15')},
          eventDeletes: {9},
        ),
      );
      expect(result.partiallySucceeded, isTrue);
      expect(result.failedCount, 1);
      expect(result.failureKeys.first.key, 'NEW-new-1');
    });

    test('network-out — every call throws DioException — allFailed', () async {
      final adapter = _ScriptedAdapter({});  // every request becomes 500
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(
          bookingPatch: BookingFieldDiff(name: 'X'),
        ),
      );
      expect(result.allFailed, isTrue);
    });

    test('retry semantics — second save with reduced snapshot only re-runs failures',
        () async {
      // First pass: PATCH succeeds, POST fails. Second pass with a snapshot
      // containing only the failed POST should fire just one request.
      var postShouldFail = true;
      final adapter = _ScriptedAdapter({
        'PATCH /api/mobile/bands/7/bookings/42': () =>
            _json(200, {'booking': _bookingFixture()}),
        'POST /api/mobile/bands/7/bookings/42/events': () => postShouldFail
            ? _json(500, {'message': 'oops'})
            : _json(200, {'event': _eventFixture(99)}),
      });
      final orch = _orchestrator(adapter);

      final first = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: BookingFormSnapshot(
          bookingPatch: const BookingFieldDiff(name: 'X'),
          eventCreates: {'new-1': const EventDraft(title: 'N', date: '2026-06-15')},
        ),
      );
      expect(first.partiallySucceeded, isTrue);

      postShouldFail = false;
      adapter.calls.clear();
      final second = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: BookingFormSnapshot(
          eventCreates: {'new-1': const EventDraft(title: 'N', date: '2026-06-15')},
        ),
      );
      expect(adapter.calls, hasLength(1));
      expect(second.allSucceeded, isTrue);
    });

    test('all-pending result (no ops actually run) — not allFailed', () async {
      // Sanity: an all-pending snapshot post-orchestrator-call shouldn't
      // assert allFailed (a property already covered in the value-type
      // tests but worth re-checking against the integrated implementation).
      final adapter = _ScriptedAdapter({});
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(),
      );
      expect(result.allFailed, isFalse);
      expect(result.allSucceeded, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the tests**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/services/booking_save_orchestrator_test.dart 2>&1 | tail -15
```

Expected: 10 tests pass.

If the implementer chose the id-keyed `eventUpdates` variant in Task 5, the PUT path assertion in the "all event PUTs succeed" test needs to change accordingly — but the recommendation is the key-keyed variant.

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add test/features/bookings/services/booking_save_orchestrator_test.dart
git commit -m "test(mobile): exhaustive BookingSaveOrchestrator coverage

Ten cases: empty snapshot, booking-only, booking-fails-skips-events,
event PUT/POST/DELETE happy paths, DELETE 422 message capture, mixed
success/failure, network-out (allFailed), retry semantics, all-pending."
```

---

## Task 7: `EventSubFormCard` widget

**Files:**
- Create: `lib/features/bookings/widgets/event_sub_form_card.dart`
- Create: `test/features/bookings/widgets/event_sub_form_card_test.dart`

- [ ] **Step 1: Write the widget**

```dart
import 'package:flutter/cupertino.dart';
import '../data/models/event_draft.dart';

/// Single event row inside the booking form. Cupertino-styled.
///
/// The form state holds an `EventFormRow` (id+key+draft) per row; this
/// widget receives the draft + a local key for identity, plus per-row
/// status callbacks.
class EventSubFormCard extends StatelessWidget {
  const EventSubFormCard({
    super.key,
    required this.draft,
    required this.canDelete,
    this.saveError,
    required this.onChange,
    required this.onDelete,
    this.onRetryRow,
  });

  final EventDraft draft;
  final bool canDelete;
  final String? saveError;
  final ValueChanged<EventDraft> onChange;
  final VoidCallback onDelete;
  final VoidCallback? onRetryRow;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CupertinoColors.separator.resolveFrom(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.title.isEmpty ? 'Untitled event' : draft.title,
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: canDelete ? onDelete : null,
                child: Icon(
                  CupertinoIcons.trash,
                  color: canDelete
                      ? CupertinoColors.destructiveRed
                      : CupertinoColors.inactiveGray,
                ),
              ),
            ],
          ),
          if (saveError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                onTap: onRetryRow,
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.exclamationmark_circle_fill,
                      color: CupertinoColors.destructiveRed,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Save failed — tap to retry',
                      style: TextStyle(
                        color: CupertinoColors.destructiveRed,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          CupertinoTextField(
            placeholder: 'Title',
            controller: TextEditingController(text: draft.title),
            onChanged: (v) => onChange(_copyWith(title: v)),
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            placeholder: 'Date (YYYY-MM-DD)',
            controller: TextEditingController(text: draft.date),
            onChanged: (v) => onChange(_copyWith(date: v)),
          ),
          // Start time / end time / venue inputs follow the same pattern.
          // Implementer may swap CupertinoTextField for CupertinoDatePicker
          // launchers if the surrounding screen already uses them.
        ],
      ),
    );
  }

  EventDraft _copyWith({
    String? title,
    String? date,
    String? startTime,
    String? endTime,
    String? venueName,
    String? venueAddress,
    String? price,
  }) {
    return EventDraft(
      title: title ?? draft.title,
      date: date ?? draft.date,
      startTime: startTime ?? draft.startTime,
      endTime: endTime ?? draft.endTime,
      venueName: venueName ?? draft.venueName,
      venueAddress: venueAddress ?? draft.venueAddress,
      price: price ?? draft.price,
    );
  }
}
```

- [ ] **Step 2: Write the widget test**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_draft.dart';
import 'package:tts_bandmate/features/bookings/widgets/event_sub_form_card.dart';

void main() {
  testWidgets('renders inline error when saveError non-null', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: Center(
        child: EventSubFormCard(
          draft: const EventDraft(title: 'X', date: '2026-06-13'),
          canDelete: true,
          saveError: 'Server error',
          onChange: (_) {},
          onDelete: () {},
        ),
      ),
    ));
    expect(find.text('Save failed — tap to retry'), findsOneWidget);
  });

  testWidgets('does not render error when saveError null', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: Center(
        child: EventSubFormCard(
          draft: const EventDraft(title: 'X', date: '2026-06-13'),
          canDelete: true,
          onChange: (_) {},
          onDelete: () {},
        ),
      ),
    ));
    expect(find.text('Save failed — tap to retry'), findsNothing);
  });

  testWidgets('delete button disabled when canDelete is false', (tester) async {
    var deleteCalled = false;
    await tester.pumpWidget(CupertinoApp(
      home: Center(
        child: EventSubFormCard(
          draft: const EventDraft(title: 'X', date: '2026-06-13'),
          canDelete: false,
          onChange: (_) {},
          onDelete: () => deleteCalled = true,
        ),
      ),
    ));
    final btn = find.byIcon(CupertinoIcons.trash);
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    await tester.pump();
    expect(deleteCalled, isFalse);
  });

  testWidgets('onRetryRow fires when tapping the inline error', (tester) async {
    var retryCalled = false;
    await tester.pumpWidget(CupertinoApp(
      home: Center(
        child: EventSubFormCard(
          draft: const EventDraft(title: 'X', date: '2026-06-13'),
          canDelete: true,
          saveError: 'Server error',
          onChange: (_) {},
          onDelete: () {},
          onRetryRow: () => retryCalled = true,
        ),
      ),
    ));
    await tester.tap(find.text('Save failed — tap to retry'));
    await tester.pump();
    expect(retryCalled, isTrue);
  });
}
```

- [ ] **Step 3: Run tests + analyze**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/bookings/widgets/event_sub_form_card.dart && flutter test test/features/bookings/widgets/event_sub_form_card_test.dart 2>&1 | tail -10
```

Expected: analyze clean; 4 tests pass.

- [ ] **Step 4: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/widgets/event_sub_form_card.dart test/features/bookings/widgets/event_sub_form_card_test.dart
git commit -m "feat(mobile/ui): EventSubFormCard with inline save-error indicator"
```

---

## Task 8: `BookingFormPartialFailureBanner` widget

**Files:**
- Create: `lib/features/bookings/widgets/booking_form_partial_failure_banner.dart`
- Create: `test/features/bookings/widgets/booking_form_partial_failure_banner_test.dart`

- [ ] **Step 1: Write the widget**

```dart
import 'package:flutter/cupertino.dart';

/// Cupertino-styled banner shown only on the all-failure save path.
/// Tap-to-dismiss returns control to the user without changing form state.
class BookingFormPartialFailureBanner extends StatelessWidget {
  const BookingFormPartialFailureBanner({
    super.key,
    required this.onDismiss,
  });

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: CupertinoColors.destructiveRed.withOpacity(0.12),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              color: CupertinoColors.destructiveRed,
              size: 18,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'No changes saved — check your connection',
                style: TextStyle(color: CupertinoColors.destructiveRed),
              ),
            ),
            const Icon(
              CupertinoIcons.xmark,
              color: CupertinoColors.destructiveRed,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Write the test**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/widgets/booking_form_partial_failure_banner.dart';

void main() {
  testWidgets('renders the spec copy', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: BookingFormPartialFailureBanner(onDismiss: () {}),
    ));
    expect(find.text('No changes saved — check your connection'), findsOneWidget);
  });

  testWidgets('tap fires onDismiss', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(CupertinoApp(
      home: BookingFormPartialFailureBanner(onDismiss: () => dismissed = true),
    ));
    await tester.tap(find.byType(BookingFormPartialFailureBanner));
    expect(dismissed, isTrue);
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/bookings/widgets/booking_form_partial_failure_banner.dart && flutter test test/features/bookings/widgets/booking_form_partial_failure_banner_test.dart 2>&1 | tail -5
```

Expected: 2 tests pass.

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/widgets/booking_form_partial_failure_banner.dart test/features/bookings/widgets/booking_form_partial_failure_banner_test.dart
git commit -m "feat(mobile/ui): partial-failure save banner widget"
```

---

## Task 9: `BookingFormNavigationGuard` widget

**Files:**
- Create: `lib/features/bookings/widgets/booking_form_navigation_guard.dart`
- Create: `test/features/bookings/widgets/booking_form_navigation_guard_test.dart`

- [ ] **Step 1: Write the guard**

```dart
import 'package:flutter/cupertino.dart';
import '../services/booking_save_orchestrator.dart';

class BookingFormNavigationGuard {
  /// Returns true when the user may leave (no pending failures, or they
  /// explicitly tapped Discard). Returns false when the user elected to
  /// stay (caller should NOT pop).
  static Future<bool> shouldAllowLeave(
    BuildContext context,
    BookingSaveResult? result,
  ) async {
    if (result == null || result.failedCount == 0) return true;

    final savedCount = _countSuccesses(result);
    final failedCount = result.failedCount;

    final outcome = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Unsaved changes'),
        content: Text(
          '$savedCount ${savedCount == 1 ? 'change' : 'changes'} saved, '
          '$failedCount still failed. Leave anyway?',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay & Retry'),
          ),
        ],
      ),
    );
    return outcome ?? false;
  }

  static int _countSuccesses(BookingSaveResult r) {
    var n = 0;
    if (r.bookingPatch is OperationSuccess) n++;
    n += r.eventUpdates.values.whereType<OperationSuccess>().length;
    n += r.eventCreates.values.whereType<OperationSuccess>().length;
    n += r.eventDeletes.values.whereType<OperationSuccess>().length;
    return n;
  }
}
```

- [ ] **Step 2: Write the test**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/services/booking_save_orchestrator.dart';
import 'package:tts_bandmate/features/bookings/widgets/booking_form_navigation_guard.dart';

Widget _harness({required Future<bool> Function() onTap}) {
  return CupertinoApp(
    home: Builder(
      builder: (ctx) => CupertinoButton(
        child: const Text('Try Leave'),
        onPressed: () async {
          final allowed = await onTap();
          // Stash the outcome on the binding via debug print so the test
          // can read it via the returned future.
          debugPrint('guard returned: $allowed');
        },
      ),
    ),
  );
}

void main() {
  testWidgets('returns true immediately when result is null', (tester) async {
    late bool outcome;
    await tester.pumpWidget(CupertinoApp(
      home: Builder(
        builder: (ctx) => CupertinoButton(
          child: const Text('Try Leave'),
          onPressed: () async {
            outcome =
                await BookingFormNavigationGuard.shouldAllowLeave(ctx, null);
          },
        ),
      ),
    ));
    await tester.tap(find.text('Try Leave'));
    await tester.pumpAndSettle();
    expect(outcome, isTrue);
  });

  testWidgets('shows alert and returns true on Discard', (tester) async {
    late bool outcome;
    final result = BookingSaveResult(
      bookingPatch: const OperationSuccess(),
      eventUpdates: {'evt_1': const OperationFailure('boom')},
      eventCreates: const {},
      eventDeletes: const {},
    );
    await tester.pumpWidget(CupertinoApp(
      home: Builder(
        builder: (ctx) => CupertinoButton(
          child: const Text('Try Leave'),
          onPressed: () async {
            outcome =
                await BookingFormNavigationGuard.shouldAllowLeave(ctx, result);
          },
        ),
      ),
    ));
    await tester.tap(find.text('Try Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(find.textContaining('1 still failed'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(outcome, isTrue);
  });

  testWidgets('returns false on Stay & Retry', (tester) async {
    late bool outcome;
    final result = BookingSaveResult(
      bookingPatch: const OperationFailure('boom'),
      eventUpdates: const {},
      eventCreates: const {},
      eventDeletes: const {},
    );
    await tester.pumpWidget(CupertinoApp(
      home: Builder(
        builder: (ctx) => CupertinoButton(
          child: const Text('Try Leave'),
          onPressed: () async {
            outcome =
                await BookingFormNavigationGuard.shouldAllowLeave(ctx, result);
          },
        ),
      ),
    ));
    await tester.tap(find.text('Try Leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stay & Retry'));
    await tester.pumpAndSettle();
    expect(outcome, isFalse);
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/widgets/booking_form_navigation_guard_test.dart 2>&1 | tail -10
```

Expected: 3 tests pass.

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/widgets/booking_form_navigation_guard.dart test/features/bookings/widgets/booking_form_navigation_guard_test.dart
git commit -m "feat(mobile/ui): navigation guard CupertinoAlertDialog"
```

---

## Task 10: Rewrite `booking_form_screen.dart`

**Files:**
- Modify: `lib/features/bookings/screens/booking_form_screen.dart`

**Note:** this is the largest task in the chunk. The current file is 1,449 lines; targeting roughly 700-900 lines after the rewrite (the extracted widgets/service take a lot of the volume).

- [ ] **Step 1: Inspect the screen's current structure**

```bash
cd /home/eddie/github/tts_bandmate && grep -nE "^class |^  Future|^  void |^  Widget " lib/features/bookings/screens/booking_form_screen.dart | head -40
```

Identify the StatefulWidget + State class names and the existing save / build methods.

- [ ] **Step 2: Restructure the state class to hold form rows**

Inside the State class, replace the existing date/time/venue field controllers with:

```dart
List<_EventFormRow> _eventRows = [];
Set<int> _deletedEventIds = {};
BookingSaveResult? _lastSaveResult;
int _localKeyCounter = 0;

String _nextLocalKey() => 'new-${++_localKeyCounter}';
```

Add a private `_EventFormRow` class at the bottom of the file:

```dart
class _EventFormRow {
  _EventFormRow({
    this.id,
    this.key,
    required this.draft,
    this.localKey,
  });

  /// Set for existing events; null for newly-added rows.
  final int? id;

  /// Event UUID key (server-assigned). Set for existing events; null for new.
  final String? key;

  /// Local string key for new rows so the UI can map per-op failures back.
  final String? localKey;

  EventDraft draft;
}
```

- [ ] **Step 3: Initialize rows from the loaded `BookingDetail`**

In the State's `initState` (or wherever the booking is loaded), populate `_eventRows`:

```dart
_eventRows = booking.events.map((e) => _EventFormRow(
      id: e.id,
      key: e.key,
      draft: EventDraft(
        title: e.title,
        date: e.date,
        startTime: e.startTime ?? e.time,
        endTime: e.endTime,
        venueName: e.venueName,
        venueAddress: e.venueAddress,
        price: e.price,
      ),
    )).toList();
```

- [ ] **Step 4: Replace the events-section rendering**

Wherever the form previously rendered a single date+time+venue block, render the new sub-form list:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('Events',
        style: CupertinoTheme.of(context).textTheme.navTitleTextStyle),
    ..._eventRows.map((row) {
      final keyForError = row.id != null
          ? 'EVT-${row.id}'
          : 'NEW-${row.localKey}';
      final err = _lastSaveResult?.failureKeys
          .where((e) => e.key == keyForError)
          .map((e) => e.value.message)
          .firstOrNull;
      return EventSubFormCard(
        key: ValueKey(row.id ?? row.localKey),
        draft: row.draft,
        canDelete: _eventRows.length > 1,
        saveError: err,
        onChange: (newDraft) {
          setState(() => row.draft = newDraft);
        },
        onDelete: () {
          setState(() {
            if (row.id != null) _deletedEventIds.add(row.id!);
            _eventRows.remove(row);
          });
        },
        onRetryRow: _onSavePressed,
      );
    }),
    CupertinoButton(
      child: const Text('+ Add event'),
      onPressed: () {
        setState(() {
          _eventRows.add(_EventFormRow(
            localKey: _nextLocalKey(),
            draft: EventDraft(
              title: '${_nameController.text} Event',
              date: _eventRows.lastOrNull?.draft.date ?? '',
            ),
          ));
        });
      },
    ),
  ],
)
```

- [ ] **Step 5: Implement `_onSavePressed`**

```dart
Future<void> _onSavePressed() async {
  if (_isSaving) return;
  setState(() => _isSaving = true);

  final snapshot = _buildSnapshot();

  // No diff = no-op (treat as success).
  if (snapshot.isEmpty) {
    setState(() => _isSaving = false);
    return;
  }

  final orchestrator = BookingSaveOrchestrator(
    bookingsRepository: ref.read(bookingsRepositoryProvider),
    eventsRepository: ref.read(eventsRepositoryProvider),
  );
  final result = await orchestrator.save(
    bandId: widget.bandId,
    bookingId: widget.bookingId,
    snapshot: snapshot,
  );

  setState(() {
    _isSaving = false;
    _lastSaveResult = result;
  });

  if (result.allSucceeded) {
    ref
        .read(cacheInvalidatorProvider)
        .onBookingEventsChanged(
            bandId: widget.bandId, bookingId: widget.bookingId);
    if (mounted) Navigator.of(context).pop(true);
  }
  // On partial / all failure, the form stays mounted; the build()
  // picks up _lastSaveResult and renders inline errors + banner.
}
```

- [ ] **Step 6: Implement `_buildSnapshot`**

```dart
BookingFormSnapshot _buildSnapshot() {
  // Build BookingFieldDiff only for changed booking-level fields.
  final patch = BookingFieldDiff(
    name: _nameController.text != _originalBooking.name
        ? _nameController.text
        : null,
    eventTypeId: _eventTypeId != _originalBooking.eventTypeId
        ? _eventTypeId
        : null,
    price: _priceController.text != _originalBooking.price
        ? _priceController.text
        : null,
    status: _status != _originalBooking.status ? _status : null,
    contractOption: _contractOption != _originalBooking.contractOption
        ? _contractOption
        : null,
    notes: _notesController.text != (_originalBooking.notes ?? '')
        ? _notesController.text
        : null,
  );

  final eventUpdates = <String, EventDraft>{};
  final eventCreates = <String, EventDraft>{};

  for (final row in _eventRows) {
    if (row.id != null && row.key != null) {
      // Only include the row if anything changed vs the original.
      final original = _originalBooking.events.firstWhere((e) => e.id == row.id);
      if (_eventDraftDiffersFromOriginal(row.draft, original)) {
        eventUpdates[row.key!] = row.draft;
      }
    } else if (row.localKey != null) {
      eventCreates[row.localKey!] = row.draft;
    }
  }

  return BookingFormSnapshot(
    bookingPatch: patch.isEmpty ? null : patch,
    eventUpdates: eventUpdates,
    eventCreates: eventCreates,
    eventDeletes: _deletedEventIds,
  );
}

bool _eventDraftDiffersFromOriginal(EventDraft draft, EventSummary original) {
  return draft.title != original.title ||
      draft.date != original.date ||
      draft.startTime != (original.startTime ?? original.time) ||
      draft.endTime != original.endTime ||
      draft.venueName != original.venueName ||
      draft.venueAddress != original.venueAddress ||
      draft.price != original.price;
}
```

- [ ] **Step 7: Replace the Save button rendering**

```dart
CupertinoButton.filled(
  onPressed: _isSaving ? null : _onSavePressed,
  child: _isSaving
      ? const CupertinoActivityIndicator()
      : Text(
          _lastSaveResult?.partiallySucceeded == true
              ? 'Retry Failed (${_lastSaveResult!.failedCount})'
              : 'Save Booking',
          style: TextStyle(
            color: _lastSaveResult?.partiallySucceeded == true
                ? CupertinoColors.white
                : null,
          ),
        ),
)
```

For destructive tint on the retry state, wrap the button in a `CupertinoTheme` override that sets `primaryColor: CupertinoColors.destructiveRed` when `_lastSaveResult?.partiallySucceeded == true`, OR use a custom `Container(color: red)` wrapper. Simplest: just swap to `CupertinoButton.filled(color: CupertinoColors.destructiveRed, ...)` when partial.

- [ ] **Step 8: Wire the navigation guard**

Wrap the screen's `Scaffold` / `CupertinoPageScaffold` in a `PopScope`:

```dart
PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, _) async {
    if (didPop) return;
    final allow = await BookingFormNavigationGuard.shouldAllowLeave(
        context, _lastSaveResult);
    if (allow && mounted) {
      Navigator.of(context).pop();
    }
  },
  child: CupertinoPageScaffold(...),
)
```

- [ ] **Step 9: Render the partial-failure banner**

In `build()`, conditionally render at the top of the form body:

```dart
if (_lastSaveResult?.allFailed == true)
  BookingFormPartialFailureBanner(
    onDismiss: () => setState(() => _lastSaveResult = null),
  ),
```

- [ ] **Step 10: Analyze the screen**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/bookings/screens/booking_form_screen.dart 2>&1 | tail -10
```

Expected: clean (or near-clean — small fixes may be needed).

- [ ] **Step 11: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/screens/booking_form_screen.dart
git commit -m "$(cat <<'EOF'
feat(mobile/ui): rewrite booking form for multi-event editing

Replaces the single-event date/time/venue block with a stack of
EventSubFormCards. The save flow uses BookingSaveOrchestrator to
run a sequential PATCH + N event ops; partial failures stay on
screen with per-row inline error indicators and the Save button
transforms to "Retry Failed (N)" with destructive tint. Full-failure
shows the banner; navigation-guard alert prevents accidental
abandonment with unsaved failures.
EOF
)"
```

---

## Task 11: Add Save-button widget test

**Files:**
- Create: `test/features/bookings/screens/booking_form_save_button_test.dart`

Note: testing the screen end-to-end is heavy. This widget test extracts the Save-button-state logic into a small helper widget (or pumps the form with a pre-set `_lastSaveResult`). For pragmatism, this task tests the **save button rendering** by pumping a minimal stand-in that mimics the form's button logic.

- [ ] **Step 1: Extract a `BookingSaveButton` widget**

Refactor the Save button block from `booking_form_screen.dart` into a new widget in the same screen file (or a separate widget file). Suggested location: `lib/features/bookings/widgets/booking_save_button.dart`. Test against it directly. Keep the API tight:

```dart
class BookingSaveButton extends StatelessWidget {
  const BookingSaveButton({
    super.key,
    required this.isSaving,
    required this.lastResult,
    required this.onPressed,
  });

  final bool isSaving;
  final BookingSaveResult? lastResult;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) { ... }
}
```

- [ ] **Step 2: Write the test**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/services/booking_save_orchestrator.dart';
import 'package:tts_bandmate/features/bookings/widgets/booking_save_button.dart';

void main() {
  testWidgets('pristine state shows "Save Booking"', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: BookingSaveButton(
        isSaving: false,
        lastResult: null,
        onPressed: () {},
      ),
    ));
    expect(find.text('Save Booking'), findsOneWidget);
    expect(find.textContaining('Retry'), findsNothing);
  });

  testWidgets('partial failure shows "Retry Failed (N)"', (tester) async {
    final result = BookingSaveResult(
      bookingPatch: const OperationSuccess(),
      eventUpdates: {
        'evt_1': const OperationFailure('boom'),
        'evt_2': const OperationFailure('boom'),
      },
      eventCreates: const {},
      eventDeletes: const {},
    );
    await tester.pumpWidget(CupertinoApp(
      home: BookingSaveButton(
        isSaving: false,
        lastResult: result,
        onPressed: () {},
      ),
    ));
    expect(find.text('Retry Failed (2)'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/bookings/widgets/booking_save_button.dart && flutter test test/features/bookings/screens/booking_form_save_button_test.dart 2>&1 | tail -5
```

Expected: 2 tests pass.

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/widgets/booking_save_button.dart test/features/bookings/screens/booking_form_save_button_test.dart
git commit -m "feat(mobile/ui): BookingSaveButton widget + state coverage"
```

---

## Task 12: Rewrite `booking_detail_screen.dart`

**Files:**
- Modify: `lib/features/bookings/screens/booking_detail_screen.dart`

- [ ] **Step 1: Replace legacy field reads**

The current 720-line screen has roughly 10 broken-field reads (`venueName`, `venueAddress`, `date`, `startTime`, etc., plus a `BookingEvent` class reference). Working in two passes:

**Pass A — field rename (mechanical):**

```bash
cd /home/eddie/github/tts_bandmate && sed -i 's/booking\.venueName/booking.venueSummary/g; s/booking\.venueAddress/booking.events.firstOrNull?.venueAddress/g; s/booking\.date/booking.startDate/g; s/booking\.startTime/booking.events.firstOrNull?.startTime/g; s/booking\.endTime/booking.events.firstOrNull?.endTime/g' lib/features/bookings/screens/booking_detail_screen.dart
```

Then visually re-read the file and adjust any sed misfires (e.g., `firstOrNull?.venueAddress` may need null-guards in template strings).

**Pass B — remove `BookingEvent` class reference at line 669:**

The screen references the deleted `BookingEvent` class. Replace it with `EventSummary`:

```bash
cd /home/eddie/github/tts_bandmate && grep -n "BookingEvent" lib/features/bookings/screens/booking_detail_screen.dart
```

Replace each occurrence with `EventSummary`. Add the import if missing:

```dart
import '../../events/data/models/event_summary.dart';
```

- [ ] **Step 2: Add the engagement summary strip near the top**

Above the existing financial/schedule sections, add:

```dart
Widget _engagementSummary(BookingDetail booking) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                booking.name,
                style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle,
              ),
            ),
            if (booking.isMultiEvent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: CupertinoColors.activeBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${booking.eventCount} events',
                  style: const TextStyle(
                    color: CupertinoColors.activeBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _subtitleFor(booking),
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
            fontSize: 14,
          ),
        ),
      ],
    ),
  );
}

String _subtitleFor(BookingDetail booking) {
  final count = booking.eventCount;
  final dateRange = _formatDateRangeFor(booking);
  final venue = booking.venueSummary;
  final parts = <String>['$count ${count == 1 ? 'event' : 'events'}', dateRange];
  if (venue != null && venue.isNotEmpty) parts.add(venue);
  return parts.join(' · ');
}

String _formatDateRangeFor(BookingDetail booking) {
  if (booking.startDate == booking.endDate) {
    return _shortDate(booking.startDate);
  }
  // ... single-month vs cross-month formatting; reuse the logic mirrored
  // from BookingSummary.displayDateRange.
  return '${_shortDate(booking.startDate)} – ${_shortDate(booking.endDate)}';
}

String _shortDate(String iso) {
  try {
    final d = DateTime.parse(iso);
    return DateFormat('MMM d').format(d);
  } catch (_) {
    return iso;
  }
}
```

Call `_engagementSummary(booking)` at the top of the build's child list.

- [ ] **Step 3: Add the events section**

After the financials block, render:

```dart
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Events', style: CupertinoTheme.of(context).textTheme.navTitleTextStyle),
      const SizedBox(height: 8),
      ...booking.events.map((e) => _eventCard(e)),
      CupertinoButton(
        child: const Text('+ Add event'),
        onPressed: () {
          // Open booking form in edit mode pre-focused on Events section.
          // For simplicity, just navigate to the form screen.
          context.push('/bands/${booking.band?.id}/bookings/${booking.id}/edit');
        },
      ),
    ],
  ),
);
```

`_eventCard(e)` is a simple `GestureDetector` + `Container` rendering title, date, time range, venue, and tapping navigates to `/events/${e.key}`.

- [ ] **Step 4: Add the itemization summary**

Conditional block:

```dart
if (booking.isMultiEvent &&
    booking.events.any((e) =>
        e.price != null && (double.tryParse(e.price!) ?? 0) > 0))
  _itemizationSummary(booking),
```

Where `_itemizationSummary` renders the breakdown. Mirror the web's `ItemizationSummary.vue` formatting.

- [ ] **Step 5: Analyze + commit**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/bookings/screens/booking_detail_screen.dart 2>&1 | tail -10
```

Expected: clean.

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/screens/booking_detail_screen.dart
git commit -m "feat(mobile/ui): rewrite booking detail for multi-event model

New top-to-bottom layout: engagement summary strip (with multi-event
chip), financials, events stack with tappable cards + Add event,
optional itemization summary for priced multi-event bookings, then
the existing payments/contacts/contract/notes/history sections.
All legacy field reads replaced with new accessors."
```

---

## Task 13: Update `bookings_screen.dart` list card

**Files:**
- Modify: `lib/features/bookings/screens/bookings_screen.dart`

- [ ] **Step 1: Field-rename pass**

```bash
cd /home/eddie/github/tts_bandmate && sed -i 's/\.parsedDate/.parsedStartDate/g; s/booking\.venueName/booking.venueSummary/g' lib/features/bookings/screens/bookings_screen.dart
```

Verify the `startTime` references (lines around 762-764) read `booking.events.firstOrNull?.startTime` instead — sed won't handle these correctly; do them by hand.

- [ ] **Step 2: Add the multi-event chip + subtitle reformat**

Locate where the list card is built (around line 700–770 based on the error list). After the title text, conditionally render the chip:

```dart
if (booking.isMultiEvent) ...[
  const SizedBox(width: 8),
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: CupertinoColors.activeBlue.withOpacity(0.15),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      '${booking.eventCount} events',
      style: const TextStyle(
        color: CupertinoColors.activeBlue,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),
  ),
],
```

For the subtitle, replace the existing one-line builder with:

```dart
String _subtitleFor(BookingSummary b) {
  if (b.isMultiEvent) {
    final venue = b.venueSummary ?? 'Multiple venues';
    return '${b.eventCount} events · ${b.displayDateRange} · $venue';
  }
  final primary = b.events.firstOrNull;
  final dateStr = b.displayDateRange;
  final time = primary?.startTime;
  final venue = b.venueSummary ?? '';
  final parts = [dateStr, if (time != null) time, if (venue.isNotEmpty) venue];
  return parts.join(' · ');
}
```

- [ ] **Step 3: Analyze + commit**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/bookings/screens/bookings_screen.dart 2>&1 | tail -5
```

Expected: clean.

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/screens/bookings_screen.dart
git commit -m "feat(mobile/ui): bookings list subtitle + multi-event chip"
```

---

## Task 14: Add bookings list card widget test

**Files:**
- Create: `test/features/bookings/screens/bookings_list_card_test.dart`

- [ ] **Step 1: Write a focused test that pumps the list with two fixture bookings**

```dart
// Use the same BookingSummary helper from Task 2 to build fixtures.
// Pump BookingsScreen (or extract the list-card builder into a small
// public widget you can pump in isolation).
//
// Assertions:
//   - 'Three Show Run' booking shows "3 events" text.
//   - 'Solo' booking does not show any "N events" chip text.
//   - Subtitle formats match spec for each.
```

If extracting the list card builder is heavy, alternative: write a `BookingListCard` widget in `lib/features/bookings/widgets/booking_list_card.dart`, use it from the screen, and test that widget directly. The screen test becomes trivial.

- [ ] **Step 2: Run + commit**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/screens/bookings_list_card_test.dart 2>&1 | tail -5
```

Expected: pass.

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/widgets/booking_list_card.dart test/features/bookings/screens/bookings_list_card_test.dart
git commit -m "test(mobile/ui): bookings list card subtitle + chip coverage"
```

---

## Task 15: Booking contract — "verbal agreement" wording

**Files:**
- Modify: `lib/features/bookings/screens/booking_contract_screen.dart`
- Create: `test/features/bookings/screens/booking_contract_screen_test.dart`

- [ ] **Step 1: Find the "no contract" rendering block**

```bash
cd /home/eddie/github/tts_bandmate && grep -nE "none|No contract|no contract" lib/features/bookings/screens/booking_contract_screen.dart | head
```

- [ ] **Step 2: Replace the copy**

When `booking.contractOption == 'none'`, the screen should render:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      'Verbal agreement — no contract on file',
      style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
            fontWeight: FontWeight.w500,
          ),
    ),
    const SizedBox(height: 8),
    CupertinoButton.filled(
      child: const Text('Change to a contract type'),
      onPressed: () => _openContractOptionPicker(context),
    ),
  ],
)
```

Where `_openContractOptionPicker` is the existing contract-option picker (if it exists; if not, leave the button as a placeholder calling a method named `_openContractOptionPicker` and add the method stub that's documented as "follow-up").

- [ ] **Step 3: Write the test**

```dart
// Pump BookingContractScreen with a booking whose contract_option is
// 'none'. Verify "Verbal agreement — no contract on file" text appears
// and "Change to a contract type" button is present. Pump with
// contract_option = 'default' and verify the new copy is absent.
```

- [ ] **Step 4: Run + commit**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/screens/booking_contract_screen_test.dart 2>&1 | tail -5
```

Expected: pass.

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/screens/booking_contract_screen.dart test/features/bookings/screens/booking_contract_screen_test.dart
git commit -m "feat(mobile/ui): softer verbal-agreement wording on contract screen"
```

---

## Task 16: Event detail "Part of:" backlink

**Files:**
- Modify: `lib/features/events/screens/event_detail_screen.dart`
- Modify: `lib/features/bookings/screens/booking_detail_screen.dart` (pass booking name as a route extra when navigating to an event)
- Create: `test/features/events/screens/event_detail_part_of_row_test.dart`

- [ ] **Step 1: Add a `bookingName` optional prop to `EventDetailScreen`**

```dart
class EventDetailScreen extends ... {
  const EventDetailScreen({
    super.key,
    required this.eventKey,
    this.parentBookingName,
    this.parentBookingId,
    this.parentBandId,
  });

  final String eventKey;
  final String? parentBookingName;
  final int? parentBookingId;
  final int? parentBandId;
  ...
}
```

- [ ] **Step 2: Render the "Part of:" row**

Near the top of the event metadata block:

```dart
if (event.eventableType == 'Bookings' &&
    parentBookingName != null &&
    parentBookingId != null &&
    parentBandId != null)
  GestureDetector(
    onTap: () {
      context.push('/bands/$parentBandId/bookings/$parentBookingId');
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: CupertinoColors.systemGroupedBackground,
      child: Row(
        children: [
          const Icon(CupertinoIcons.bookmark, size: 14,
              color: CupertinoColors.systemBlue),
          const SizedBox(width: 6),
          Text('Part of: ', style: TextStyle(color: CupertinoColors.label.resolveFrom(context))),
          Text(parentBookingName!,
              style: const TextStyle(color: CupertinoColors.systemBlue)),
        ],
      ),
    ),
  ),
```

- [ ] **Step 3: Update booking detail navigation to pass these extras**

When tapping an event card in `booking_detail_screen.dart`, pass `parentBookingName: booking.name, parentBookingId: booking.id, parentBandId: booking.band?.id` via route extras (the router needs an update to forward these). If extras aren't supported by the current GoRouter setup, fall back to URL params or a Riverpod provider that holds the most-recent booking context.

- [ ] **Step 4: Write the test**

```dart
testWidgets('renders "Part of: $bookingName" when parent provided', (tester) async {
  // Pump EventDetailScreen with parentBookingName/Id/BandId set.
  // Verify "Part of: Symphony Hire" appears.
});

testWidgets('absent when parent not provided', (tester) async {
  // Pump without parent extras; verify no "Part of:" text.
});
```

- [ ] **Step 5: Run + commit**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/events/screens/event_detail_part_of_row_test.dart 2>&1 | tail -5
```

Expected: pass.

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/events/screens/event_detail_screen.dart lib/features/bookings/screens/booking_detail_screen.dart test/features/events/screens/event_detail_part_of_row_test.dart
git commit -m "feat(mobile/ui): Part of: backlink on event detail screen"
```

---

## Task 17: Event edit screen — split start/end time

**Files:**
- Modify: `lib/features/events/screens/event_edit_screen.dart`

- [ ] **Step 1: Find the single-time field**

```bash
cd /home/eddie/github/tts_bandmate && grep -nE "time|Time|_time" lib/features/events/screens/event_edit_screen.dart | head -20
```

- [ ] **Step 2: Replace the single-time field with two side-by-side fields**

Replace the existing time controller/field with:

```dart
final _startTimeController = TextEditingController(text: event.startTime ?? '');
final _endTimeController = TextEditingController(text: event.endTime ?? '');
```

And in the UI:

```dart
Row(
  children: [
    Expanded(
      child: CupertinoTextField(
        controller: _startTimeController,
        placeholder: 'Start time (HH:mm)',
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: CupertinoTextField(
        controller: _endTimeController,
        placeholder: 'End time (HH:mm)',
      ),
    ),
  ],
)
```

- [ ] **Step 3: Update the save call**

The submit handler currently calls `eventsRepository.updateEvent(key, {'time': controller.text})`. Replace with:

```dart
await eventsRepository.updateEvent(
  event.key,
  title: _titleController.text,
  date: _dateController.text,
  startTime: _startTimeController.text.isEmpty ? null : _startTimeController.text,
  endTime: _endTimeController.text.isEmpty ? null : _endTimeController.text,
  venueName: _venueNameController.text,
  venueAddress: _venueAddressController.text,
  notes: _notesController.text,
);
```

- [ ] **Step 4: Analyze + commit**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/events/screens/event_edit_screen.dart 2>&1 | tail -5
```

Expected: clean.

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/events/screens/event_edit_screen.dart
git commit -m "feat(mobile/ui): split start/end time fields on event edit screen"
```

---

## Task 18: Booking-detail engagement-summary widget test

**Files:**
- Create: `test/features/bookings/screens/booking_detail_engagement_summary_test.dart`

- [ ] **Step 1: Pump with single-event + multi-event fixtures, assert subtitle**

If extracting the engagement summary into a small widget makes testing easier (recommended), create `lib/features/bookings/widgets/booking_engagement_summary.dart`:

```dart
class BookingEngagementSummary extends StatelessWidget {
  const BookingEngagementSummary({super.key, required this.booking});
  final BookingDetail booking;
  @override
  Widget build(BuildContext context) { ... }  // moved from booking_detail_screen
}
```

- [ ] **Step 2: Test**

```dart
testWidgets('single-event subtitle reads "1 event · …"', (tester) async {
  // Build a BookingDetail with eventCount=1, isMultiEvent=false, venueSummary='Hall', startDate=endDate.
  // Pump BookingEngagementSummary.
  // Expect find.text('1 event · Jun 13 · Hall').
});

testWidgets('multi-event subtitle reads "N events · range · venue"', (tester) async {
  // Build a BookingDetail with eventCount=3, isMultiEvent=true.
  // Expect find.text('3 events · Jun 12–14 · Hall') and find.text('3 events') for the chip.
});

testWidgets('chip absent on single-event bookings', (tester) async {
  // Verify the chip widget is not in the tree for isMultiEvent=false.
});
```

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/screens/booking_detail_engagement_summary_test.dart 2>&1 | tail -5
```

Expected: pass.

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/widgets/booking_engagement_summary.dart test/features/bookings/screens/booking_detail_engagement_summary_test.dart
git commit -m "test(mobile/ui): booking-detail engagement summary widget coverage"
```

---

## Task 19: Full-project green check

**Files:** none modified.

- [ ] **Step 1: Run full test suite**

```bash
cd /home/eddie/github/tts_bandmate && flutter test 2>&1 | tail -15
```

Expected: every test passes.

- [ ] **Step 2: Run full analyze**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze 2>&1 | tail -10
```

Expected: `No issues found!`. The deprecated-method warning on `secure_storage.dart` and the experimental-member warnings on `main.dart` are pre-existing and should be left alone (they aren't from this chunk).

- [ ] **Step 3: No commit — verification gate.**

---

## Task 20: Push + open the bundled mobile PR

**Files:** none modified.

- [ ] **Step 1: Push the branch**

```bash
cd /home/eddie/github/tts_bandmate && git push -u origin feature/bookings-events-mobile
```

- [ ] **Step 2: Open the PR**

```bash
cd /home/eddie/github/tts_bandmate && gh pr create --base main --title "feat(mobile): bookings/events catch-up — data layer + UI rewrite" --body "$(cat <<'EOF'
## Summary

Catches the Flutter mobile app up to the post-bookings/events-redesign backend (web Chunks 1–4 + 7 merged). Two logical chunks landed on this branch:

### Chunk 5 — Mobile data layer (commits prefixed `feat(mobile/data):` / `test(mobile/data):`)

- `BookingSummary` / `BookingDetail` rewritten for the new payload (startDate, endDate, eventCount, isMultiEvent, venueSummary, nested events).
- `EventSummary` / `EventDetail` gain `startTime` / `endTime` / `price`.
- New `EventDraft` create-only DTO.
- `BookingsRepository.createBooking` / `updateBooking` get typed named parameters; new `addEventToBooking` / `removeEventFromBooking` target the booking-event subresource endpoints from web Chunk 3.
- `EventsRepository.updateEvent` accepts typed named parameters.
- `CacheInvalidator.onBookingEventsChanged` for screens that mutate booking events.
- 14 new unit tests (9 model `fromJson` + 5 repository).

### Chunk 6 — Mobile UI (commits prefixed `feat(mobile/ui):` / `feat(mobile):` / `test(mobile):` / `refactor(mobile/ui):`)

- Booking detail rewritten: engagement summary strip (with `[N events]` chip on multi-event), events-first vertical stack with tappable cards + Add event, optional itemization summary.
- Booking form rewritten for multi-event editing with iOS-styled partial-failure save flow: per-row inline error indicators, Save button transforms to "Retry Failed (N)" with destructive tint on partial failure, full-failure banner ("No changes saved — check your connection"), and `CupertinoAlertDialog` navigation guard ("Discard" / "Stay & Retry").
- `BookingSaveOrchestrator` (pure Dart) extracted with 10 exhaustive unit tests covering every partial-failure permutation.
- Bookings list card: new subtitle format + `[N events]` chip on multi-event bookings.
- Event detail: "Part of: $bookingName" backlink row when reached from booking detail.
- Booking contract screen: softened "Verbal agreement — no contract on file" wording for `contract_option == 'none'`.
- Event edit screen: split single `time` into start/end time inputs.
- Utility fixes: `booking_search` matches against any-event-in-range; `booking_month_strip` keys off `startDate`.

## Test plan

- [ ] `flutter test` — full suite green.
- [ ] `flutter analyze` — `No issues found!` across the project.
- [ ] On-device manual smoke: list, detail, form (multi-event), event detail "Part of:" row, contract screen verbal-agreement copy.
- [ ] On-device partial-failure smoke: edit a multi-event booking, toggle airplane mode mid-save, verify the per-row error indicators, Save button transform to "Retry Failed (N)", and navigation guard alert.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Confirm the PR URL**

Expected output: a `https://github.com/eddimull/tts_bandmate/pull/NNN` URL.

---

## Self-review notes

- **Spec coverage:**
  - §1 widget + service extractions → Tasks 3 (orchestrator types), 5 (orchestrator impl), 7 (EventSubFormCard), 8 (banner), 9 (nav guard), 11 (Save button).
  - §2 screen rewrites → Tasks 10 (booking form), 12 (booking detail), 13 (bookings list), 15 (contract), 16 (event detail Part-of:), 17 (event edit start/end time).
  - §3 utility/provider fixes → Task 1.
  - §4 tests — orchestrator (Tasks 4, 6), widgets (7, 8, 9, 11, 14, 18), screens (15, 16), pre-existing fixups (Task 2). Covers every test the spec calls out.
  - §5 commit strategy → ~20 commits prefixed per spec; covered by per-task commit steps.
  - §6 final PR → Task 20.
- **Placeholder scan:** No "TBD" / "implement later" in steps. A few places mention "follow-up" — explicitly scoped (e.g., contract-option picker stub in Task 15) and consistent with the spec's out-of-scope list.
- **Type / signature consistency:**
  - `OperationStatus` sealed class consistent (Tasks 3, 4, 5, 6, 9).
  - `BookingFormSnapshot.eventUpdates` keyed by event `String key` (Task 5 recommendation, used in Task 6 tests).
  - `BookingSaveResult.failureKeys` emits `BOOKING` / `EVT-{id|key}` / `NEW-{localKey}` consistently in Tasks 3, 6, 10.
  - `EventDraft` field names (`startTime`, `endTime`, `venueName`, etc.) match Chunk 5's definition.
- **Sequencing:**
  - Task 1 (utility fixes) and Task 2 (test fixups) come first — they restore most of the green and aren't blocked by the bigger tasks.
  - Orchestrator types (Task 3) → tests (Task 4) → implementation (Task 5) → tests (Task 6) — clean TDD flow for the riskiest piece.
  - Widget extractions (Tasks 7, 8, 9) before the form rewrite (Task 10) that uses them.
  - Detail screen (Task 12) and list screen (Task 13) are independent and could swap, but detail-first matches the user-flow order.
  - Final green-check (Task 19) before the PR (Task 20).
- **Out of scope kept out:** contract-state lock, calendar grouping, Pusher real-time, auth/setlist/media/rehearsals — none referenced in any task.
