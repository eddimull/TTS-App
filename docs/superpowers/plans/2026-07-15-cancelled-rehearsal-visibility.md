# Cancelled Rehearsal Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cancelled rehearsals visibly cancelled everywhere: app event cards, calendar day markers, Google Calendar (red + "Cancelled: " prefix), and the ICS feed (`STATUS:CANCELLED`).

**Architecture:** Two repos. The Laravel backend (TTS) adds `is_cancelled` to the mobile events index and makes the calendar-representation methods (`getGoogleCalendarSummary`/`getGoogleCalendarColor`) cancellation-aware, with `ProcessRehearsalCancelled` re-dispatching the existing `ProcessEventUpdated` sync. The Flutter app (TTS-App) parses the new flag into `EventSummary` and styles `EventCard` + `CalendarEventMarker`.

**Tech Stack:** Laravel 11 (PHPUnit, spatie/icalendar-generator, google/apiclient), Flutter/Dart (Cupertino, flutter_test).

**Spec:** `docs/superpowers/specs/2026-07-15-cancelled-rehearsal-visibility-design.md`

## Global Constraints

- Laravel repo: `/home/eddie/github/TTS`, branch `feat/cancelled-rehearsal-calendar` off `staging`. PRs target `staging` (never master).
- Flutter repo: `/home/eddie/github/tts_bandmate`, branch `feat/cancelled-rehearsal-visibility` (already exists, has the spec commit).
- NEVER run `php`/`artisan`/`composer`/`phpunit` on the host — always `docker compose exec app <cmd>` from `/home/eddie/github/TTS`.
- Flutter commands run on the host from `/home/eddie/github/tts_bandmate`: `flutter test`, `flutter analyze`.
- Google Calendar color IDs: `'5'` = yellow (normal rehearsal), `'11'` = tomato/red (cancelled).
- Cancelled title prefix is exactly `Cancelled: ` (capital C, colon, space) in both Google and ICS output.
- Dart: never use raw `CupertinoColors.secondaryLabel` in a `color:` — use `context.secondaryText` / `context.primaryText` from `package:tts_bandmate/core/theme/context_colors.dart`.
- Tests must not hardcode calendar dates that drift with the clock — use `now()->addDays(n)` (PHP) or fixed ISO strings only where the date is never compared to now (Dart model tests).
- `tests/Feature/CalendarFeedTest.php` is a known parallel-run flake: always run it as a single file (`docker compose exec app php artisan test tests/Feature/CalendarFeedTest.php`).

---

### Task 1: Backend branch + `is_cancelled` in mobile events index

**Repo:** `/home/eddie/github/TTS`

**Files:**
- Modify: `app/Services/Mobile/EventDataService.php:287-300` (`formatForList`)
- Test: `tests/Feature/Api/Mobile/EventsTest.php`

**Interfaces:**
- Produces: events index JSON entries gain `"is_cancelled": bool` — `true` only for rehearsal-sourced events whose `Rehearsal.is_cancelled` is true, `false` for everything else. Flutter Task 5 parses this key.

- [ ] **Step 1: Create the branch**

```bash
cd /home/eddie/github/TTS
git checkout staging && git pull --ff-only
git checkout -b feat/cancelled-rehearsal-calendar
```

- [ ] **Step 2: Write the failing test**

Add to `tests/Feature/Api/Mobile/EventsTest.php` (the file already imports `Rehearsal`, `RehearsalSchedule`, `EventTypes`; helper `createUserWithBandAndEvent()` returns a booking-backed event):

```php
public function test_events_index_includes_is_cancelled_for_rehearsals(): void
{
    ['band' => $band, 'token' => $token] = $this->createUserWithBandAndEvent();

    $schedule = RehearsalSchedule::factory()->weekly()->create(['band_id' => $band->id]);
    $rehearsal = Rehearsal::factory()->create([
        'rehearsal_schedule_id' => $schedule->id,
        'band_id'               => $band->id,
        'is_cancelled'          => true,
    ]);
    Events::factory()->create([
        'eventable_id'   => $rehearsal->id,
        'eventable_type' => 'App\\Models\\Rehearsal',
        'event_type_id'  => EventTypes::factory()->create()->id,
        'date'           => now()->addDays(3)->format('Y-m-d'),
        'start_time'     => '19:00:00',
    ]);

    $response = $this->withToken($token)
        ->withHeaders(['X-Band-ID' => $band->id])
        ->getJson("/api/mobile/bands/{$band->id}/events")
        ->assertOk();

    $events = collect($response->json('events'));

    $rehearsalRow = $events->firstWhere('event_source', 'rehearsal');
    $this->assertNotNull($rehearsalRow, 'rehearsal event missing from index');
    $this->assertTrue($rehearsalRow['is_cancelled']);

    $bookingRow = $events->firstWhere('event_source', 'booking');
    $this->assertNotNull($bookingRow);
    $this->assertFalse($bookingRow['is_cancelled']);
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=test_events_index_includes_is_cancelled_for_rehearsals`
Expected: FAIL — `Undefined array key "is_cancelled"` (or assertTrue fails on null).

- [ ] **Step 4: Implement**

In `app/Services/Mobile/EventDataService.php`, `formatForList()` return array, after the `'status'` line (keep the aligned `=>` style):

```php
'status'          => $event->eventable?->status ?? null,
'is_cancelled'    => $event->eventable_type === 'App\\Models\\Rehearsal'
    && (bool) ($event->eventable?->is_cancelled ?? false),
'roster_status'   => $this->rosterStatusFromRaw($members),
```

(Only the `'is_cancelled'` line is new; the neighbors show placement.)

- [ ] **Step 5: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=test_events_index_includes_is_cancelled_for_rehearsals`
Expected: PASS

- [ ] **Step 6: Run the whole file to check for regressions**

Run: `docker compose exec app php artisan test tests/Feature/Api/Mobile/EventsTest.php`
Expected: all PASS

- [ ] **Step 7: Commit**

```bash
git add app/Services/Mobile/EventDataService.php tests/Feature/Api/Mobile/EventsTest.php
git commit -m "feat(mobile-api): expose is_cancelled on rehearsal events index"
```

---

### Task 2: Cancellation-aware Google Calendar summary + color

**Repo:** `/home/eddie/github/TTS`

**Files:**
- Modify: `app/Models/Events.php:342-352` (`getGoogleCalendarSummary`) and `:382-390` (`getGoogleCalendarColor`)
- Modify: `app/Models/Rehearsal.php:111-116` (`getGoogleCalendarSummary`) and `:170-175` (`getGoogleCalendarColor`)
- Create: `tests/Feature/RehearsalCalendarRepresentationTest.php`

**Interfaces:**
- Consumes: `rehearsals.is_cancelled` boolean (exists; cast on the model).
- Produces: for a cancelled rehearsal, `Events::getGoogleCalendarSummary()` returns `'Cancelled: ' . $this->title` and `Events::getGoogleCalendarColor()` returns `'11'`; same semantics on `Rehearsal`. Task 3's re-sync and Task 4's ICS feed rely on these methods (the ICS feed calls `Events::getGoogleCalendarSummary()` directly, so the prefix flows through for free).

- [ ] **Step 1: Write the failing tests**

Create `tests/Feature/RehearsalCalendarRepresentationTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\Bands;
use App\Models\Events;
use App\Models\EventTypes;
use App\Models\Rehearsal;
use App\Models\RehearsalSchedule;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RehearsalCalendarRepresentationTest extends TestCase
{
    use RefreshDatabase;

    /** @return array{rehearsal: Rehearsal, event: Events} */
    private function makeRehearsalWithEvent(bool $cancelled): array
    {
        $band = Bands::factory()->create();
        $schedule = RehearsalSchedule::factory()->weekly()->create([
            'band_id' => $band->id,
            'name'    => 'Tuesday Practice',
        ]);
        $rehearsal = Rehearsal::factory()->create([
            'rehearsal_schedule_id' => $schedule->id,
            'band_id'               => $band->id,
            'is_cancelled'          => $cancelled,
        ]);
        $event = Events::factory()->create([
            'eventable_id'   => $rehearsal->id,
            'eventable_type' => 'App\\Models\\Rehearsal',
            'event_type_id'  => EventTypes::factory()->create()->id,
            'title'          => 'Tuesday Practice',
            'date'           => now()->addDays(5)->format('Y-m-d'),
            'start_time'     => '19:00:00',
        ]);

        return compact('rehearsal', 'event');
    }

    public function test_cancelled_rehearsal_event_gets_prefixed_summary_and_red_color(): void
    {
        ['rehearsal' => $rehearsal, 'event' => $event] = $this->makeRehearsalWithEvent(true);

        $this->assertSame('Cancelled: Tuesday Practice', $event->getGoogleCalendarSummary());
        $this->assertSame('11', $event->getGoogleCalendarColor());

        $this->assertSame('Cancelled: Tuesday Practice', $rehearsal->getGoogleCalendarSummary());
        $this->assertSame('11', $rehearsal->getGoogleCalendarColor());
    }

    public function test_active_rehearsal_event_keeps_plain_summary_and_yellow_color(): void
    {
        ['rehearsal' => $rehearsal, 'event' => $event] = $this->makeRehearsalWithEvent(false);

        $this->assertSame('Tuesday Practice', $event->getGoogleCalendarSummary());
        $this->assertSame('5', $event->getGoogleCalendarColor());

        $this->assertSame('Tuesday Practice', $rehearsal->getGoogleCalendarSummary());
        $this->assertSame('5', $rehearsal->getGoogleCalendarColor());
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test tests/Feature/RehearsalCalendarRepresentationTest.php`
Expected: `test_cancelled_...` FAILS (`'Tuesday Practice'` !== `'Cancelled: Tuesday Practice'`); `test_active_...` PASSES already.

- [ ] **Step 3: Implement — `app/Models/Events.php`**

Replace `getGoogleCalendarSummary` (lines 342-352):

```php
public function getGoogleCalendarSummary(BandCalendars $bandCalendar = null): string|null
{
    if ($this->isCancelledRehearsal()) {
        return 'Cancelled: ' . $this->title;
    }

    if ($bandCalendar?->type === 'public') {
        return $this->title;
    }

    if ($this->eventable_type === 'App\\Models\\Bookings' && $this->eventable) {
        return $this->title . ' (' . ucfirst($this->eventable->status) . ')';
    }
    return $this->title;
}

/**
 * True when this event's eventable is a rehearsal that has been cancelled.
 */
private function isCancelledRehearsal(): bool
{
    return $this->eventable_type === 'App\\Models\\Rehearsal'
        && (bool) ($this->eventable?->is_cancelled ?? false);
}
```

Replace `getGoogleCalendarColor` (lines 382-390):

```php
public function getGoogleCalendarColor(): string|null
{
    if ($this->eventable_type === 'App\\Models\\Rehearsal') {
        // Red for cancelled rehearsals, yellow otherwise.
        return $this->isCancelledRehearsal() ? '11' : '5';
    }

    return null;
}
```

- [ ] **Step 4: Implement — `app/Models/Rehearsal.php`**

Replace `getGoogleCalendarSummary` (lines 111-116):

```php
public function getGoogleCalendarSummary(BandCalendars $bandCalendar = null): string|null
{
    // Get the first event or use schedule name
    $event = $this->events()->first();
    $title = $event ? $event->title : ($this->rehearsalSchedule->name ?? 'Rehearsal');

    return $this->is_cancelled ? 'Cancelled: ' . $title : $title;
}
```

Replace `getGoogleCalendarColor` (lines 170-175):

```php
public function getGoogleCalendarColor(): string|null
{
    // Google Calendar color IDs: 1-11. Red for cancelled, yellow otherwise.
    return $this->is_cancelled ? '11' : '5';
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `docker compose exec app php artisan test tests/Feature/RehearsalCalendarRepresentationTest.php`
Expected: both PASS

- [ ] **Step 6: Commit**

```bash
git add app/Models/Events.php app/Models/Rehearsal.php tests/Feature/RehearsalCalendarRepresentationTest.php
git commit -m "feat(calendar): cancelled rehearsals render red with Cancelled prefix"
```

---

### Task 3: Re-sync Google Calendar on cancel/restore

**Repo:** `/home/eddie/github/TTS`

**Files:**
- Modify: `app/Jobs/ProcessRehearsalCancelled.php:33-36`
- Test: `tests/Feature/ProcessRehearsalCancelledTest.php`

**Interfaces:**
- Consumes: `ProcessEventUpdated::dispatch(Events $event, array $originalData)` — existing job; its `handle()` calls `writeToGoogleCalendar()` which re-renders summary/color from Task 2's methods. Passing `['status' => $event->status]` keeps its status-change notification a no-op.
- Produces: cancelling or restoring a rehearsal queues one `ProcessEventUpdated` for the backing `Events` row. `ProcessRehearsalCancelled` fires for BOTH directions (`isCancelled` bool param), so restore re-syncs too.

- [ ] **Step 1: Write the failing tests**

Add to `tests/Feature/ProcessRehearsalCancelledTest.php` (uses existing helper `setUpBandWithRehearsal()`; add `use App\Jobs\ProcessEventUpdated;` to the imports):

```php
public function test_dispatches_calendar_resync_for_backing_event(): void
{
    Notification::fake();
    Queue::fake();
    ['rehearsal' => $rehearsal, 'actor' => $actor] = $this->setUpBandWithRehearsal();

    (new ProcessRehearsalCancelled($rehearsal, $actor->id, true, 'key-cal-1'))->handle();

    Queue::assertPushed(ProcessEventUpdated::class);
}

public function test_no_calendar_resync_when_rehearsal_has_no_backing_event(): void
{
    Notification::fake();
    Queue::fake();

    $actor = User::factory()->create();
    $band  = Bands::factory()->create();
    $band->owners()->create(['user_id' => $actor->id]);
    $schedule = RehearsalSchedule::factory()->weekly()->create([
        'band_id' => $band->id,
        'name'    => 'No Event Practice',
    ]);
    $rehearsal = Rehearsal::factory()->create([
        'rehearsal_schedule_id' => $schedule->id,
        'band_id'               => $band->id,
    ]);

    (new ProcessRehearsalCancelled($rehearsal, $actor->id, true, 'key-cal-2'))->handle();

    Queue::assertNotPushed(ProcessEventUpdated::class);
}
```

- [ ] **Step 2: Run tests to verify the first fails**

Run: `docker compose exec app php artisan test --filter=calendar_resync`
Expected: `test_dispatches_calendar_resync_for_backing_event` FAILS (`The expected [App\Jobs\ProcessEventUpdated] job was not pushed`); the no-backing-event test passes vacuously.

- [ ] **Step 3: Implement**

In `app/Jobs/ProcessRehearsalCancelled.php`, `handle()`, directly after the `$event = $this->rehearsal->events->first();` block (line 33-36):

```php
$event = $this->rehearsal->events->first();
$date = $event
    ? (is_string($event->date) ? $event->date : $event->date->format('Y-m-d'))
    : null;

// Re-render the Google Calendar entry so the cancelled (or restored)
// state shows up: red + "Cancelled: " prefix comes from the model's
// calendar representation methods. Current status is passed as the
// original so the job's status-change notification stays quiet.
if ($event) {
    ProcessEventUpdated::dispatch($event, ['status' => $event->status]);
}
```

(The `$event`/`$date` lines already exist — only the comment and `if` block are new. `ProcessEventUpdated` is in the same `App\Jobs` namespace; no import needed.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=calendar_resync`
Expected: both PASS

- [ ] **Step 5: Run the whole file**

Run: `docker compose exec app php artisan test tests/Feature/ProcessRehearsalCancelledTest.php`
Expected: all PASS

- [ ] **Step 6: Commit**

```bash
git add app/Jobs/ProcessRehearsalCancelled.php tests/Feature/ProcessRehearsalCancelledTest.php
git commit -m "feat(calendar): re-sync Google event when rehearsal is cancelled or restored"
```

---

### Task 4: ICS feed marks cancelled rehearsals

**Repo:** `/home/eddie/github/TTS`

**Files:**
- Modify: `app/Http/Controllers/CalendarFeedController.php:124-126` (`buildEvent`) + import block
- Test: `tests/Feature/CalendarFeedTest.php`

**Interfaces:**
- Consumes: `Events::getGoogleCalendarSummary()` (Task 2) — the feed already calls it at line 126, so the `Cancelled: ` prefix appears without changes; and `Spatie\IcalendarGenerator\Enums\EventStatus::Cancelled` (enum case, value `'CANCELLED'`).
- Produces: VEVENTs for cancelled rehearsals carry `STATUS:CANCELLED`.

- [ ] **Step 1: Write the failing test**

Add to `tests/Feature/CalendarFeedTest.php` (add `use App\Models\EventTypes;`, `use App\Models\Rehearsal;`, `use App\Models\RehearsalSchedule;` to the imports; `$this->band`/`$this->owner` come from `setUp()`):

```php
public function test_feed_marks_cancelled_rehearsals(): void
{
    $schedule = RehearsalSchedule::factory()->weekly()->create([
        'band_id' => $this->band->id,
        'name'    => 'Tuesday Practice',
    ]);
    $rehearsal = Rehearsal::factory()->create([
        'rehearsal_schedule_id' => $schedule->id,
        'band_id'               => $this->band->id,
        'is_cancelled'          => true,
    ]);
    Events::factory()->create([
        'eventable_id'   => $rehearsal->id,
        'eventable_type' => 'App\\Models\\Rehearsal',
        'event_type_id'  => EventTypes::factory()->create()->id,
        'title'          => 'Tuesday Practice',
        'date'           => now()->addDays(4)->toDateString(),
        'start_time'     => '19:00',
        'end_time'       => '21:00',
    ]);

    $token = $this->owner->getCalendarToken();
    $body  = $this->get('/calendar/' . $token . '.ics')->assertOk()->getContent();

    $this->assertStringContainsString('STATUS:CANCELLED', $body);
    $this->assertStringContainsString('Cancelled: Tuesday Practice', $body);
}
```

- [ ] **Step 2: Run the test file to verify the new test fails**

Run: `docker compose exec app php artisan test tests/Feature/CalendarFeedTest.php`
Expected: `test_feed_marks_cancelled_rehearsals` FAILS on `STATUS:CANCELLED` missing (the `Cancelled: Tuesday Practice` assertion may already pass thanks to Task 2). If it instead fails with the rehearsal event missing from the feed entirely, the entitlement query excludes it — stop and report rather than forcing the assertion.

- [ ] **Step 3: Implement**

In `app/Http/Controllers/CalendarFeedController.php`, add to the import block:

```php
use Spatie\IcalendarGenerator\Enums\EventStatus;
```

In `buildEvent()`, right after the `->name(...)` chain (line 124-126):

```php
$calendarEvent = CalendarEvent::create()
    ->uniqueIdentifier('event-' . $event->id . '@thatstheticket')
    ->name($event->getGoogleCalendarSummary() ?? ($event->title ?: 'Event'));

// Cancelled rehearsals stay in the feed but flagged, so subscribed
// clients strike them through instead of silently dropping them.
if ($event->eventable_type === 'App\\Models\\Rehearsal'
    && ($event->eventable?->is_cancelled ?? false)) {
    $calendarEvent->status(EventStatus::Cancelled);
}
```

(The `CalendarEvent::create()` chain already exists — only the comment and `if` block are new.)

- [ ] **Step 4: Run the file to verify it passes**

Run: `docker compose exec app php artisan test tests/Feature/CalendarFeedTest.php`
Expected: all PASS (single-file run — this file flakes under parallel execution).

- [ ] **Step 5: Commit**

```bash
git add app/Http/Controllers/CalendarFeedController.php tests/Feature/CalendarFeedTest.php
git commit -m "feat(calendar): ICS feed emits STATUS:CANCELLED for cancelled rehearsals"
```

---

### Task 5: `EventSummary.isCancelled` (Flutter)

**Repo:** `/home/eddie/github/tts_bandmate` (branch `feat/cancelled-rehearsal-visibility`, already checked out)

**Files:**
- Modify: `lib/features/events/data/models/event_summary.dart`
- Test: `test/features/events/data/event_summary_test.dart`

**Interfaces:**
- Consumes: `is_cancelled` JSON key from Task 1 (may be absent on old payloads).
- Produces: `EventSummary.isCancelled` — non-nullable `bool`, defaults `false`. Tasks 6 and 7 read it.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/events/data/event_summary_test.dart` inside `main()`:

```dart
test('parses is_cancelled', () {
  final e = EventSummary.fromJson({...baseJson(), 'is_cancelled': true});
  expect(e.isCancelled, isTrue);
});

test('defaults is_cancelled to false on legacy payloads', () {
  final e = EventSummary.fromJson(baseJson());
  expect(e.isCancelled, isFalse);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/events/data/event_summary_test.dart`
Expected: FAIL — `The getter 'isCancelled' isn't defined`.

- [ ] **Step 3: Implement**

In `lib/features/events/data/models/event_summary.dart`:

Constructor (after `this.unreadCommentCount = 0,`):

```dart
    this.unreadCommentCount = 0,
    this.isCancelled = false,
```

Field declarations (after the `unreadCommentCount` field + doc comment):

```dart
  /// True when this event is a cancelled rehearsal. False on legacy
  /// payloads that don't send is_cancelled.
  final bool isCancelled;
```

`fromJson` (after the `unreadCommentCount:` line):

```dart
      unreadCommentCount: (json['unread_comment_count'] as num?)?.toInt() ?? 0,
      isCancelled: (json['is_cancelled'] as bool?) ?? false,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/events/data/event_summary_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/events/data/models/event_summary.dart test/features/events/data/event_summary_test.dart
git commit -m "feat(events): parse is_cancelled into EventSummary"
```

---

### Task 6: `EventCard` cancelled styling (Flutter)

**Files:**
- Modify: `lib/features/dashboard/widgets/event_card.dart`
- Test: `test/features/dashboard/event_card_test.dart`

**Interfaces:**
- Consumes: `EventSummary.isCancelled` (Task 5).
- Produces: cancelled events render red `CupertinoIcons.xmark_circle` instead of the type icon, strikethrough secondary-colored title, a red 12pt `Cancelled` label under the date, and a neutral gray icon-column background instead of rehearsal blue.

- [ ] **Step 1: Write the failing tests**

In `test/features/dashboard/event_card_test.dart`, extend the helper and add tests:

```dart
EventSummary event({int unread = 0, bool cancelled = false}) => EventSummary(
      key: 'evt-1',
      title: 'Tuesday Rehearsal',
      date: '2026-07-20',
      eventSource: 'rehearsal',
      unreadCommentCount: unread,
      isCancelled: cancelled,
    );
```

```dart
testWidgets('cancelled rehearsal shows red X, strikethrough, and label',
    (tester) async {
  await tester.pumpWidget(CupertinoApp(
    home: CupertinoPageScaffold(child: EventCard(event: event(cancelled: true))),
  ));

  expect(find.byIcon(CupertinoIcons.xmark_circle), findsOneWidget);
  expect(find.byIcon(CupertinoIcons.music_mic), findsNothing);
  expect(find.text('Cancelled'), findsOneWidget);

  final title = tester.widget<Text>(find.text('Tuesday Rehearsal'));
  expect(title.style?.decoration, TextDecoration.lineThrough);
});

testWidgets('active rehearsal keeps mic icon and no cancelled label',
    (tester) async {
  await tester.pumpWidget(CupertinoApp(
    home: CupertinoPageScaffold(child: EventCard(event: event())),
  ));

  expect(find.byIcon(CupertinoIcons.music_mic), findsOneWidget);
  expect(find.byIcon(CupertinoIcons.xmark_circle), findsNothing);
  expect(find.text('Cancelled'), findsNothing);

  final title = tester.widget<Text>(find.text('Tuesday Rehearsal'));
  expect(title.style?.decoration, isNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/dashboard/event_card_test.dart`
Expected: the cancelled test FAILS (`xmark_circle` not found); the other three pass.

- [ ] **Step 3: Implement**

In `lib/features/dashboard/widgets/event_card.dart`:

`build()` — background tint (replace lines 17-20):

```dart
    final isRehearsal = event.isRehearsal;
    final bgColor = isRehearsal && !event.isCancelled
        ? CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.08)
        : CupertinoColors.systemGrey6.resolveFrom(context);
```

Title `Text` (replace the style at lines 60-65):

```dart
                          child: Text(
                            event.title,
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold,
                                color: event.isCancelled
                                    ? context.secondaryText
                                    : context.primaryText,
                                decoration: event.isCancelled
                                    ? TextDecoration.lineThrough
                                    : null),
                          ),
```

Cancelled label — after the date `Text` (the `_formatDate` block ending line 83), before the band chip:

```dart
                    if (event.isCancelled) ...[
                      const SizedBox(height: 2),
                      const Text(
                        'Cancelled',
                        style: TextStyle(
                            fontSize: 12, color: CupertinoColors.systemRed),
                      ),
                    ],
```

`_EventTypeIcon.build()` — cancelled branch first (before the `gigIconPath` check):

```dart
  @override
  Widget build(BuildContext context) {
    if (event.isCancelled) {
      return Icon(CupertinoIcons.xmark_circle,
          size: 24, color: CupertinoColors.systemRed.resolveFrom(context));
    }
    final iconPath = event.gigIconPath;
    if (iconPath != null) {
      return Image.asset(iconPath, width: 40, height: 40, fit: BoxFit.contain);
    }
    return Icon(CupertinoIcons.music_mic,
        size: 24, color: context.secondaryText);
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/dashboard/event_card_test.dart`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/widgets/event_card.dart test/features/dashboard/event_card_test.dart
git commit -m "feat(dashboard): cancelled styling on event cards"
```

---

### Task 7: Calendar day marker cancelled ring (Flutter)

**Files:**
- Modify: `lib/features/dashboard/widgets/calendar_event_marker.dart:143-150` (`_ringSpec`) and `:182-199` (`_semanticsLabel`)
- Create: `test/features/dashboard/calendar_event_marker_test.dart`

**Interfaces:**
- Consumes: `EventSummary.isCancelled` (Task 5).
- Produces: cancelled rehearsal markers get the same treatment as cancelled bookings — solid red ring, avatar faded to 0.4 opacity — and a semantics label ending in `, cancelled`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/dashboard/calendar_event_marker_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/widgets/calendar_event_marker.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

void main() {
  EventSummary rehearsal({bool cancelled = false}) => EventSummary(
        key: 'evt-1',
        title: 'Tuesday Rehearsal',
        date: '2026-07-20',
        eventSource: 'rehearsal',
        isCancelled: cancelled,
      );

  Future<void> pump(WidgetTester tester, EventSummary event) => tester.pumpWidget(
        CupertinoApp(
          home: Center(child: CalendarEventMarker(event: event)),
        ),
      );

  testWidgets('cancelled rehearsal marker fades avatar and announces cancelled',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, rehearsal(cancelled: true));

    expect(find.bySemanticsLabel('Event rehearsal, cancelled'), findsOneWidget);

    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 0.4);

    handle.dispose();
  });

  testWidgets('active rehearsal marker keeps full opacity and plain label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, rehearsal());

    expect(find.bySemanticsLabel('Event rehearsal'), findsOneWidget);

    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 1.0);

    handle.dispose();
  });
}
```

(`_semanticsLabel` uses `e.band?.name ?? 'Event'`; these events carry no band, hence the `Event ` prefix.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/dashboard/calendar_event_marker_test.dart`
Expected: cancelled test FAILS (label `Event rehearsal` found instead of `Event rehearsal, cancelled`; opacity 1.0 not 0.4). Active test passes.

- [ ] **Step 3: Implement**

In `lib/features/dashboard/widgets/calendar_event_marker.dart`, `_ringSpec` rehearsal branch (replace lines 144-150):

```dart
  if (e.eventSource == 'rehearsal' || e.eventSource == 'rehearsal_schedule') {
    if (e.isCancelled) {
      return _RingSpec(
        color: CupertinoColors.systemRed.resolveFrom(ctx),
        dashed: false,
        fadeAvatar: true,
      );
    }
    return _RingSpec(
      color: CupertinoColors.systemBlue.resolveFrom(ctx),
      dashed: false,
      fadeAvatar: false,
    );
  }
```

`_semanticsLabel` — before the final `return '$bandName $type';`:

```dart
  if ((e.eventSource == 'rehearsal' || e.eventSource == 'rehearsal_schedule') &&
      e.isCancelled) {
    return '$bandName $type, cancelled';
  }
  return '$bandName $type';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/dashboard/calendar_event_marker_test.dart`
Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/widgets/calendar_event_marker.dart test/features/dashboard/calendar_event_marker_test.dart
git commit -m "feat(dashboard): red faded marker for cancelled rehearsals"
```

---

### Task 8: Full verification, both repos

**Files:** none (verification only)

- [ ] **Step 1: Flutter analyze + full test suite**

```bash
cd /home/eddie/github/tts_bandmate
flutter analyze
flutter test
```

Expected: analyze clean (no new issues), all tests pass.

- [ ] **Step 2: Laravel targeted suites**

```bash
cd /home/eddie/github/TTS
docker compose exec app php artisan test tests/Feature/Api/Mobile/EventsTest.php tests/Feature/ProcessRehearsalCancelledTest.php tests/Feature/RehearsalCalendarRepresentationTest.php
docker compose exec app php artisan test tests/Feature/CalendarFeedTest.php
```

Expected: all pass. (CalendarFeedTest runs alone — parallel flake.)

- [ ] **Step 3: On-device / PR handoff**

Implementation done. Next steps outside this plan: use superpowers:finishing-a-development-branch — TTS PR base `staging` (auto-deploys on merge), Flutter PR base `main`; wait for Copilot review on both; on-device verification of the dashboard/events cards via the run-on-device skill.
