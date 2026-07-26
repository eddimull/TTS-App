# Calendar Forward Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the mobile calendar browse rehearsals and bookings arbitrarily far forward (5-year cap) via lazy windowed fetching, and make the Rehearsals tab show recurrence rules plus merged virtual+real occurrences with load-more.

**Architecture:** Mirror the existing `loadOlder` back-fetch with a `loadNewer` forward-fetch. The backend `UserEventsService::getEvents($after, $before)` already generates virtual rehearsals correctly for any bounded window — new endpoints just expose bounded windows. All backend changes are opt-in via query params so old app versions see unchanged responses.

**Tech Stack:** Laravel 10 (TTS repo, Sanctum, PHPUnit via Docker), Flutter/Dart (Riverpod v2 AsyncNotifier, Dio, table_calendar).

**Spec:** `docs/superpowers/specs/2026-07-25-calendar-forward-windows-design.md`

## Global Constraints

- TTS repo (`/home/eddie/github/TTS`): branch `feat/calendar-forward-windows`, PR base `staging`. NEVER run php/artisan/composer on the host — always `docker compose exec app …` from the repo root.
- App repo (`/home/eddie/github/tts_bandmate`): branch `feat/calendar-forward-windows` (exists), PR base `main`.
- Date query params are `yyyy-MM-dd` strings. Window semantics: `after_date` inclusive, `before_date` exclusive (matches existing `>=` / `<` predicates). Client-side merge dedups by id (and by `key` for null-id events) so a stray inclusive boundary day can never duplicate.
- There is NO `hasReachedEnd` for forward fetching — an empty window proves nothing. The browse cap is the calendar's `lastDay` (now + 5 years).
- No time-bomb tests: PHP fixtures use `now()`-relative dates; Dart assertions compute expectations relative to `DateTime.now()`.
- Backend tests: `docker compose exec app php artisan test --filter=<Name>`. Flutter: `flutter test <path>`, `flutter analyze` before finishing.
- Do not assert on `event_type_id` in backend tests — `RehearsalScheduleService::getRehearsalEventTypeId()` caches in a `static` local across tests.

---

### Task 1: Backend — `loadNewer` dashboard endpoint

**Files:**
- Modify: `app/Http/Controllers/Api/Mobile/DashboardController.php` (add method after `loadOlder`, ~line 90)
- Modify: `routes/api.php` (after line 94, the `load-older` route)
- Test: `tests/Feature/Api/Mobile/DashboardTest.php`

**Interfaces:**
- Produces: `GET /api/mobile/dashboard/load-newer?after_date=Y-m-d&before_date=Y-m-d` → `{"events": [...]}` — same event shape as `load-older`. Missing/blank params → `{"events": []}` (mirrors `loadOlder` leniency). Requires `auth:sanctum`.

- [ ] **Step 1: Create the TTS branch**

```bash
cd /home/eddie/github/TTS
git fetch origin staging
git checkout -b feat/calendar-forward-windows origin/staging
```

- [ ] **Step 2: Write the failing tests**

Append to `tests/Feature/Api/Mobile/DashboardTest.php` (inside the class; imports for `RehearsalSchedule` needed: add `use App\Models\RehearsalSchedule;` to the existing use block):

```php
    public function test_load_newer_returns_virtual_rehearsals_inside_the_window(): void
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        // Weekly schedule (factory pins day_of_week = wednesday, active = true).
        RehearsalSchedule::factory()->weekly()->create(['band_id' => $band->id]);

        $token = $user->createToken('test-device')->plainTextToken;

        $after  = now()->addDays(120)->toDateString();
        $before = now()->addDays(150)->toDateString();

        $response = $this->withToken($token)
            ->getJson("/api/mobile/dashboard/load-newer?after_date={$after}&before_date={$before}");

        $response->assertOk()->assertJsonStructure(['events']);

        $events = collect($response->json('events'));
        $this->assertGreaterThanOrEqual(4, $events->count(),
            'a weekly schedule must produce ~4 virtual rehearsals in a 30-day window');
        $events->each(function ($e) use ($after, $before) {
            $this->assertGreaterThanOrEqual($after, $e['date']);
            $this->assertLessThan($before, $e['date']);
        });
    }

    public function test_load_newer_excludes_events_outside_the_window(): void
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $eventType = EventTypes::factory()->create();
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        // 3 years out — far beyond the requested window.
        Events::factory()->create([
            'eventable_id'   => $booking->id,
            'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id'  => $eventType->id,
            'date'           => now()->addYears(3)->format('Y-m-d'),
        ]);

        $token = $user->createToken('test-device')->plainTextToken;

        $after  = now()->addDays(90)->toDateString();
        $before = now()->addDays(120)->toDateString();

        $response = $this->withToken($token)
            ->getJson("/api/mobile/dashboard/load-newer?after_date={$after}&before_date={$before}");

        $response->assertOk();
        $this->assertCount(0, $response->json('events'));

        // The same booking IS returned when the window reaches it.
        $after2  = now()->addYears(3)->subDays(15)->toDateString();
        $before2 = now()->addYears(3)->addDays(15)->toDateString();
        $reach = $this->withToken($token)
            ->getJson("/api/mobile/dashboard/load-newer?after_date={$after2}&before_date={$before2}");
        $this->assertCount(1, $reach->json('events'));
    }

    public function test_load_newer_returns_empty_when_params_missing(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('test-device')->plainTextToken;

        $response = $this->withToken($token)->getJson('/api/mobile/dashboard/load-newer');

        $response->assertOk();
        $this->assertSame([], $response->json('events'));
    }

    public function test_load_newer_requires_authentication(): void
    {
        $this->getJson('/api/mobile/dashboard/load-newer?after_date=2026-01-01&before_date=2026-02-01')
            ->assertUnauthorized();
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=DashboardTest`
Expected: the four new tests FAIL with 404 (route not defined); existing tests PASS.

- [ ] **Step 4: Implement the endpoint**

In `app/Http/Controllers/Api/Mobile/DashboardController.php`, after `loadOlder`:

```php
    /**
     * Load a future window of events for the calendar's lazy forward-fetch.
     * Window: [after_date, before_date). Virtual rehearsals are generated for
     * the window by UserEventsService. There is deliberately no "reached end"
     * signal — an empty window proves nothing about later events.
     */
    public function loadNewer(Request $request): JsonResponse
    {
        $afterDateInput  = $request->input('after_date');
        $beforeDateInput = $request->input('before_date');

        if (! $afterDateInput || ! $beforeDateInput) {
            return response()->json(['events' => []]);
        }

        Auth::setUser($request->user());

        $afterDate  = Carbon::parse($afterDateInput);
        $beforeDate = Carbon::parse($beforeDateInput);

        $events = (new UserEventsService())->getEvents($afterDate, $beforeDate);

        $collection = $events instanceof \Illuminate\Support\Collection
            ? $events
            : collect($events);

        $unreadByKey = $this->topicUnread->unreadCountsForConversables(
            $request->user(),
            $this->formatter->conversablePairs($collection),
        );

        return response()->json([
            'events' => $this->formatter->formatEvents($collection, $unreadByKey),
        ]);
    }
```

In `routes/api.php`, directly under the `load-older` route (line ~94):

```php
        Route::get('/dashboard/load-newer', [App\Http\Controllers\Api\Mobile\DashboardController::class, 'loadNewer'])->name('mobile.dashboard.load-newer');
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=DashboardTest`
Expected: ALL PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Http/Controllers/Api/Mobile/DashboardController.php routes/api.php tests/Feature/Api/Mobile/DashboardTest.php
git commit -m "feat(mobile): add dashboard load-newer endpoint for forward calendar windows

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Backend — opt-in `to` bound on the initial dashboard payload

**Files:**
- Modify: `app/Http/Controllers/Api/Mobile/DashboardController.php:37` (the `index` method)
- Test: `tests/Feature/Api/Mobile/DashboardTest.php`

**Interfaces:**
- Produces: `GET /api/mobile/dashboard?to=Y-m-d` — when `to` is present it is passed as `beforeDate` (exclusive) to `getEvents`; when absent, behavior is byte-identical to today (unbounded real events, 12-week virtuals).

- [ ] **Step 1: Write the failing tests**

Append to `tests/Feature/Api/Mobile/DashboardTest.php`:

```php
    public function test_dashboard_without_to_still_returns_far_future_events(): void
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $eventType = EventTypes::factory()->create();
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        Events::factory()->create([
            'eventable_id'   => $booking->id,
            'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id'  => $eventType->id,
            'date'           => now()->addYears(3)->format('Y-m-d'),
        ]);

        $token = $user->createToken('test-device')->plainTextToken;

        // Old-client behavior preserved: no `to` → far-future booking included.
        $response = $this->withToken($token)->getJson('/api/mobile/dashboard');
        $response->assertOk();
        $this->assertCount(1, $response->json('events'));
    }

    public function test_dashboard_with_to_bounds_the_payload(): void
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $eventType = EventTypes::factory()->create();
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        Events::factory()->create([
            'eventable_id'   => $booking->id,
            'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id'  => $eventType->id,
            'date'           => now()->addYears(3)->format('Y-m-d'),
        ]);
        // And one inside the bound.
        $near = Bookings::factory()->create(['band_id' => $band->id]);
        Events::factory()->create([
            'eventable_id'   => $near->id,
            'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id'  => $eventType->id,
            'date'           => now()->addDays(10)->format('Y-m-d'),
        ]);

        $token = $user->createToken('test-device')->plainTextToken;
        $to = now()->addDays(90)->toDateString();

        $response = $this->withToken($token)->getJson("/api/mobile/dashboard?to={$to}");
        $response->assertOk();
        $this->assertCount(1, $response->json('events'),
            'only the near booking should survive the to= bound');
    }
```

- [ ] **Step 2: Run tests to verify the new bound test fails**

Run: `docker compose exec app php artisan test --filter=DashboardTest`
Expected: `test_dashboard_with_to_bounds_the_payload` FAILS (2 events returned); `test_dashboard_without_to_...` PASSES (documents existing behavior).

- [ ] **Step 3: Implement**

In `DashboardController::index`, replace:

```php
        $events         = (new UserEventsService())->getEvents($afterDate);
```

with:

```php
        // Opt-in forward bound: new app versions send ?to= and lazy-fetch
        // beyond it via load-newer. Absent `to` preserves old-client behavior.
        $beforeDate = $request->filled('to')
            ? Carbon::parse($request->input('to'))
            : null;

        $events         = (new UserEventsService())->getEvents($afterDate, $beforeDate);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=DashboardTest`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add app/Http/Controllers/Api/Mobile/DashboardController.php tests/Feature/Api/Mobile/DashboardTest.php
git commit -m "feat(mobile): support opt-in to= forward bound on dashboard payload

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Backend — recurrence label formatter

**Files:**
- Create: `app/Services/Mobile/RecurrenceLabelService.php`
- Test: `tests/Unit/Services/Mobile/RecurrenceLabelServiceTest.php` (create; `tests/Unit` exists)

**Interfaces:**
- Produces: `RecurrenceLabelService::format(RehearsalSchedule $schedule): string` — pure function of the schedule's recurrence columns; used by Task 4.

- [ ] **Step 1: Write the failing tests**

Create `tests/Unit/Services/Mobile/RecurrenceLabelServiceTest.php`:

```php
<?php

namespace Tests\Unit\Services\Mobile;

use App\Models\RehearsalSchedule;
use App\Services\Mobile\RecurrenceLabelService;
use PHPUnit\Framework\TestCase;

class RecurrenceLabelServiceTest extends TestCase
{
    private RecurrenceLabelService $service;

    protected function setUp(): void
    {
        parent::setUp();
        $this->service = new RecurrenceLabelService();
    }

    /** Build an unsaved model — no DB needed for a pure formatter. */
    private function schedule(array $attrs): RehearsalSchedule
    {
        return new RehearsalSchedule($attrs);
    }

    public function test_daily(): void
    {
        $this->assertSame('Every day at 7:00 PM', $this->service->format(
            $this->schedule(['frequency' => 'daily', 'default_time' => '19:00:00'])));
    }

    public function test_weekday(): void
    {
        $this->assertSame('Weekdays at 6:30 PM', $this->service->format(
            $this->schedule(['frequency' => 'weekday', 'default_time' => '18:30:00'])));
    }

    public function test_weekly_single_day_from_selected_days(): void
    {
        $this->assertSame('Every Tuesday at 7:00 PM', $this->service->format(
            $this->schedule([
                'frequency' => 'weekly',
                'selected_days' => ['tuesday'],
                'default_time' => '19:00:00',
            ])));
    }

    public function test_weekly_multiple_days(): void
    {
        $this->assertSame('Every Tuesday & Thursday at 7:00 PM', $this->service->format(
            $this->schedule([
                'frequency' => 'weekly',
                'selected_days' => ['tuesday', 'thursday'],
                'default_time' => '19:00:00',
            ])));
    }

    public function test_weekly_legacy_day_of_week_fallback(): void
    {
        $this->assertSame('Every Wednesday', $this->service->format(
            $this->schedule([
                'frequency' => 'weekly',
                'day_of_week' => 'wednesday',
                'default_time' => null,
            ])));
    }

    public function test_weekly_with_no_days_falls_back_to_generic(): void
    {
        $this->assertSame('Weekly', $this->service->format(
            $this->schedule(['frequency' => 'weekly'])));
    }

    public function test_monthly_day_of_month(): void
    {
        $this->assertSame('Monthly on the 15th at 7:00 PM', $this->service->format(
            $this->schedule([
                'frequency' => 'monthly',
                'monthly_pattern' => 'day_of_month',
                'day_of_month' => 15,
                'default_time' => '19:00:00',
            ])));
    }

    public function test_monthly_pattern_weekday(): void
    {
        $this->assertSame('First Monday of each month at 7:00 PM', $this->service->format(
            $this->schedule([
                'frequency' => 'monthly',
                'monthly_pattern' => 'first',
                'monthly_weekday' => 'monday',
                'default_time' => '19:00:00',
            ])));
    }

    public function test_monthly_without_pattern_is_generic(): void
    {
        $this->assertSame('Monthly', $this->service->format(
            $this->schedule(['frequency' => 'monthly'])));
    }

    public function test_custom(): void
    {
        $this->assertSame('Custom schedule', $this->service->format(
            $this->schedule(['frequency' => 'custom', 'default_time' => '19:00:00'])));
    }

    public function test_ordinals(): void
    {
        foreach ([1 => '1st', 2 => '2nd', 3 => '3rd', 4 => '4th', 11 => '11th', 21 => '21st', 22 => '22nd', 23 => '23rd'] as $day => $expected) {
            $this->assertStringContainsString("Monthly on the {$expected}", $this->service->format(
                $this->schedule([
                    'frequency' => 'monthly',
                    'monthly_pattern' => 'day_of_month',
                    'day_of_month' => $day,
                ])));
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=RecurrenceLabelServiceTest`
Expected: FAIL — class `RecurrenceLabelService` not found.

- [ ] **Step 3: Implement**

Create `app/Services/Mobile/RecurrenceLabelService.php`:

```php
<?php

namespace App\Services\Mobile;

use App\Models\RehearsalSchedule;
use Illuminate\Support\Carbon;

/**
 * Formats a rehearsal schedule's recurrence columns into a human-readable
 * label, e.g. "Every Tuesday at 7:00 PM". Pure; no DB access.
 */
class RecurrenceLabelService
{
    public function format(RehearsalSchedule $schedule): string
    {
        $time = $this->timeSuffix($schedule);

        return match ($schedule->frequency) {
            'daily'   => 'Every day' . $time,
            'weekday' => 'Weekdays' . $time,
            'weekly'  => $this->weeklyLabel($schedule, $time),
            'monthly' => $this->monthlyLabel($schedule, $time),
            default   => 'Custom schedule',
        };
    }

    private function timeSuffix(RehearsalSchedule $schedule): string
    {
        if (! $schedule->default_time) {
            return '';
        }

        return ' at ' . Carbon::parse($schedule->default_time)->format('g:i A');
    }

    private function weeklyLabel(RehearsalSchedule $schedule, string $time): string
    {
        $days = $schedule->selected_days
            ?: ($schedule->day_of_week ? [$schedule->day_of_week] : []);

        if (empty($days)) {
            return 'Weekly' . $time;
        }

        $names = array_map(fn ($d) => ucfirst(strtolower($d)), $days);

        return 'Every ' . $this->joinNames($names) . $time;
    }

    private function monthlyLabel(RehearsalSchedule $schedule, string $time): string
    {
        if ($schedule->monthly_pattern === 'day_of_month' && $schedule->day_of_month) {
            return 'Monthly on the ' . $this->ordinal((int) $schedule->day_of_month) . $time;
        }

        if ($schedule->monthly_pattern && $schedule->monthly_weekday) {
            return ucfirst($schedule->monthly_pattern) . ' '
                . ucfirst(strtolower($schedule->monthly_weekday))
                . ' of each month' . $time;
        }

        return 'Monthly' . $time;
    }

    private function joinNames(array $names): string
    {
        if (count($names) === 1) {
            return $names[0];
        }

        $last = array_pop($names);

        return implode(', ', $names) . ' & ' . $last;
    }

    private function ordinal(int $n): string
    {
        if (in_array($n % 100, [11, 12, 13], true)) {
            return $n . 'th';
        }

        return $n . match ($n % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            default => 'th',
        };
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=RecurrenceLabelServiceTest`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add app/Services/Mobile/RecurrenceLabelService.php tests/Unit/Services/Mobile/RecurrenceLabelServiceTest.php
git commit -m "feat(mobile): add recurrence label formatter for rehearsal schedules

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Backend — `include_virtual`, `until`, and `recurrence_label` on the schedules endpoint

**Files:**
- Modify: `app/Http/Controllers/Api/Mobile/RehearsalsController.php:24-52` (the `schedules` method)
- Test: `tests/Feature/Api/Mobile/RehearsalsTest.php`

**Interfaces:**
- Consumes: `RecurrenceLabelService::format(RehearsalSchedule): string` (Task 3); `RehearsalScheduleService::generateUpcomingRehearsals(array $bandIds, Carbon $start, Carbon $end): Collection` (existing — items are arrays with keys `date`, `time` (H:i:s), `key`, `venue_name`, `venue_address`, `rehearsal_schedule_id`).
- Produces: `GET /api/mobile/bands/{band}/rehearsal-schedules?include_virtual=1&until=Y-m-d`.
  Each schedule gains `recurrence_label` (string, always present). With `include_virtual=1`, `upcoming_rehearsals` items gain `is_virtual` (bool); virtual items have `id: null`, `event_key: "virtual-rehearsal-{scheduleId}-{date}"`, `time: "HH:mm"`. `until` is INCLUSIVE (matches the existing `<= cutoff` predicate) and defaults to now+60d. Without `include_virtual`, `upcoming_rehearsals` items are unchanged (no `is_virtual` key).

- [ ] **Step 1: Write the failing tests**

Append to `tests/Feature/Api/Mobile/RehearsalsTest.php`:

```php
    public function test_schedules_includes_recurrence_label(): void
    {
        ['band' => $band, 'token' => $token] = $this->createUserWithBandAndRehearsal();

        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/rehearsal-schedules");

        $response->assertOk();
        // Factory weekly() state: day_of_week=wednesday, default_time=19:00:00.
        $this->assertSame(
            'Every Wednesday at 7:00 PM',
            $response->json('schedules.0.recurrence_label')
        );
    }

    public function test_schedules_default_response_has_no_virtuals(): void
    {
        ['band' => $band, 'token' => $token] = $this->createUserWithBandAndRehearsal();

        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/rehearsal-schedules");

        $response->assertOk();
        foreach ($response->json('schedules.0.upcoming_rehearsals') as $item) {
            $this->assertArrayNotHasKey('is_virtual', $item,
                'default response must stay byte-compatible for old clients');
            $this->assertNotNull($item['id']);
        }
    }

    public function test_schedules_include_virtual_merges_virtual_occurrences(): void
    {
        [
            'band'      => $band,
            'schedule'  => $schedule,
            'rehearsal' => $rehearsal,
            'event'     => $event,
            'token'     => $token,
        ] = $this->createUserWithBandAndRehearsal();

        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/rehearsal-schedules?include_virtual=1");

        $response->assertOk();
        $upcoming = collect($response->json('schedules.0.upcoming_rehearsals'));

        // The materialized rehearsal is present exactly once, flagged real.
        $real = $upcoming->where('id', $rehearsal->id);
        $this->assertCount(1, $real);
        $this->assertFalse($real->first()['is_virtual']);

        // Virtual occurrences exist, have null ids and parseable keys.
        $virtuals = $upcoming->where('is_virtual', true);
        $this->assertGreaterThanOrEqual(6, $virtuals->count(),
            'weekly schedule over 60 days should yield ~8 virtual occurrences');
        $virtuals->each(function ($v) use ($schedule) {
            $this->assertNull($v['id']);
            $this->assertStringStartsWith("virtual-rehearsal-{$schedule->id}-", $v['event_key']);
        });

        // No virtual duplicates the materialized rehearsal's date.
        $materializedDate = $event->date instanceof \Carbon\Carbon
            ? $event->date->toDateString()
            : \Carbon\Carbon::parse($event->date)->toDateString();
        $this->assertCount(0, $virtuals->where('date', $materializedDate));

        // Sorted ascending by date.
        $dates = $upcoming->pluck('date')->all();
        $sorted = $dates;
        sort($sorted);
        $this->assertSame($sorted, $dates);
    }

    public function test_schedules_until_extends_the_window(): void
    {
        ['band' => $band, 'token' => $token] = $this->createUserWithBandAndRehearsal();

        $until = now()->addDays(180)->toDateString();
        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/rehearsal-schedules?include_virtual=1&until={$until}");

        $response->assertOk();
        $virtuals = collect($response->json('schedules.0.upcoming_rehearsals'))
            ->where('is_virtual', true);

        $beyondSixty = $virtuals->filter(
            fn ($v) => $v['date'] > now()->addDays(60)->toDateString()
        );
        $this->assertGreaterThanOrEqual(10, $beyondSixty->count(),
            'weekly virtuals must extend past the default 60-day cutoff');
        $virtuals->each(fn ($v) => $this->assertLessThanOrEqual($until, $v['date']));
    }

    public function test_schedules_inactive_schedule_gets_no_virtuals(): void
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);
        RehearsalSchedule::factory()->weekly()->inactive()->create(['band_id' => $band->id]);
        $token = $user->createToken('test-device')->plainTextToken;

        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/rehearsal-schedules?include_virtual=1");

        $response->assertOk();
        $this->assertSame([], $response->json('schedules.0.upcoming_rehearsals'));
        $this->assertNotNull($response->json('schedules.0.recurrence_label'));
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=RehearsalsTest`
Expected: new tests FAIL (`recurrence_label` missing / no virtuals); existing tests PASS.

- [ ] **Step 3: Implement**

Replace the `schedules` method in `RehearsalsController` with:

```php
    /**
     * GET /api/mobile/bands/{band}/rehearsal-schedules
     *
     * List all rehearsal schedules for a band with upcoming rehearsals.
     * Window: today .. `until` (inclusive, default +60 days). With
     * `include_virtual=1`, un-materialized occurrences generated from the
     * schedule's recurrence rule are merged in (id: null, event_key:
     * "virtual-rehearsal-{scheduleId}-{date}"). Both params are opt-in so the
     * default response stays byte-compatible for old clients.
     */
    public function schedules(Request $request): JsonResponse
    {
        $band           = $request->input('mobile_band');
        $includeVirtual = $request->boolean('include_virtual');
        $cutoff         = $request->filled('until')
            ? Carbon::parse($request->input('until'))->toDateString()
            : now()->addDays(60)->toDateString();

        $schedules = RehearsalSchedule::where('band_id', $band->id)
            ->with(['rehearsals' => function ($query) use ($cutoff) {
                $query->whereHas('events', function ($eq) use ($cutoff) {
                    $eq->where('date', '>=', now()->toDateString())
                       ->where('date', '<=', $cutoff);
                })->with('events');
            }])
            ->get();

        $virtualBySchedule = collect();
        if ($includeVirtual) {
            // endOfDay so the inclusive `until` date survives the generators'
            // exclusive `lt($endDate)` loops.
            $virtualBySchedule = (new RehearsalScheduleService())
                ->generateUpcomingRehearsals([$band->id], now(), Carbon::parse($cutoff)->endOfDay())
                ->groupBy('rehearsal_schedule_id');
        }

        $labels = new RecurrenceLabelService();

        $mapped = $schedules->map(function ($schedule) use ($labels, $includeVirtual, $virtualBySchedule) {
            $upcoming = $schedule->rehearsals
                ->map(fn ($r) => $this->rehearsalService->formatSummary($r)
                    + ($includeVirtual ? ['is_virtual' => false] : []));

            if ($includeVirtual) {
                $virtuals = ($virtualBySchedule[$schedule->id] ?? collect())->map(fn ($v) => [
                    'id'            => null,
                    'date'          => $v['date'],
                    'time'          => substr((string) $v['time'], 0, 5),
                    'venue_name'    => $v['venue_name'],
                    'venue_address' => $v['venue_address'],
                    'is_cancelled'  => false,
                    'notes'         => null,
                    'event_key'     => $v['key'],
                    'is_virtual'    => true,
                ]);
                $upcoming = $upcoming->concat($virtuals)->sortBy('date')->values();
            }

            return [
                'id'                  => $schedule->id,
                'name'                => $schedule->name,
                'description'         => $schedule->description,
                'frequency'           => $schedule->frequency,
                'recurrence_label'    => $labels->format($schedule),
                'location_name'       => $schedule->location_name,
                'location_address'    => $schedule->location_address,
                'active'              => $schedule->active,
                'upcoming_rehearsals' => $upcoming->values()->all(),
            ];
        });

        return response()->json(['schedules' => $mapped->values()]);
    }
```

Add imports to the controller's use block:

```php
use App\Services\Mobile\RecurrenceLabelService;
use App\Services\RehearsalScheduleService;
use Illuminate\Support\Carbon;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=RehearsalsTest`
Expected: ALL PASS. Then run the full mobile suite once: `docker compose exec app php artisan test tests/Feature/Api/Mobile`
Expected: ALL PASS.

- [ ] **Step 5: Commit and open the backend PR**

```bash
git add app/Http/Controllers/Api/Mobile/RehearsalsController.php tests/Feature/Api/Mobile/RehearsalsTest.php
git commit -m "feat(mobile): opt-in virtual occurrences, until window, and recurrence labels on rehearsal schedules

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin feat/calendar-forward-windows
gh pr create --base staging --title "feat(mobile): forward calendar windows + infinite rehearsal rendering" --body "$(cat <<'EOF'
## Summary
- New `GET /api/mobile/dashboard/load-newer` endpoint: bounded future windows with virtual rehearsals, mirroring load-older
- Opt-in `?to=` forward bound on the initial dashboard payload (absent = unchanged old-client behavior)
- `?include_virtual=1` + `?until=` on rehearsal-schedules: merged virtual+real occurrences; `recurrence_label` on every schedule

Spec: tts_bandmate `docs/superpowers/specs/2026-07-25-calendar-forward-windows-design.md`
Companion app PR: (link after it exists)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Wait for Copilot review comments and address them before calling the PR done.

---

### Task 5: Flutter — repository layer (`load-newer`, `to`, schedules params)

**Files:**
- Modify: `lib/core/network/api_endpoints.dart:19-21`
- Modify: `lib/features/dashboard/data/dashboard_repository.dart`
- Modify: `lib/features/rehearsals/data/rehearsals_repository.dart:14-25`
- Test: `test/features/dashboard/dashboard_repository_test.dart` (create)
- Test: `test/features/rehearsals/rehearsals_repository_test.dart` (extend)

**Interfaces:**
- Produces (used by Tasks 6, 9):
  - `ApiEndpoints.mobileDashboardLoadNewer` = `'/api/mobile/dashboard/load-newer'`
  - `DashboardRepository.getDashboard({String? to})` — sends `?to=` when non-null
  - `DashboardRepository.loadNewerEvents(String afterDate, String beforeDate)` → `List<EventSummary>`
  - (The `RehearsalsRepository.getSchedules` param change is produced by Task 9 — this task only writes its test, skipped until then.)

- [ ] **Step 1: Switch to the app repo/branch**

```bash
cd /home/eddie/github/tts_bandmate
git checkout feat/calendar-forward-windows
```

- [ ] **Step 2: Write the failing tests**

Create `test/features/dashboard/dashboard_repository_test.dart` (adapter-fake pattern copied from `test/features/rehearsals/rehearsals_repository_test.dart`):

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';

/// Adapter that records the request and returns a canned JSON response.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responseBody);

  final Map<String, dynamic> responseBody;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(responseBody),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DashboardRepository _repo(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = adapter;
  return DashboardRepository(dio);
}

void main() {
  test('getDashboard sends to= when provided', () async {
    final adapter = _FakeAdapter({'events': [], 'upcoming_charts': []});
    await _repo(adapter).getDashboard(to: '2026-10-23');

    expect(adapter.lastRequest!.path, '/api/mobile/dashboard');
    expect(adapter.lastRequest!.queryParameters, {'to': '2026-10-23'});
  });

  test('getDashboard omits to= when null', () async {
    final adapter = _FakeAdapter({'events': [], 'upcoming_charts': []});
    await _repo(adapter).getDashboard();

    expect(adapter.lastRequest!.queryParameters, isEmpty);
  });

  test('loadNewerEvents hits load-newer with both bounds and parses events',
      () async {
    final adapter = _FakeAdapter({
      'events': [
        {
          'id': null,
          'key': 'virtual-rehearsal-3-2026-11-04',
          'title': 'Weekly Rehearsal',
          'date': '2026-11-04',
          'event_source': 'rehearsal_schedule',
        },
      ],
    });

    final events =
        await _repo(adapter).loadNewerEvents('2026-10-23', '2026-12-01');

    expect(adapter.lastRequest!.path, '/api/mobile/dashboard/load-newer');
    expect(adapter.lastRequest!.queryParameters,
        {'after_date': '2026-10-23', 'before_date': '2026-12-01'});
    expect(events, hasLength(1));
    expect(events.first.id, isNull);
    expect(events.first.key, 'virtual-rehearsal-3-2026-11-04');
    expect(events.first.isRehearsal, isTrue);
  });
}
```

Append to `test/features/rehearsals/rehearsals_repository_test.dart` (reuses its existing `_FakeAdapter`):

```dart
  test('getSchedules passes until and include_virtual and parses new fields',
      () async {
    final adapter = _FakeAdapter({
      'schedules': [
        {
          'id': 7,
          'name': 'Weekly Rehearsal',
          'frequency': 'weekly',
          'recurrence_label': 'Every Wednesday at 7:00 PM',
          'active': true,
          'upcoming_rehearsals': [
            {
              'id': 42,
              'date': '2026-07-29',
              'is_cancelled': false,
              'is_virtual': false,
            },
            {
              'id': null,
              'date': '2026-08-05',
              'event_key': 'virtual-rehearsal-7-2026-08-05',
              'is_cancelled': false,
              'is_virtual': true,
            },
          ],
        },
      ],
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://x'))
      ..httpClientAdapter = adapter;
    final repo = RehearsalsRepository(dio);

    final schedules = await repo.getSchedules(1,
        until: '2026-10-23', includeVirtual: true);

    expect(adapter.lastRequest!.path, '/api/mobile/bands/1/rehearsal-schedules');
    expect(adapter.lastRequest!.queryParameters,
        {'until': '2026-10-23', 'include_virtual': 1});

    final schedule = schedules.single;
    expect(schedule.recurrenceLabel, 'Every Wednesday at 7:00 PM');
    expect(schedule.upcomingRehearsals, hasLength(2));
    expect(schedule.upcomingRehearsals[0].id, 42);
    expect(schedule.upcomingRehearsals[0].isVirtual, isFalse);
    expect(schedule.upcomingRehearsals[1].id, isNull);
    expect(schedule.upcomingRehearsals[1].isVirtual, isTrue);
    expect(schedule.upcomingRehearsals[1].eventKey,
        'virtual-rehearsal-7-2026-08-05');
  });
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/dashboard/dashboard_repository_test.dart test/features/rehearsals/rehearsals_repository_test.dart`
Expected: compile errors — `getDashboard` takes no `to`, `loadNewerEvents`/`recurrenceLabel`/`isVirtual` undefined. (Model fields land in Task 8; the rehearsals test stays red until then — that's fine, the dashboard repo test must pass by end of this task. If you prefer green, defer writing the rehearsals test addition to Task 8 Step 1.)

**Decision for the implementer:** write the rehearsals test now but move model + repository param changes for rehearsals into Task 8/9 as specced there; this task only makes the DASHBOARD tests green. Keep the rehearsals test in a `skip:` state until Task 9:

```dart
  }, skip: 'enabled in Task 9');
```

- [ ] **Step 4: Implement the dashboard repository changes**

`lib/core/network/api_endpoints.dart` — after `mobileDashboardLoadOlder`:

```dart
  static const String mobileDashboardLoadNewer =
      '/api/mobile/dashboard/load-newer';
```

`lib/features/dashboard/data/dashboard_repository.dart` — change `getDashboard` and add `loadNewerEvents`:

```dart
  /// Fetches the dashboard payload — upcoming events and charts.
  /// [to] (yyyy-MM-dd, exclusive) bounds the forward window; events beyond it
  /// are fetched lazily via [loadNewerEvents].
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard({String? to}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileDashboard,
      queryParameters: {if (to != null) 'to': to},
    );
    // ... body unchanged ...
  }

  /// Fetches a future window of events for the calendar's lazy forward-fetch.
  /// Both bounds are yyyy-MM-dd strings; the window is [afterDate, beforeDate).
  Future<List<EventSummary>> loadNewerEvents(
      String afterDate, String beforeDate) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileDashboardLoadNewer,
      queryParameters: {'after_date': afterDate, 'before_date': beforeDate},
    );

    final rawEvents = response.data?['events'] as List<dynamic>? ?? [];
    return rawEvents
        .cast<Map<String, dynamic>>()
        .map(EventSummary.fromJson)
        .toList();
  }
```

- [ ] **Step 5: Run dashboard repo tests to verify they pass**

Run: `flutter test test/features/dashboard/dashboard_repository_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/core/network/api_endpoints.dart lib/features/dashboard/data/dashboard_repository.dart test/features/dashboard/dashboard_repository_test.dart test/features/rehearsals/rehearsals_repository_test.dart
git commit -m "feat(dashboard): repository support for load-newer windows and to= bound

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Flutter — `DashboardState.loadedTo` + `loadNewer` + forward `ensureMonthLoaded`

**Files:**
- Modify: `lib/features/dashboard/providers/dashboard_provider.dart`
- Test: `test/features/dashboard/dashboard_provider_test.dart` (extend)

**Interfaces:**
- Consumes: `DashboardRepository.getDashboard({String? to})`, `loadNewerEvents(String, String)` (Task 5).
- Produces (used by Task 7): `DashboardState.loadedTo` (DateTime, exclusive forward watermark), `DashboardState.isLoadingNewer` (bool), `DashboardNotifier.ensureMonthLoaded(DateTime focusedDay)` now handles BOTH directions.

- [ ] **Step 1: Write the failing tests**

In `test/features/dashboard/dashboard_provider_test.dart`, extend `_FakeDashboardRepository`:

```dart
  /// Successive responses for each loadNewerEvents call, in order. When
  /// exhausted, returns an empty list.
  final List<List<EventSummary>> newerBatches;

  final List<(String, String)> requestedNewerWindows = [];
  final List<String?> requestedTos = [];
  int _newerIndex = 0;

  @override
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard({String? to}) async {
    requestedTos.add(to);
    return (events: initialEvents, upcomingCharts: const <UpcomingChart>[]);
  }

  @override
  Future<List<EventSummary>> loadNewerEvents(
      String afterDate, String beforeDate) async {
    requestedNewerWindows.add((afterDate, beforeDate));
    if (_newerIndex >= newerBatches.length) return const [];
    return newerBatches[_newerIndex++];
  }
```

(Update the constructor: `this.newerBatches = const []` as a named optional; existing tests keep compiling.)

Add a new group:

```dart
  group('DashboardNotifier.loadNewer', () {
    // Helpers `setUpContainer` / `buildNotifier` reused from the file.

    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    test('initial fetch sends to = today + 90d', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: [], olderBatches: [],
      ));
      await buildNotifier();

      final expected = ymd(DateTime.now().add(const Duration(days: 90)));
      expect(fakeRepo.requestedTos, [expected]);
    });

    test('forward ensureMonthLoaded fetches one window to the month start after target', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: [], olderBatches: [],
        newerBatches: [
          [_event(5, '2028-03-10')],
        ],
      ));
      final notifier = await buildNotifier();

      // Jump 2+ years forward — must be a single fetch, not many.
      final target = DateTime(2028, 3, 15);
      await notifier.ensureMonthLoaded(target);

      expect(fakeRepo.requestedNewerWindows, hasLength(1));
      final (after, before) = fakeRepo.requestedNewerWindows.single;
      expect(after, ymd(DateTime.now().add(const Duration(days: 90))),
          reason: 'window starts at the current loadedTo watermark');
      expect(before, '2028-04-01',
          reason: 'window extends to the first day of the month after target');

      final state = container.read(dashboardProvider).value!;
      expect(state.events.map((e) => e.id), contains(5));
      expect(state.loadedTo, DateTime(2028, 4, 1));
    });

    test('already-covered months trigger no fetch and empty windows do not stop future fetches', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: [], olderBatches: [],
        newerBatches: [], // every loadNewer returns empty
      ));
      final notifier = await buildNotifier();

      await notifier.ensureMonthLoaded(DateTime(2027, 6, 15));
      expect(fakeRepo.requestedNewerWindows, hasLength(1));

      // Same month again: covered, no new fetch.
      await notifier.ensureMonthLoaded(DateTime(2027, 6, 20));
      expect(fakeRepo.requestedNewerWindows, hasLength(1));

      // Further month: MUST fetch again despite the last window being empty —
      // there is no hasReachedEnd for the future.
      await notifier.ensureMonthLoaded(DateTime(2028, 1, 10));
      expect(fakeRepo.requestedNewerWindows, hasLength(2));
    });

    test('merges newer events deduping by id and by key for null-id events', () async {
      EventSummary nullIdEvent(String key, String date) =>
          EventSummary.fromJson({
            'key': key,
            'title': 'Event $key',
            'date': date,
            'event_source': 'rehearsal',
          });

      setUpContainer(_FakeDashboardRepository(
        initialEvents: [_event(1, '2026-08-01'), nullIdEvent('vr-a', '2026-08-05')],
        olderBatches: [],
        newerBatches: [
          [
            _event(1, '2026-08-01'), // dup by id — dropped
            nullIdEvent('vr-a', '2026-08-05'), // dup by key — dropped
            nullIdEvent('vr-b', '2026-11-12'), // new — kept
            _event(2, '2026-12-01'), // new — kept
          ],
        ],
      ));
      final notifier = await buildNotifier();

      await notifier.ensureMonthLoaded(DateTime(2026, 12, 15));

      final state = container.read(dashboardProvider).value!;
      expect(state.events, hasLength(4));
    });

    test('refresh resets the forward watermark', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: [], olderBatches: [], newerBatches: [],
      ));
      final notifier = await buildNotifier();
      await notifier.ensureMonthLoaded(DateTime(2028, 3, 15));

      await notifier.refresh();

      final state = container.read(dashboardProvider).value!;
      final expected = DateTime.now().add(const Duration(days: 90));
      expect(state.loadedTo.year, expected.year);
      expect(state.loadedTo.month, expected.month);
      expect(state.loadedTo.day, expected.day);
      // And the refresh re-sent to=.
      expect(fakeRepo.requestedTos, hasLength(2));
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/dashboard/dashboard_provider_test.dart`
Expected: compile errors (`newerBatches`, `loadedTo` undefined).

- [ ] **Step 3: Implement**

In `lib/features/dashboard/providers/dashboard_provider.dart`:

`DashboardState` — add fields (constructor, declarations, `copyWith`):

```dart
  /// Exclusive forward watermark: events on/after this date are NOT loaded
  /// yet. Only ever moves forward (see [DashboardNotifier._loadNewer]);
  /// [DashboardNotifier.refresh] resets it. There is deliberately no
  /// "reached end" flag — an empty forward window proves nothing about later
  /// events, so the browse cap is the calendar's lastDay.
  final DateTime loadedTo;

  /// True while a newer-events fetch is in flight.
  final bool isLoadingNewer;
```

`DashboardNotifier`:

```dart
  /// Days of future events the initial payload covers.
  static const int _initialForwardWindowDays = 90;

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _initialTo() => _dateOnly(
      DateTime.now().add(const Duration(days: _initialForwardWindowDays)));
```

`build()` and `refresh()`: compute `final initialTo = _initialTo();`, call `repo.getDashboard(to: _ymd(initialTo))`, and set `loadedTo: initialTo` on the state (both the band-null early return and the loaded state).

New private method:

```dart
  /// Fetches [loadedTo, target) and merges. [target] must be a month-start
  /// (exclusive bound). No-ops while in flight or when already covered.
  Future<void> _loadNewer(DateTime target) async {
    final current = state.value;
    if (current == null) return;
    if (current.isLoadingNewer) return;
    if (!target.isAfter(current.loadedTo)) return; // already covered

    state = AsyncValue.data(current.copyWith(isLoadingNewer: true));

    try {
      final repo = ref.read(dashboardRepositoryProvider);
      final newer = await repo.loadNewerEvents(
          _ymd(current.loadedTo), _ymd(target));

      // Dedup by id when present; by key for null-id events (virtual
      // rehearsals) so an inclusive boundary day can never duplicate.
      final existingIds =
          current.events.map((e) => e.id).whereType<int>().toSet();
      final existingKeys = current.events.map((e) => e.key).toSet();
      final merged = [
        ...current.events,
        ...newer.where((e) => e.id != null
            ? !existingIds.contains(e.id)
            : !existingKeys.contains(e.key)),
      ];

      state = AsyncValue.data(current.copyWith(
        events: merged,
        loadedTo: target,
        isLoadingNewer: false,
      ));
    } catch (_) {
      state = AsyncValue.data(
        (state.value ?? current).copyWith(isLoadingNewer: false),
      );
    }
  }
```

Extend `ensureMonthLoaded` — after the existing backward loop, add the forward branch (and update its doc comment to say it covers both directions):

```dart
    // Forward: cover the focused month in ONE fetch to the month's exclusive
    // end. DateTime normalizes month 13 to January of the next year.
    final nextMonthFirst = DateTime(focusedDay.year, focusedDay.month + 1, 1);
    final current2 = state.value;
    if (current2 != null && nextMonthFirst.isAfter(current2.loadedTo)) {
      await _loadNewer(nextMonthFirst);
    }
```

Note: the existing backward loop `return`s early in several branches (`hasReachedStart`, already covered). Restructure so those `return`s become breaks out of the backward phase only — extract the backward loop into a private `_ensureMonthLoadedBackward(monthStart)` and call both phases from `ensureMonthLoaded`:

```dart
  Future<void> ensureMonthLoaded(DateTime focusedDay) async {
    await _ensureMonthLoadedBackward(DateTime(focusedDay.year, focusedDay.month, 1));

    final nextMonthFirst = DateTime(focusedDay.year, focusedDay.month + 1, 1);
    final current = state.value;
    if (current != null && nextMonthFirst.isAfter(current.loadedTo)) {
      await _loadNewer(nextMonthFirst);
    }
  }
```

where `_ensureMonthLoadedBackward` is the existing while-loop body verbatim (taking `monthStart` as its parameter).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/dashboard/`
Expected: ALL PASS (new group + all pre-existing loadOlder tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/providers/dashboard_provider.dart test/features/dashboard/dashboard_provider_test.dart
git commit -m "feat(dashboard): forward loadedTo watermark with lazy load-newer fetching

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Flutter — extend the calendar's browsable range to 5 years

**Files:**
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart:385`

**Interfaces:**
- Consumes: `ensureMonthLoaded` (Task 6) — already wired to `onPageChanged` at line 160-164; no screen wiring changes needed.

- [ ] **Step 1: Change `lastDay`**

At line 385 replace:

```dart
          lastDay: DateTime.now().add(const Duration(days: 365)),
```

with:

```dart
          // Sanity cap only — forward fetching is lazy (see ensureMonthLoaded),
          // so this bounds the picker, not the data.
          lastDay: DateTime.now().add(const Duration(days: 365 * 5)),
```

- [ ] **Step 2: Analyze and run the full dashboard test suite**

Run: `flutter analyze && flutter test test/features/dashboard/`
Expected: no new analyzer issues; ALL PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/features/dashboard/screens/dashboard_screen.dart
git commit -m "feat(dashboard): allow calendar browsing five years forward

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Flutter — rehearsal models support virtual occurrences and recurrence labels

**Files:**
- Modify: `lib/features/rehearsals/data/models/rehearsal_summary.dart`
- Modify: `lib/features/rehearsals/data/models/rehearsal_schedule.dart`
- Test: `test/features/rehearsals/rehearsal_models_test.dart` (create)

**Interfaces:**
- Produces (used by Tasks 9, 10): `RehearsalSummary.id` becomes `int?`; new `RehearsalSummary.isVirtual` (bool, default false); new `RehearsalSchedule.recurrenceLabel` (String?).

- [ ] **Step 1: Write the failing tests**

Create `test/features/rehearsals/rehearsal_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_schedule.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_summary.dart';

void main() {
  test('RehearsalSummary parses a virtual occurrence (null id)', () {
    final summary = RehearsalSummary.fromJson({
      'id': null,
      'date': '2026-08-05',
      'time': '19:00',
      'is_cancelled': false,
      'event_key': 'virtual-rehearsal-7-2026-08-05',
      'is_virtual': true,
    });

    expect(summary.id, isNull);
    expect(summary.isVirtual, isTrue);
    expect(summary.eventKey, 'virtual-rehearsal-7-2026-08-05');
  });

  test('RehearsalSummary defaults isVirtual to false for old payloads', () {
    final summary = RehearsalSummary.fromJson({
      'id': 42,
      'date': '2026-07-29',
      'is_cancelled': false,
    });

    expect(summary.id, 42);
    expect(summary.isVirtual, isFalse);
  });

  test('RehearsalSchedule parses recurrence_label and tolerates absence', () {
    final withLabel = RehearsalSchedule.fromJson({
      'id': 7,
      'name': 'Weekly',
      'active': true,
      'recurrence_label': 'Every Wednesday at 7:00 PM',
      'upcoming_rehearsals': [],
    });
    expect(withLabel.recurrenceLabel, 'Every Wednesday at 7:00 PM');

    final without = RehearsalSchedule.fromJson({
      'id': 8,
      'name': 'Old payload',
      'active': true,
      'upcoming_rehearsals': [],
    });
    expect(without.recurrenceLabel, isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/rehearsals/rehearsal_models_test.dart`
Expected: FAIL — null `id` cast throws; `isVirtual`/`recurrenceLabel` undefined.

- [ ] **Step 3: Implement**

`rehearsal_summary.dart`: change `id` to `final int? id;` (constructor: `this.id,` no longer `required`), add `final bool isVirtual;` (constructor: `this.isVirtual = false,`), and in `fromJson`:

```dart
      id: json['id'] == null ? null : (json['id'] as num).toInt(),
      isVirtual: (json['is_virtual'] as bool?) ?? false,
```

`rehearsal_schedule.dart`: add `final String? recurrenceLabel;` (constructor: `this.recurrenceLabel,`), and in `fromJson`:

```dart
      recurrenceLabel: json['recurrence_label'] as String?,
```

- [ ] **Step 4: Fix compile fallout from the nullable id**

Run: `flutter analyze`
Expected errors at `lib/features/rehearsals/screens/rehearsals_screen.dart:227` (`'/rehearsals/${rehearsal.id}'` still compiles — string interpolation accepts null — so check analyze output carefully; the real fix for navigation lands in Task 10). Any OTHER nullable-id errors (e.g. sorting, map keys) must be fixed here with `?.` / null guards. Do not change navigation behavior in this task.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/rehearsals/`
Expected: model tests PASS; pre-existing repository/widget tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/rehearsals/data/models/ test/features/rehearsals/rehearsal_models_test.dart
git commit -m "feat(rehearsals): model support for virtual occurrences and recurrence labels

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Flutter — schedules repository params + window provider

**Files:**
- Modify: `lib/features/rehearsals/data/rehearsals_repository.dart:14-25`
- Modify: `lib/features/rehearsals/providers/rehearsals_provider.dart`
- Test: `test/features/rehearsals/rehearsals_repository_test.dart` (un-skip Task 5's test)
- Test: `test/features/rehearsals/rehearsals_provider_test.dart` (create)

**Interfaces:**
- Consumes: models from Task 8.
- Produces (used by Task 10): `schedulesWindowDaysProvider` (`StateProvider<int>`, default 90); `schedulesProvider` now fetches with `until = today + windowDays` (inclusive, `yyyy-MM-dd`) and `includeVirtual: true`.

- [ ] **Step 1: Un-skip the repository test from Task 5**

Remove the `skip:` argument added in Task 5 Step 3.

- [ ] **Step 2: Write the failing provider test**

Create `test/features/rehearsals/rehearsals_provider_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_schedule.dart';
import 'package:tts_bandmate/features/rehearsals/data/rehearsals_repository.dart';
import 'package:tts_bandmate/features/rehearsals/providers/rehearsals_provider.dart';

final _throwingDio = Dio();

class _FakeRehearsalsRepository extends RehearsalsRepository {
  _FakeRehearsalsRepository() : super(_throwingDio);

  final List<({int bandId, String? until, bool includeVirtual})> calls = [];

  @override
  Future<List<RehearsalSchedule>> getSchedules(int bandId,
      {String? until, bool includeVirtual = false}) async {
    calls.add((bandId: bandId, until: until, includeVirtual: includeVirtual));
    return const [];
  }
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  test('schedulesProvider fetches with until = today + window and virtuals on',
      () async {
    final repo = _FakeRehearsalsRepository();
    final container = ProviderContainer(overrides: [
      rehearsalsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await container.read(schedulesProvider(1).future);

    final call = repo.calls.single;
    expect(call.bandId, 1);
    expect(call.includeVirtual, isTrue);
    expect(call.until, _ymd(DateTime.now().add(const Duration(days: 90))));
  });

  test('bumping schedulesWindowDaysProvider refetches with a larger until',
      () async {
    final repo = _FakeRehearsalsRepository();
    final container = ProviderContainer(overrides: [
      rehearsalsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await container.read(schedulesProvider(1).future);
    container.read(schedulesWindowDaysProvider.notifier).state += 90;
    // The family provider rebuilds; await the new future.
    await container.read(schedulesProvider(1).future);

    expect(repo.calls, hasLength(2));
    expect(repo.calls.last.until,
        _ymd(DateTime.now().add(const Duration(days: 180))));
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/rehearsals/`
Expected: compile errors — `getSchedules` named params and `schedulesWindowDaysProvider` undefined.

- [ ] **Step 4: Implement**

`rehearsals_repository.dart` — change `getSchedules`:

```dart
  /// Fetches the rehearsal schedules (with upcoming rehearsals) for [bandId].
  /// [until] (yyyy-MM-dd, inclusive) extends the upcoming window past the
  /// server's 60-day default; [includeVirtual] merges un-materialized
  /// occurrences generated from each schedule's recurrence rule.
  Future<List<RehearsalSchedule>> getSchedules(
    int bandId, {
    String? until,
    bool includeVirtual = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRehearsalSchedules(bandId),
      queryParameters: {
        if (until != null) 'until': until,
        if (includeVirtual) 'include_virtual': 1,
      },
    );
    // ... body unchanged ...
  }
```

`rehearsals_provider.dart`:

```dart
/// Days ahead the rehearsals list covers. "Show more" bumps this by 90; a
/// pull-to-refresh keeps the current window.
final schedulesWindowDaysProvider = StateProvider<int>((_) => 90);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
```

and change `schedulesProvider`'s body:

```dart
final schedulesProvider =
    FutureProvider.family<List<RehearsalSchedule>, int>(
        (ref, bandId) async {
  final windowDays = ref.watch(schedulesWindowDaysProvider);
  final until = DateTime.now().add(Duration(days: windowDays));
  final repo = ref.watch(rehearsalsRepositoryProvider);
  return repo.getSchedules(bandId, until: _ymd(until), includeVirtual: true);
});
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/rehearsals/`
Expected: ALL PASS (including the un-skipped Task 5 test).

- [ ] **Step 6: Commit**

```bash
git add lib/features/rehearsals/data/rehearsals_repository.dart lib/features/rehearsals/providers/rehearsals_provider.dart test/features/rehearsals/
git commit -m "feat(rehearsals): fetch schedules with virtual occurrences and growable window

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Flutter — Rehearsals tab UI (rule headline, virtual rows, Show more)

**Files:**
- Modify: `lib/features/rehearsals/screens/rehearsals_screen.dart`
- Test: manual verification + `flutter analyze` + full `flutter test` (widget testing of Cupertino expandables is out of scope; the logic lives in already-tested providers/models)

**Interfaces:**
- Consumes: `RehearsalSchedule.recurrenceLabel`, `RehearsalSummary.isVirtual`/nullable `id` (Task 8), `schedulesWindowDaysProvider` (Task 9), existing routes `/rehearsals/:id` and `/rehearsals/by-key/:key`.

- [ ] **Step 1: Rule headline in `_ScheduleTile`**

In the `subtitle` list (lines 105-111), replace the frequency line:

```dart
      if (schedule.frequency != null && schedule.frequency!.isNotEmpty)
        _capitalise(schedule.frequency!),
```

with:

```dart
      if (schedule.recurrenceLabel != null &&
          schedule.recurrenceLabel!.isNotEmpty)
        schedule.recurrenceLabel!
      else if (schedule.frequency != null && schedule.frequency!.isNotEmpty)
        _capitalise(schedule.frequency!),
```

- [ ] **Step 2: Virtual-aware `_RehearsalSubTile`**

Replace the `onTap` (line 226-227):

```dart
      onTap: () {
        final id = rehearsal.id;
        if (id != null) {
          GoRouter.of(context).push('/rehearsals/$id');
        } else if (rehearsal.eventKey != null) {
          // Virtual occurrence — resolved (and materialized) server-side.
          GoRouter.of(context).push('/rehearsals/by-key/${rehearsal.eventKey}');
        }
      },
```

Replace the leading icon (lines 232-240) so virtual occurrences read as "recurring, not yet scheduled":

```dart
            Icon(
              rehearsal.isCancelled
                  ? CupertinoIcons.xmark_circle
                  : rehearsal.isVirtual
                      ? CupertinoIcons.repeat
                      : CupertinoIcons.checkmark_circle,
              size: 20,
              color: rehearsal.isCancelled
                  ? CupertinoColors.systemRed
                  : context.secondaryText,
            ),
```

- [ ] **Step 3: "Show more" affordance**

In `_RehearsalsBody.build`, after the `SliverList` inside the `data:` branch (line 83-89), wrap in a list so a footer can follow — replace the `data:` return with:

```dart
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == schedules.length) {
                    return const _ShowMoreButton();
                  }
                  return _ScheduleTile(schedule: schedules[index]);
                },
                childCount: schedules.length + 1,
              ),
            );
```

Add the widget at the bottom of the file:

```dart
/// Extends the upcoming-rehearsals window by 90 days. The provider refetch
/// replaces the list wholesale (idempotent — see spec §2).
class _ShowMoreButton extends ConsumerWidget {
  const _ShowMoreButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: CupertinoButton(
          onPressed: () =>
              ref.read(schedulesWindowDaysProvider.notifier).state += 90,
          child: const Text('Show more'),
        ),
      ),
    );
  }
}
```

(`_RehearsalsBody` is already a `ConsumerWidget`; `flutter_riverpod` is already imported.)

- [ ] **Step 4: Analyze and run the full test suite**

Run: `flutter analyze && flutter test`
Expected: no new analyzer issues; ALL tests PASS.

- [ ] **Step 5: Commit and open the app PR**

```bash
git add lib/features/rehearsals/screens/rehearsals_screen.dart
git commit -m "feat(rehearsals): recurrence headline, virtual occurrences, and Show more window

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin feat/calendar-forward-windows
gh pr create --base main --title "feat: infinite forward calendar + rehearsal recurrence rendering" --body "$(cat <<'EOF'
## Summary
- Calendar browses 5 years forward with lazy load-newer windows (mirrors loadOlder); rehearsals and 3-year-out bookings both render wherever you swipe
- Rehearsals tab: recurrence-rule headline, merged virtual+real occurrences, Show more extends the window
- Virtual occurrences navigate through the existing by-key materialization route

Spec: docs/superpowers/specs/2026-07-25-calendar-forward-windows-design.md
Companion backend PR: (link TTS PR)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Wait for Copilot review comments and address them before calling the PR done.

---

### Task 11: On-device verification

**Files:** none (verification only)

- [ ] **Step 1: Backend must be running locally** (`docker compose up` in the TTS repo, on the feature branch).

- [ ] **Step 2: Use the `run-on-device` skill** to launch the app on the physical Android phone against the local backend, then verify:
  1. Dashboard calendar: swipe forward past 3 months — rehearsal markers keep appearing (previously stopped ~8 weeks out).
  2. Swipe/jump to a month 2+ years out — far-future bookings render; one loading spinner, not many.
  3. Tap a far-future virtual rehearsal marker — the by-key detail screen opens.
  4. Rehearsals tab: each schedule shows its recurrence label; upcoming list includes future virtual rows (repeat icon); "Show more" extends the list.
  5. Tap a virtual row — detail opens (server materializes it).

- [ ] **Step 3: Report results** — screenshots of the far-future month and the rehearsals tab.
