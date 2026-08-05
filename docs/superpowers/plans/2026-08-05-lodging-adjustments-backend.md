# Lodging Adjustments — Backend + Web Plan (TTS repo)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Logistics-only lodging on the advance page (replacing the legacy artifact), lodging lines on dashboard event cards, and date-aware searchable link pickers on the web lodging form.

**Architecture:** A `LodgingService::formatLogistics()` formatter is the single sensitive-field firewall reused by advance + dashboard payloads. The advance is the Blade view `resources/views/advance/advance.blade.php` (the Inertia `Pages/Events/Advance.vue` is dead code — deleted here). Picker smarts are client-side; the only payload change is a representative `date` on booking options.

**Tech Stack:** Laravel 10, Blade (advance), Inertia + Vue 3, Vitest, PHPUnit.

**Repo:** `/home/eddie/github/TTS`, fresh branch `feat/lodging-surfaces` off up-to-date `staging`. PR base `staging`.

## Global Constraints

- ALL php/artisan/npm/npx via `docker-compose exec app <cmd>` (hyphenated), never on host.
- Advance lodging fields: **name, address, check_in_at, check_out_at, room_count — nothing else.** No confirmation numbers, notes, or attachment URLs anywhere in the advance response.
- Wire datetimes `Y-m-d H:i:s`. Vue tests assert on `wrapper.text()`, never `<!--v-if-->`.
- Legacy `additional_data.lodging` data and the legacy `BandEvents.lodging` scalar stay in the DB/model — only presentation artifacts are removed.
- Conventional commits; run `--filter=Lodging` + touched suites while iterating, full `--parallel` + `npx vitest run` before the PR. Known flake: CalendarFeedTest under parallel (re-run file alone before blaming a change).

---

### Task 1: `formatLogistics()` + booking picker dates

**Files:**
- Modify: `app/Services/Mobile/LodgingService.php` (add method after `formatSummary`)
- Modify: `app/Http/Controllers/LodgingController.php:66,113` (bookings prop) and the `create`/`edit` methods' surroundings
- Test: `tests/Feature/LodgingWebTest.php` (extend)

**Interfaces:**
- Produces: `LodgingService::formatLogistics(Lodging $lodging): array` → `['id'=>int,'name'=>string,'address'=>?string,'check_in_at'=>'Y-m-d H:i:s','check_out_at'=>'Y-m-d H:i:s','room_count'=>int]`. Booking options become `['id'=>int,'name'=>string,'date'=>?string /* Y-m-d of nearest event */]`.
- Consumes: `Bookings::events(): MorphMany` (`app/Models/Bookings.php:98`), events have a `date` column (bookings themselves have none).

- [ ] **Step 1: Write the failing tests** (append to `tests/Feature/LodgingWebTest.php`)

```php
    public function test_format_logistics_exposes_only_safe_fields(): void
    {
        $band = Bands::factory()->create();
        $lodging = Lodging::factory()->create([
            'band_id' => $band->id,
            'name'    => 'Safe Hotel',
            'notes'   => 'SECRET-NOTE',
        ]);
        $lodging->rooms()->create(['label' => 'King', 'confirmation_number' => 'SECRET-CONF', 'sort_order' => 0]);

        $logistics = app(\App\Services\Mobile\LodgingService::class)
            ->formatLogistics($lodging->fresh()->loadCount('rooms'));

        $this->assertSame(
            ['id', 'name', 'address', 'check_in_at', 'check_out_at', 'room_count'],
            array_keys($logistics),
        );
        $this->assertSame(1, $logistics['room_count']);
        $this->assertStringNotContainsString('SECRET', json_encode($logistics));
    }

    public function test_booking_picker_options_carry_nearest_event_date(): void
    {
        $user = User::factory()->create(['email_verified_at' => now()]);
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $booking = \App\Models\Bookings::factory()->create(['band_id' => $band->id, 'name' => 'Dated Booking']);
        \App\Models\Events::factory()->create([
            'eventable_id' => $booking->id, 'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id' => \App\Models\EventTypes::factory()->create()->id,
            'date' => now()->addDays(9)->format('Y-m-d'),
        ]);
        $eventless = \App\Models\Bookings::factory()->create(['band_id' => $band->id, 'name' => 'Eventless']);

        $response = $this->actingAs($user)->get(route('bands.lodgings.create', $band));
        $response->assertOk();
        $bookings = collect($response->viewData('page')['props']['bookings']);

        $dated = $bookings->firstWhere('name', 'Dated Booking');
        $this->assertSame(now()->addDays(9)->format('Y-m-d'), $dated['date']);
        $this->assertNull($bookings->firstWhere('name', 'Eventless')['date']);
    }
```

Check how neighbouring tests read Inertia props (grep `viewData('page')` vs `assertInertia` in `tests/Feature/LodgingWebTest.php`) and use the established idiom.

- [ ] **Step 2: Run to verify failure**

Run: `docker-compose exec app php artisan test --filter=LodgingWebTest`
Expected: FAIL — `formatLogistics` undefined; missing `date` key.

- [ ] **Step 3: Implement `formatLogistics`** in `app/Services/Mobile/LodgingService.php`:

```php
    /**
     * Safe-for-sharing subset: the advance page URL travels outside the
     * band, so this deliberately omits confirmation numbers, notes, and
     * attachments. Add fields here only if they are safe on a passed-around
     * advance link.
     */
    public function formatLogistics(Lodging $lodging): array
    {
        return [
            'id'           => $lodging->id,
            'name'         => $lodging->name,
            'address'      => $lodging->address,
            'check_in_at'  => $lodging->check_in_at?->format('Y-m-d H:i:s'),
            'check_out_at' => $lodging->check_out_at?->format('Y-m-d H:i:s'),
            'room_count'   => $lodging->rooms_count ?? $lodging->rooms()->count(),
        ];
    }
```

- [ ] **Step 4: Booking options with dates.** In `app/Http/Controllers/LodgingController.php`, replace both `'bookings' => $band->bookings()->orderByDesc('created_at')->get(['id', 'name'])` occurrences (`:66`, `:113`) with a shared private method:

```php
    /**
     * Picker options: bookings have no date column (dates live on their
     * events), so each option carries its nearest event date — the next
     * upcoming one, else the most recent past one — for proximity sorting.
     */
    private function bookingOptions(Bands $band): array
    {
        $today = now()->toDateString();

        return $band->bookings()
            ->with(['events' => fn ($q) => $q->orderBy('date')->select(['id', 'eventable_id', 'eventable_type', 'date'])])
            ->get(['id', 'name'])
            ->map(function ($booking) use ($today) {
                $dates = $booking->events->pluck('date')->map(fn ($d) => (string) $d)->sort()->values();
                $date = $dates->first(fn ($d) => $d >= $today) ?? $dates->last();
                return ['id' => $booking->id, 'name' => $booking->name, 'date' => $date ?: null];
            })
            ->sortBy(fn ($b) => $b['date'] ?? '9999-99-99')
            ->values()
            ->toArray();
    }
```

Check the `events.date` cast on `Events` (`date:Y-m-d` Carbon) — `(string) $d` may yield a full timestamp; normalise with `substr((string) $d, 0, 10)` if the test shows a mismatch.

- [ ] **Step 5: Run tests**

Run: `docker-compose exec app php artisan test --filter=LodgingWebTest`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app tests
git commit -m "feat(lodging): logistics formatter + dated booking picker options"
```

---

### Task 2: Advance page — legacy artifact out, logistics section in

**Files:**
- Modify: `app/Http/Controllers/EventsController.php:72-91` (`advance()`)
- Modify: `resources/views/advance/advance.blade.php` (legacy `$additionalData->lodging` mapping at ~:67-69, lodging cell at ~:144-146)
- Delete: `resources/js/Pages/Events/Advance.vue` (dead code — its only render call is commented out at `EventsController.php:88`; verify with `grep -rn "Events/Advance" resources/ app/` that nothing else references it before deleting)
- Test: `tests/Feature/AdvanceLodgingTest.php`

**Interfaces:**
- Consumes: `formatLogistics()` (Task 1), `Events::lodgings()` relation.
- Produces: `advance.advance` view receives `lodgings` (array of logistics arrays, check-in ascending).

- [ ] **Step 1: Failing test**

```php
<?php
// tests/Feature/AdvanceLodgingTest.php
namespace Tests\Feature;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\Events;
use App\Models\EventTypes;
use App\Models\Lodging;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AdvanceLodgingTest extends TestCase
{
    use RefreshDatabase;

    private function createEventWithLodging(): array
    {
        $user = User::factory()->create(['email_verified_at' => now()]);
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        $event = Events::factory()->create([
            'eventable_id' => $booking->id, 'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id' => EventTypes::factory()->create()->id,
            'date' => now()->addDays(5)->format('Y-m-d'),
        ]);
        $lodging = Lodging::factory()->create([
            'band_id' => $band->id, 'event_id' => $event->id,
            'name' => 'Advance Hotel', 'address' => '500 Beach Rd',
            'notes' => 'SECRET-NOTE',
        ]);
        $lodging->rooms()->create(['label' => 'King', 'confirmation_number' => 'SECRET-CONF', 'sort_order' => 0]);
        return compact('user', 'band', 'event');
    }

    public function test_advance_shows_lodging_logistics_only(): void
    {
        ['user' => $user, 'event' => $event] = $this->createEventWithLodging();

        $response = $this->actingAs($user)->get(route('events.advance', ['key' => $event->key]));

        $response->assertOk()
            ->assertSee('Advance Hotel')
            ->assertSee('500 Beach Rd')
            ->assertDontSee('SECRET-NOTE')
            ->assertDontSee('SECRET-CONF')
            ->assertDontSee('There will be lodging');
    }

    public function test_advance_without_lodging_shows_no_lodging_section(): void
    {
        ['user' => $user, 'event' => $event] = $this->createEventWithLodging();
        Lodging::where('event_id', $event->id)->forceDelete();

        $this->actingAs($user)
            ->get(route('events.advance', ['key' => $event->key]))
            ->assertOk()
            ->assertDontSee('Advance Hotel');
    }
}
```

- [ ] **Step 2: Run to verify failure** — `docker-compose exec app php artisan test --filter=AdvanceLodgingTest` — Expected: FAIL (SECRET strings absent-check may pass, `Advance Hotel` assertSee fails).

- [ ] **Step 3: Controller.** In `EventsController::advance()` (line ~72-91), before the `return view(...)`:

```php
        $lodgings = $event->lodgings()
            ->withCount('rooms')
            ->orderBy('check_in_at')
            ->get()
            ->map(fn ($l) => app(\App\Services\Mobile\LodgingService::class)->formatLogistics($l))
            ->values()
            ->toArray();

        return view('advance.advance', ['event' => $event, 'lodgings' => $lodgings]);
```

- [ ] **Step 4: Blade.** In `resources/views/advance/advance.blade.php`:
  - Delete the `@php` legacy mapping block lines `if (isset($additionalData->lodging)) { $event['lodging'] = $additionalData->lodging; }` (~:67-69).
  - Replace the legacy lodging cell (`<div class="border text-center">Lodging:</div>` + the 🏨/👎 conditional, ~:144-146) with nothing (remove the pair from that grid).
  - Add a logistics section after the Notes block (find `<div class="-ml-2 font-bold">Notes:</div>` ~:152 and place after its container), matching surrounding markup style:

```blade
        @if (!empty($lodgings))
        <div class="px-6 mt-4">
            <div class="-ml-2 font-bold">Lodging:</div>
            @foreach ($lodgings as $lodging)
            <div class="border rounded px-3 py-2 mt-2">
                <div class="font-semibold">{{ $lodging['name'] }}</div>
                @if ($lodging['address'])
                <div>{{ $lodging['address'] }}</div>
                @endif
                <div>
                    Check-in {{ \Carbon\Carbon::parse($lodging['check_in_at'])->format('D, M j g:i A') }}
                    — Check-out {{ \Carbon\Carbon::parse($lodging['check_out_at'])->format('D, M j g:i A') }}
                </div>
                <div>{{ $lodging['room_count'] }} {{ \Illuminate\Support\Str::plural('room', $lodging['room_count']) }}</div>
            </div>
            @endforeach
        </div>
        @endif
```

- [ ] **Step 5: Delete dead page.** `grep -rn "Events/Advance" resources/ app/` → only the commented `EventsController.php:88` line; delete `resources/js/Pages/Events/Advance.vue` and the commented line. Run `docker-compose exec app npx vitest run` to confirm no test referenced it.

- [ ] **Step 6: Run** — `docker-compose exec app php artisan test --filter=AdvanceLodgingTest` — Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add app resources tests
git commit -m "feat(lodging): logistics-only lodging on advance, remove legacy artifact + dead Advance.vue"
```

---

### Task 3: Dashboard event cards

**Files:**
- Modify: `app/Http/Controllers/DashboardController.php` (`index()` ~:17-31 and `loadOlderEvents()`)
- Modify: `resources/js/Components/Event/Card/Body.vue` (lodging line — near where the removed legacy `Lodging Provided` block sat, after the attire/extra-details region)
- Test: `tests/Feature/DashboardLodgingTest.php`, `resources/js/tests/components/eventcardlodging.test.js`

**Interfaces:**
- Consumes: `formatLogistics()`; `UserEventsService::getEvents()` returns a collection of `Events` models.
- Produces: each dashboard event gains `lodgings_summary` (array of logistics arrays; empty array when none). `Body.vue` renders `event.lodgings_summary`.

- [ ] **Step 1: Failing PHP test**

```php
<?php
// tests/Feature/DashboardLodgingTest.php
namespace Tests\Feature;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\Events;
use App\Models\EventTypes;
use App\Models\Lodging;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class DashboardLodgingTest extends TestCase
{
    use RefreshDatabase;

    public function test_dashboard_events_carry_lodging_logistics_summary(): void
    {
        $user = User::factory()->create(['email_verified_at' => now()]);
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        $event = Events::factory()->create([
            'eventable_id' => $booking->id, 'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id' => EventTypes::factory()->create()->id,
            'date' => now()->addDays(3)->format('Y-m-d'),
        ]);
        Lodging::factory()->create([
            'band_id' => $band->id, 'event_id' => $event->id,
            'name' => 'Dash Hotel', 'notes' => 'SECRET-NOTE',
        ]);

        $response = $this->actingAs($user)->get('/dashboard');
        $response->assertOk();

        $events = collect($response->viewData('page')['props']['events']);
        $withLodging = $events->firstWhere('id', $event->id);
        $this->assertSame('Dash Hotel', $withLodging['lodgings_summary'][0]['name']);
        $this->assertStringNotContainsString('SECRET-NOTE', json_encode($withLodging['lodgings_summary']));
    }
}
```

- [ ] **Step 2: Run to verify failure** — `--filter=DashboardLodgingTest` — FAIL (missing key).

- [ ] **Step 3: Controller.** In `DashboardController::index()` after `$events = (new UserEventsService())->getEvents();`:

```php
        $this->attachLodgingSummaries($events);
```
and add the private helper (also call it in `loadOlderEvents()` on its events collection before returning):

```php
    /**
     * Attach a logistics-only lodging summary to each event. Uses the
     * shared formatter so dashboard payloads can never leak confirmation
     * numbers or notes.
     */
    private function attachLodgingSummaries($events): void
    {
        $service = app(\App\Services\Mobile\LodgingService::class);
        $ids = collect($events)->pluck('id')->filter()->all();
        $byEvent = \App\Models\Lodging::whereIn('event_id', $ids)
            ->withCount('rooms')
            ->orderBy('check_in_at')
            ->get()
            ->groupBy('event_id');

        foreach ($events as $event) {
            $event->lodgings_summary = ($byEvent->get($event->id) ?? collect())
                ->map(fn ($l) => $service->formatLogistics($l))->values()->toArray();
        }
    }
```
`getEvents()` may return models or arrays — check its return shape first (`app/Services/UserEventsService.php`); if items are arrays, set `$event['lodgings_summary']` instead. Adapt and note in the report.

- [ ] **Step 4: Vue.** In `resources/js/Components/Event/Card/Body.vue`, add after the attire block (the region where the legacy `Lodging Provided` lookup used to live, ~:670):

```vue
    <div
      v-if="event.lodgings_summary && event.lodgings_summary.length"
      class="mt-2"
    >
      <a
        v-for="lodging in event.lodgings_summary"
        :key="lodging.id"
        :href="route('lodgings.show', lodging.id)"
        class="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100"
      >
        <span>🛏</span>
        <span class="truncate">{{ lodging.name }}</span>
        <span class="flex-none">· in {{ formatCheckIn(lodging.check_in_at) }}</span>
      </a>
    </div>
```
with a script helper (match Body.vue's script style — it's Options API per `Footer.vue`; check and follow):
```js
    formatCheckIn(sql) {
        if (!sql) return '';
        const dt = DateTime.fromSQL(sql);
        return dt.isValid ? dt.toFormat('h:mm a') : '';
    },
```
(luxon `DateTime` — check Body.vue's existing imports; import if absent.)

- [ ] **Step 5: Vitest**

```js
// resources/js/tests/components/eventcardlodging.test.js
import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import Body from '@/Components/Event/Card/Body.vue';

global.route = vi.fn((name, id) => `/mock/${name}/${id}`);

const baseEvent = {
  id: 1, title: 'Gig', date: '2030-05-01',
  lodgings_summary: [
    { id: 9, name: 'Dash Hotel', address: null, check_in_at: '2030-04-30 15:00:00', check_out_at: '2030-05-02 11:00:00', room_count: 2 },
  ],
};

describe('EventCard Body lodging line', () => {
  it('renders hotel name and check-in time', () => {
    const wrapper = mount(Body, { props: { event: baseEvent } });
    expect(wrapper.text()).toContain('Dash Hotel');
    expect(wrapper.text()).toContain('3:00 PM');
  });

  it('renders nothing without lodging', () => {
    const wrapper = mount(Body, { props: { event: { ...baseEvent, lodgings_summary: [] } } });
    expect(wrapper.text()).not.toContain('Dash Hotel');
  });
});
```
Body.vue may require more props/stubs to mount — check how `eventcardbody.test.js` mounts it and copy its scaffolding (stubs, extra props) exactly.

- [ ] **Step 6: Run both** — `--filter=DashboardLodgingTest` and `npx vitest run resources/js/tests/components/eventcardlodging.test.js` — PASS.

- [ ] **Step 7: Commit**

```bash
git add app resources tests
git commit -m "feat(lodging): lodging logistics line on dashboard event cards"
```

---

### Task 4: Web link picker — proximity + search

**Files:**
- Create: `resources/js/utils/lodgingLinkOptions.js`
- Create: `resources/js/Components/Lodging/LinkPicker.vue`
- Modify: `resources/js/Pages/Lodging/Form.vue:109-150` (replace both `<select>` blocks)
- Test: `resources/js/tests/utils/lodgingLinkOptions.test.js`, extend `resources/js/tests/components/lodgingform.test.js`

**Interfaces:**
- Consumes: `bookings` prop items `{id, name, date|null}` (Task 1), `events` prop items `{id, title, date}` (existing `bandEventOptions`), `form.check_in_at`/`form.check_out_at` (`'Y-m-d H:i:s'` strings).
- Produces:
  - `groupLinkOptions(options, checkIn, checkOut)` → `[{label: 'During your stay'|'Nearby'|'Everything else', options: [{id, name, date}]}]` (groups omitted when empty; within groups sorted by |date − checkIn|; without checkIn one group `''` sorted date-ascending from today, undated last).
  - `<LinkPicker v-model="form.booking_id" :options="bookings" :check-in="form.check_in_at" :check-out="form.check_out_at" label="Linked Booking" />` — renders a text filter input + grouped option list (radio-style rows incl. a None row), emits `update:modelValue` with `id|null`.

- [ ] **Step 1: Failing util test**

```js
// resources/js/tests/utils/lodgingLinkOptions.test.js
import { describe, it, expect } from 'vitest';
import { groupLinkOptions } from '@/utils/lodgingLinkOptions';

const opt = (id, name, date) => ({ id, name, date });

describe('groupLinkOptions', () => {
  const checkIn = '2030-06-10 15:00:00';
  const checkOut = '2030-06-13 11:00:00';

  it('groups by stay window, proximity, and the rest', () => {
    const groups = groupLinkOptions([
      opt(1, 'Far future', '2030-09-01'),
      opt(2, 'During', '2030-06-11'),
      opt(3, 'Near before', '2030-06-01'),
      opt(4, 'Undated', null),
    ], checkIn, checkOut);

    expect(groups.map(g => g.label)).toEqual(['During your stay', 'Nearby', 'Everything else']);
    expect(groups[0].options.map(o => o.id)).toEqual([2]);
    expect(groups[1].options.map(o => o.id)).toEqual([3]);
    expect(groups[2].options.map(o => o.id)).toEqual([1, 4]);
  });

  it('sorts nearby by distance from check-in', () => {
    const groups = groupLinkOptions([
      opt(1, 'Nine off', '2030-06-19'),
      opt(2, 'Two off', '2030-06-08'),
    ], checkIn, checkOut);
    expect(groups[0].label).toBe('Nearby');
    expect(groups[0].options.map(o => o.id)).toEqual([2, 1]);
  });

  it('without check-in: single group, date-ascending, undated last', () => {
    const groups = groupLinkOptions([
      opt(1, 'B', '2030-07-01'),
      opt(2, 'A', '2030-06-01'),
      opt(3, 'U', null),
    ], null, null);
    expect(groups).toHaveLength(1);
    expect(groups[0].options.map(o => o.id)).toEqual([2, 1, 3]);
  });
});
```

- [ ] **Step 2: Run to verify failure** — `npx vitest run resources/js/tests/utils/lodgingLinkOptions.test.js` — FAIL.

- [ ] **Step 3: Implement util**

```js
// resources/js/utils/lodgingLinkOptions.js
const DAY_MS = 86400000;
const NEARBY_DAYS = 14;

const toDay = (value) => {
  if (!value) return null;
  const d = new Date(String(value).slice(0, 10) + 'T00:00:00');
  return Number.isNaN(d.getTime()) ? null : d.getTime();
};

/**
 * Groups picker options ({id, name|title, date}) around a stay.
 * With a check-in: "During your stay" / "Nearby" (±14 days) / "Everything
 * else". Without: one unlabeled group, date-ascending, undated last.
 */
export function groupLinkOptions(options, checkIn, checkOut) {
  const inDay = toDay(checkIn);
  const outDay = toDay(checkOut) ?? inDay;

  if (inDay == null) {
    const sorted = [...options].sort((a, b) => {
      const da = toDay(a.date); const db = toDay(b.date);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da - db;
    });
    return [{ label: '', options: sorted }];
  }

  const during = []; const nearby = []; const rest = [];
  for (const o of options) {
    const day = toDay(o.date);
    if (day != null && day >= inDay && day <= outDay) during.push(o);
    else if (day != null && Math.abs(day - inDay) <= NEARBY_DAYS * DAY_MS) nearby.push(o);
    else rest.push(o);
  }
  const dist = (o) => Math.abs(toDay(o.date) - inDay);
  during.sort((a, b) => dist(a) - dist(b));
  nearby.sort((a, b) => dist(a) - dist(b));
  rest.sort((a, b) => {
    const da = toDay(a.date); const db = toDay(b.date);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da - db;
  });

  return [
    { label: 'During your stay', options: during },
    { label: 'Nearby', options: nearby },
    { label: 'Everything else', options: rest },
  ].filter(g => g.options.length);
}
```

- [ ] **Step 4: LinkPicker component.** `resources/js/Components/Lodging/LinkPicker.vue`: props `modelValue` (Number|null), `options` (Array), `checkIn`/`checkOut` (String|null), `label` (String); a filter `<input>` (`w-full p-2 border rounded dark:bg-slate-700 dark:text-gray-50 mb-2`, placeholder "Filter…"); computed `groups = groupLinkOptions(filtered, checkIn, checkOut)` where `filtered` matches `(o.name ?? o.title)` case-insensitively; renders a bordered scrollable list (`max-h-56 overflow-y-auto border rounded dark:border-slate-600`) with a "None" row on top and per-group headers (`text-xs font-semibold text-gray-500 dark:text-gray-400 px-2 pt-2`); each option row a button showing name + date (`DateTime.fromISO(o.date).toFormat('EEE, MMM d, yyyy')`), highlighted when `o.id === modelValue` (`bg-blue-500/10 text-blue-500`), clicking emits `update:modelValue`. Label rendered via the existing `Label` component. Add `data-testid="link-picker-option"` on option rows and `data-testid="link-picker-filter"` on the input.

- [ ] **Step 5: Wire into Form.vue.** Replace the booking `<select>` block (`Form.vue:109-134`) with:
```vue
                  <LinkPicker
                    v-model="form.booking_id"
                    :options="bookings"
                    :check-in="form.check_in_at"
                    :check-out="form.check_out_at"
                    label="Linked Booking"
                  />
                  <InputError :message="form.errors.booking_id" class="mt-2" />
```
and the event block likewise (`label="Linked Event"`, `:options="events"`). Note: `form.check_in_at`/`check_out_at` are composed at submit-time from the date/time refs — pass the composed values instead: add computed `composedCheckIn`/`composedCheckOut` reusing the existing `composeDateTime` helpers and bind those. Import LinkPicker; delete the now-unused select markup.

- [ ] **Step 6: Component test.** Extend `lodgingform.test.js`: filter input narrows options (mount Form with 3 bookings, type into `[data-testid="link-picker-filter"]`, assert visible `link-picker-option` count); selecting an option sets the highlighted row. Follow the file's existing mock scaffolding verbatim.

- [ ] **Step 7: Run** — `npx vitest run` (full) — PASS.

- [ ] **Step 8: Commit**

```bash
git add resources/js
git commit -m "feat(lodging): proximity-grouped searchable link pickers on web form"
```

---

### Task 5: Full suites + PR

- [ ] **Step 1:** `docker-compose exec app php artisan test --parallel` and `docker-compose exec app npx vitest run` — green (CalendarFeedTest flake: re-run alone).
- [ ] **Step 2:** Push + PR:
```bash
git push -u origin feat/lodging-surfaces
gh pr create --base staging --title "feat(lodging): advance/dashboard surfaces + smart link pickers" --body "$(cat <<'EOF'
## Summary
- Advance page: legacy "There will be lodging." artifact removed (Blade + dead Advance.vue deleted); logistics-only lodging section (name/address/check-in/out/room count — confirmation numbers, notes, attachments deliberately excluded, enforced server-side in LodgingService::formatLogistics)
- Dashboard event cards: compact lodging line (name + check-in) via the same safe formatter
- Lodging form: booking/event pickers become searchable lists grouped by date proximity ("During your stay" / "Nearby" / rest); booking options now carry their nearest event date

## Test plan
- [x] AdvanceLodgingTest (logistics present, secrets absent, artifact gone)
- [x] DashboardLodgingTest + eventcardlodging vitest
- [x] lodgingLinkOptions util + form picker tests
- [x] Full parallel + vitest suites green

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_014HjpXvYak8CfXzEH1sVKh7
EOF
)"
```
- [ ] **Step 3:** Wait for Copilot review and address comments. Merge before the mobile PR (mobile picker needs no backend change, but keep the established backend-first order).
