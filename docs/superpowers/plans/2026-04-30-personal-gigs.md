# Personal Gigs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user track gigs that don't belong to any band on the platform (church sub gigs, wedding-band fill-ins). Personal gigs appear on the Dashboard and Bookings tab alongside band gigs, with the user's avatar + "Personal" label distinguishing them. The personal-band wrapper stays invisible to the user.

**Architecture:** Personal gigs are bookings on a `bands.is_personal = true` band, lazily created via `POST /api/mobile/bands/solo` when the user creates their first personal gig. A new aggregating endpoint `GET /api/mobile/me/bookings` returns all bookings across the user's bands so the Bookings tab becomes a true multi-band view. Each booking and dashboard event gains nested band identity (`{ id, name, logo_url, is_personal }`) so a shared `BandIdentityChip` widget can render the right avatar + label per item.

**Tech Stack:**
- Backend: Laravel (PHP), tested with PHPUnit
- Mobile: Flutter, Riverpod v2, Cupertino widgets, Dio HTTP client, GoRouter
- Tests: `flutter_test` with `ProviderContainer` for Riverpod, custom `StubAdapter` for HTTP fakes

---

## File Structure

### Backend (Laravel) — TTS repo at `/home/eddie/github/TTS`

| File | Responsibility |
|---|---|
| `app/Services/Mobile/TokenService.php` | Add `is_personal` and `logo_url` to `formatBands()` output |
| `app/Http/Controllers/Api/Mobile/BookingsController.php` | New `indexForUser()` action returning bookings across all the user's bands |
| `app/Http/Controllers/Api/Mobile/Formatters/BookingFormatter.php` (or wherever the formatter lives) | Add `band` object to each formatted booking |
| `app/Http/Controllers/Api/Mobile/DashboardController.php` (or wherever the dashboard endpoint is) | Add `band` object to each event in the dashboard payload |
| `routes/api.php` | Register `GET /api/mobile/me/bookings` |
| `tests/Feature/Mobile/MeBookingsTest.php` | New feature test for the aggregating endpoint |
| `tests/Feature/Mobile/BookingFormatterTest.php` (or extend an existing one) | Test that bookings include the `band` field |

### Mobile (Flutter) — `/home/eddie/github/tts_bandmate`

| File | Responsibility |
|---|---|
| `lib/features/auth/data/models/band_summary.dart` | Add `isPersonal` and `logoUrl` fields |
| `lib/features/auth/data/models/auth_user.dart` | Add `avatarUrl` field |
| `lib/features/bookings/data/models/booking_summary.dart` | Add nested `band` field |
| `lib/features/events/data/models/event_summary.dart` | Add nested `band` field |
| `lib/core/network/api_endpoints.dart` | Add `mobileMeBookings` constant |
| `lib/features/bookings/data/bookings_repository.dart` | Add `getAllUserBookings()` method |
| `lib/features/bookings/providers/bookings_provider.dart` | Add `userBookingsProvider` (multi-band) |
| `lib/shared/providers/personal_band_provider.dart` (new) | Derived getter + `ensureExists()` mutation |
| `lib/shared/widgets/band_identity_chip.dart` (new) | Renders avatar + label, swaps for personal bands |
| `lib/features/bookings/widgets/create_booking_sheet.dart` (new) | Sheet with real bands + "Personal gig" row |
| `lib/features/bookings/screens/bookings_screen.dart` | Refactor body to use `userBookingsProvider`, render `BandIdentityChip` on cards |
| `lib/features/dashboard/widgets/event_card.dart` | Render `BandIdentityChip` |
| `lib/features/dashboard/screens/dashboard_screen.dart` | Wire "+" button to open `CreateBookingSheet` |
| `lib/features/auth/screens/band_selector_screen.dart` | Filter out personal band from list |
| `test/models/band_summary_test.dart` (new) | Test new fields |
| `test/models/booking_summary_test.dart` (new) | Test nested band field |
| `test/models/event_summary_band_test.dart` (new, or extend existing) | Test nested band field |
| `test/providers/personal_band_provider_test.dart` (new) | Three cases of `ensureExists()` |
| `test/providers/user_bookings_provider_test.dart` (new) | Hits `/me/bookings`, parses payload |
| `test/widgets/band_identity_chip_test.dart` (new) | Renders both modes |
| `test/widgets/create_booking_sheet_test.dart` (new) | All sheet states |
| `test/widgets/band_selector_filters_personal_test.dart` (new) | Personal band hidden |

---

## Tasks

The plan is split into three phases: **(1) Backend** (mobile depends on it), **(2) Mobile data layer** (models, repository, providers), **(3) Mobile UI** (widgets, screens, end-to-end wiring).

---

### Task 1: Backend — Add `is_personal` and `logo_url` to `formatBands()`

**Files:**
- Modify: `/home/eddie/github/TTS/app/Services/Mobile/TokenService.php:47-54`
- Test: `/home/eddie/github/TTS/tests/Feature/Mobile/TokenServiceFormatBandsTest.php` (new)

**Why:** The mobile app reads its bands list via `auth/me` (which calls `formatBands`). Without `is_personal` in that payload, the mobile app can't tell which band is personal — and without `logo_url`, the band-identity chip can't render a logo.

**Verify before writing:** Check whether a `tests/Feature/Mobile/TokenService*` test file already exists. If so, add a test method to it instead of creating a new file.

- [ ] **Step 1: Verify whether a TokenService test file exists**

```bash
find /home/eddie/github/TTS/tests -name 'TokenService*' -type f
```

If a file exists, the rest of this task adds a test method to it. If not, create a new file as shown.

- [ ] **Step 2: Write the failing test (new file)**

Create `/home/eddie/github/TTS/tests/Feature/Mobile/TokenServiceFormatBandsTest.php`:

```php
<?php

namespace Tests\Feature\Mobile;

use App\Models\BandOwners;
use App\Models\Bands;
use App\Models\User;
use App\Services\Mobile\TokenService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TokenServiceFormatBandsTest extends TestCase
{
    use RefreshDatabase;

    public function test_format_bands_includes_is_personal_and_logo_url(): void
    {
        $user = User::factory()->create();

        $regular = Bands::create([
            'name' => 'The Real Band',
            'site_name' => 'the-real-band',
            'logo' => 'logos/real.png',
            'is_personal' => false,
        ]);
        $personal = Bands::create([
            'name' => "{$user->name}'s Band",
            'site_name' => 'eddies-band',
            'logo' => null,
            'is_personal' => true,
        ]);

        BandOwners::create(['user_id' => $user->id, 'band_id' => $regular->id]);
        BandOwners::create(['user_id' => $user->id, 'band_id' => $personal->id]);

        $service = app(TokenService::class);
        $formatted = $service->formatBands($user);

        $this->assertCount(2, $formatted);

        $regularRow = collect($formatted)->firstWhere('id', $regular->id);
        $this->assertSame('The Real Band', $regularRow['name']);
        $this->assertFalse($regularRow['is_personal']);
        $this->assertNotNull($regularRow['logo_url']);

        $personalRow = collect($formatted)->firstWhere('id', $personal->id);
        $this->assertTrue($personalRow['is_personal']);
        $this->assertNull($personalRow['logo_url']);
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=TokenServiceFormatBandsTest
```

Expected: FAIL — current `formatBands()` doesn't return `is_personal` or `logo_url`.

- [ ] **Step 4: Update `formatBands()` to include the new fields**

In `/home/eddie/github/TTS/app/Services/Mobile/TokenService.php`, replace the body of `formatBands()`:

```php
public function formatBands(User $user): array
{
    return $user->allBands()->map(fn ($b) => [
        'id'          => $b->id,
        'name'        => $b->name,
        'is_owner'    => $user->ownsBand($b->id),
        'is_personal' => (bool) $b->is_personal,
        'logo_url'    => $b->logo ? asset('storage/' . $b->logo) : null,
    ])->values()->all();
}
```

**Note on `logo_url`:** check how other endpoints expose logos — if there's a `logoUrl` accessor on `Bands` already, prefer that. If `$b->logo` is stored as a full URL elsewhere, drop the `asset()` wrapper. Match existing conventions.

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=TokenServiceFormatBandsTest
```

Expected: PASS.

- [ ] **Step 6: Run the full mobile-controller test suite to catch regressions**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=Mobile
```

Expected: PASS. (Existing tests should not regress since they check `id`/`name`/`is_owner` only.)

- [ ] **Step 7: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Services/Mobile/TokenService.php tests/Feature/Mobile/TokenServiceFormatBandsTest.php && git commit -m "feat(mobile): include is_personal and logo_url in formatBands"
```

---

### Task 2: Backend — Add `band` field to formatted bookings

**Files:**
- Modify: the booking formatter that `BookingsController` uses (find via `grep -rn "BookingFormatter\\|formatter->format" /home/eddie/github/TTS/app/`)
- Test: `/home/eddie/github/TTS/tests/Feature/Mobile/BookingFormatterBandFieldTest.php` (new)

**Why:** Mobile cards render band identity per booking. Without a `band` field on each booking response, mobile would have to look up band info separately.

- [ ] **Step 1: Locate the booking formatter**

```bash
grep -rn 'class BookingFormatter\|->formatter->format' /home/eddie/github/TTS/app/
```

Note the file path of the formatter and the class name.

- [ ] **Step 2: Write the failing test**

Create `/home/eddie/github/TTS/tests/Feature/Mobile/BookingFormatterBandFieldTest.php`:

```php
<?php

namespace Tests\Feature\Mobile;

use App\Models\BandOwners;
use App\Models\Bands;
use App\Models\Bookings;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class BookingFormatterBandFieldTest extends TestCase
{
    use RefreshDatabase;

    public function test_booking_index_response_includes_band_field(): void
    {
        $user = User::factory()->create();
        $band = Bands::create([
            'name' => 'Test Band',
            'site_name' => 'test-band',
            'is_personal' => false,
        ]);
        BandOwners::create(['user_id' => $user->id, 'band_id' => $band->id]);

        Bookings::create([
            'name' => 'Test Gig',
            'date' => '2026-06-01',
            'band_id' => $band->id,
            'status' => 'confirmed',
        ]);

        Sanctum::actingAs($user);

        $response = $this->getJson("/api/mobile/bands/{$band->id}/bookings");
        $response->assertOk();

        $first = $response->json('bookings.0');
        $this->assertArrayHasKey('band', $first);
        $this->assertSame($band->id, $first['band']['id']);
        $this->assertSame('Test Band', $first['band']['name']);
        $this->assertFalse($first['band']['is_personal']);
        $this->assertArrayHasKey('logo_url', $first['band']);
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=BookingFormatterBandFieldTest
```

Expected: FAIL — bookings don't currently include a `band` field.

- [ ] **Step 4: Add the `band` field to the formatter**

In the booking-formatter file located in Step 1, locate the array returned for a single booking and add a `band` key. Example (adjust to actual formatter code):

```php
return [
    // ...existing fields...
    'band' => [
        'id'          => $booking->band->id,
        'name'        => $booking->band->name,
        'is_personal' => (bool) $booking->band->is_personal,
        'logo_url'    => $booking->band->logo ? asset('storage/' . $booking->band->logo) : null,
    ],
];
```

If the formatter doesn't currently load the band relation, add `with('band')` to queries that pass through it (likely in `BookingsController::index` and `BookingsController::show`).

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=BookingFormatterBandFieldTest
```

Expected: PASS.

- [ ] **Step 6: Run the full mobile booking suite for regressions**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=Mobile
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd /home/eddie/github/TTS && git add -A && git commit -m "feat(mobile): include band field on formatted bookings"
```

---

### Task 3: Backend — Implement `GET /api/mobile/me/bookings`

**Files:**
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/BookingsController.php` (add new method)
- Modify: `/home/eddie/github/TTS/routes/api.php` (register route)
- Test: `/home/eddie/github/TTS/tests/Feature/Mobile/MeBookingsTest.php` (new)

- [ ] **Step 1: Write the failing tests**

Create `/home/eddie/github/TTS/tests/Feature/Mobile/MeBookingsTest.php`:

```php
<?php

namespace Tests\Feature\Mobile;

use App\Models\BandOwners;
use App\Models\Bands;
use App\Models\Bookings;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class MeBookingsTest extends TestCase
{
    use RefreshDatabase;

    public function test_unauthenticated_request_is_rejected(): void
    {
        $response = $this->getJson('/api/mobile/me/bookings');
        $response->assertStatus(401);
    }

    public function test_returns_bookings_across_all_users_bands(): void
    {
        $user = User::factory()->create();

        $bandA = Bands::create([
            'name' => 'Band A', 'site_name' => 'band-a', 'is_personal' => false,
        ]);
        $bandB = Bands::create([
            'name' => 'Band B', 'site_name' => 'band-b', 'is_personal' => false,
        ]);
        $personal = Bands::create([
            'name' => "{$user->name}'s Band", 'site_name' => 'eddies-band', 'is_personal' => true,
        ]);

        foreach ([$bandA, $bandB, $personal] as $b) {
            BandOwners::create(['user_id' => $user->id, 'band_id' => $b->id]);
        }

        Bookings::create(['name' => 'A Gig', 'date' => '2026-06-01', 'band_id' => $bandA->id]);
        Bookings::create(['name' => 'B Gig', 'date' => '2026-06-02', 'band_id' => $bandB->id]);
        Bookings::create(['name' => 'Church', 'date' => '2026-06-03', 'band_id' => $personal->id]);

        Sanctum::actingAs($user);

        $response = $this->getJson('/api/mobile/me/bookings');
        $response->assertOk();

        $bookings = $response->json('bookings');
        $this->assertCount(3, $bookings);

        $names = collect($bookings)->pluck('name')->all();
        $this->assertContains('A Gig', $names);
        $this->assertContains('B Gig', $names);
        $this->assertContains('Church', $names);

        $church = collect($bookings)->firstWhere('name', 'Church');
        $this->assertTrue($church['band']['is_personal']);
    }

    public function test_excludes_bookings_from_bands_user_does_not_belong_to(): void
    {
        $user = User::factory()->create();
        $myBand = Bands::create([
            'name' => 'Mine', 'site_name' => 'mine', 'is_personal' => false,
        ]);
        $otherBand = Bands::create([
            'name' => 'Other', 'site_name' => 'other', 'is_personal' => false,
        ]);
        BandOwners::create(['user_id' => $user->id, 'band_id' => $myBand->id]);

        Bookings::create(['name' => 'Mine Gig', 'date' => '2026-06-01', 'band_id' => $myBand->id]);
        Bookings::create(['name' => 'Other Gig', 'date' => '2026-06-02', 'band_id' => $otherBand->id]);

        Sanctum::actingAs($user);

        $bookings = $this->getJson('/api/mobile/me/bookings')->json('bookings');
        $names = collect($bookings)->pluck('name')->all();
        $this->assertContains('Mine Gig', $names);
        $this->assertNotContains('Other Gig', $names);
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=MeBookingsTest
```

Expected: FAIL with "404 Not Found" (route doesn't exist).

- [ ] **Step 3: Add the controller method**

Add to `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/BookingsController.php` after the existing `index` method:

```php
/**
 * GET /api/mobile/me/bookings
 *
 * Returns bookings across every band the authenticated user belongs to.
 */
public function indexForUser(Request $request): JsonResponse
{
    $user = $request->user();
    $bandIds = $user->allBands()->pluck('id');

    $query = Bookings::query()
        ->with(['band', 'contacts'])
        ->whereIn('band_id', $bandIds);

    if ($request->filled('status')) {
        $query->where('status', $request->input('status'));
    }
    if ($request->boolean('upcoming')) {
        $query->whereDate('date', '>=', now()->toDateString());
    }
    if ($request->filled('year')) {
        $query->whereYear('date', $request->integer('year'));
    }

    $bookings = $query->orderBy('date', 'desc')->get();

    return response()->json([
        'bookings' => $bookings->map(fn ($b) => $this->formatter->format($b))->values(),
    ]);
}
```

Verify imports at the top of the file include `use Illuminate\Http\Request;` and `use App\Models\Bookings;`.

- [ ] **Step 4: Register the route**

In `/home/eddie/github/TTS/routes/api.php`, find the section guarded by mobile auth middleware (the same group that wraps existing `/bands/{band}/bookings` routes — it likely uses `auth:sanctum`). Add **outside** the `mobile.band:read:bookings` middleware (since this isn't band-scoped) but **inside** the mobile-auth group:

```php
Route::get('/me/bookings', [App\Http\Controllers\Api\Mobile\BookingsController::class, 'indexForUser'])
    ->name('mobile.me.bookings');
```

If the existing `/bands/{band}/bookings` group looks like:

```php
Route::middleware('auth:sanctum')->prefix('mobile')->group(function () {
    Route::middleware('mobile.band:read:bookings')->scopeBindings()->group(function () {
        Route::get('/bands/{band}/bookings', ...);
    });
});
```

Add the new line as a sibling of the inner `mobile.band:read:bookings` group (still inside `auth:sanctum`):

```php
Route::middleware('auth:sanctum')->prefix('mobile')->group(function () {
    Route::get('/me/bookings', [App\Http\Controllers\Api\Mobile\BookingsController::class, 'indexForUser'])
        ->name('mobile.me.bookings');

    Route::middleware('mobile.band:read:bookings')->scopeBindings()->group(function () {
        // ... existing per-band routes ...
    });
});
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=MeBookingsTest
```

Expected: PASS (3 tests).

- [ ] **Step 6: Run the full mobile suite for regressions**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=Mobile
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Http/Controllers/Api/Mobile/BookingsController.php routes/api.php tests/Feature/Mobile/MeBookingsTest.php && git commit -m "feat(mobile): add /me/bookings aggregating endpoint"
```

---

### Task 4: Backend — Add `band` field to dashboard event payload

**Files:**
- Modify: the dashboard controller / formatter (find via `grep -rn 'class DashboardController' /home/eddie/github/TTS/app/`)
- Modify: dashboard event formatting (likely in the same controller)
- Test: extend or add `/home/eddie/github/TTS/tests/Feature/Mobile/DashboardEventBandFieldTest.php`

**Why:** The mobile Dashboard's `EventCard` will render a `BandIdentityChip` for each event. The dashboard endpoint already returns events from all the user's bands but currently doesn't include band identity per event.

- [ ] **Step 1: Locate the dashboard event formatter**

```bash
grep -rn 'class DashboardController\|/api/mobile/dashboard' /home/eddie/github/TTS/app/ /home/eddie/github/TTS/routes/
```

Note the controller path and the method that builds the events array.

- [ ] **Step 2: Write the failing test**

Create `/home/eddie/github/TTS/tests/Feature/Mobile/DashboardEventBandFieldTest.php`:

```php
<?php

namespace Tests\Feature\Mobile;

use App\Models\BandOwners;
use App\Models\Bands;
use App\Models\Bookings;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DashboardEventBandFieldTest extends TestCase
{
    use RefreshDatabase;

    public function test_dashboard_events_include_band_field(): void
    {
        $user = User::factory()->create();
        $band = Bands::create([
            'name' => 'Test Band', 'site_name' => 'test-band', 'is_personal' => false,
        ]);
        BandOwners::create(['user_id' => $user->id, 'band_id' => $band->id]);

        Bookings::create([
            'name' => 'Upcoming Gig',
            'date' => now()->addDays(7)->toDateString(),
            'band_id' => $band->id,
            'status' => 'confirmed',
        ]);

        Sanctum::actingAs($user);

        $response = $this->getJson('/api/mobile/dashboard');
        $response->assertOk();

        $events = $response->json('events');
        $this->assertNotEmpty($events);
        $this->assertArrayHasKey('band', $events[0]);
        $this->assertSame($band->id, $events[0]['band']['id']);
        $this->assertSame('Test Band', $events[0]['band']['name']);
        $this->assertFalse($events[0]['band']['is_personal']);
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=DashboardEventBandFieldTest
```

Expected: FAIL — events don't include a `band` field.

- [ ] **Step 4: Add the `band` field to dashboard event formatting**

In the dashboard controller's event-formatting code, add a `band` key to each event array:

```php
'band' => [
    'id'          => $event->band->id,
    'name'        => $event->band->name,
    'is_personal' => (bool) $event->band->is_personal,
    'logo_url'    => $event->band->logo ? asset('storage/' . $event->band->logo) : null,
],
```

If events come from multiple sources (bookings, rehearsals, `band_events`), add this to each source's formatter. Verify the `band` relation is eager-loaded on the queries that feed the dashboard.

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=DashboardEventBandFieldTest
```

Expected: PASS.

- [ ] **Step 6: Run the full mobile suite for regressions**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=Mobile
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd /home/eddie/github/TTS && git add -A && git commit -m "feat(mobile): include band field on dashboard events"
```

---

### Task 5: Backend — Add `avatar_url` to authenticated user payload

**Files:**
- Modify: `/home/eddie/github/TTS/app/Services/Mobile/TokenService.php` (the `formatUser` method)
- Modify: `/home/eddie/github/TTS/app/Models/User.php` if a `avatarUrl()` accessor doesn't exist
- Test: extend `TokenServiceFormatBandsTest` with a user-format test, or add a new file

**Why:** The mobile `BandIdentityChip` for personal gigs renders the user's avatar. The auth/me payload currently returns only `id`, `name`, `email`.

- [ ] **Step 1: Verify whether the User model already has an avatar field/accessor**

```bash
grep -n 'avatar\|photo\|profile_photo' /home/eddie/github/TTS/app/Models/User.php
ls /home/eddie/github/TTS/database/migrations/ | grep -i 'user\|avatar' | tail -10
```

If an avatar column or accessor exists, use its conventions. If not, this task adds a column-less accessor returning `null` for now (mobile falls back to initials), and the spec's avatar-upload feature is a follow-up.

- [ ] **Step 2: Write the failing test**

Create `/home/eddie/github/TTS/tests/Feature/Mobile/TokenServiceFormatUserTest.php`:

```php
<?php

namespace Tests\Feature\Mobile;

use App\Models\User;
use App\Services\Mobile\TokenService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TokenServiceFormatUserTest extends TestCase
{
    use RefreshDatabase;

    public function test_format_user_includes_avatar_url(): void
    {
        $user = User::factory()->create();
        $service = app(TokenService::class);

        // formatUser is private — invoke via reflection or via the public path
        // that uses it (auth/me endpoint).
        $this->actingAs($user, 'sanctum');
        $response = $this->getJson('/api/mobile/auth/me');

        $response->assertOk();
        $userJson = $response->json('user');

        $this->assertArrayHasKey('avatar_url', $userJson);
        // Default avatar_url is null when user has no uploaded avatar.
        $this->assertNull($userJson['avatar_url']);
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=TokenServiceFormatUserTest
```

Expected: FAIL — `avatar_url` not in the response.

- [ ] **Step 4: Add `avatar_url` to `formatUser`**

In `/home/eddie/github/TTS/app/Services/Mobile/TokenService.php`, update `formatUser`:

```php
private function formatUser(User $user): array
{
    return [
        'id'         => $user->id,
        'name'       => $user->name,
        'email'      => $user->email,
        'avatar_url' => $this->avatarUrlFor($user),
    ];
}

private function avatarUrlFor(User $user): ?string
{
    // Pattern-match existing User model conventions if an avatar accessor or
    // column exists. If not, return null — mobile falls back to initials.
    if (method_exists($user, 'getAvatarUrlAttribute')) {
        return $user->avatar_url;
    }
    if (isset($user->profile_photo_path) && $user->profile_photo_path) {
        return asset('storage/' . $user->profile_photo_path);
    }
    return null;
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=TokenServiceFormatUserTest
```

Expected: PASS.

- [ ] **Step 6: Run the full mobile suite**

```bash
cd /home/eddie/github/TTS && php artisan test --filter=Mobile
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Services/Mobile/TokenService.php tests/Feature/Mobile/TokenServiceFormatUserTest.php && git commit -m "feat(mobile): include avatar_url in formatUser"
```

---

### Task 6: Mobile — Add `isPersonal` and `logoUrl` to `BandSummary`

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/auth/data/models/band_summary.dart`
- Test: `/home/eddie/github/tts_bandmate/test/models/band_summary_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `/home/eddie/github/tts_bandmate/test/models/band_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';

void main() {
  group('BandSummary.fromJson', () {
    test('parses isPersonal=true', () {
      final band = BandSummary.fromJson({
        'id': 1,
        'name': 'Personal',
        'is_owner': true,
        'is_personal': true,
        'logo_url': null,
      });
      expect(band.isPersonal, isTrue);
      expect(band.logoUrl, isNull);
    });

    test('parses isPersonal=false', () {
      final band = BandSummary.fromJson({
        'id': 2,
        'name': 'Real Band',
        'is_owner': false,
        'is_personal': false,
        'logo_url': 'https://example.com/logo.png',
      });
      expect(band.isPersonal, isFalse);
      expect(band.logoUrl, equals('https://example.com/logo.png'));
    });

    test('defaults isPersonal to false when missing', () {
      final band = BandSummary.fromJson({
        'id': 3,
        'name': 'Legacy',
        'is_owner': false,
      });
      expect(band.isPersonal, isFalse);
      expect(band.logoUrl, isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/models/band_summary_test.dart
```

Expected: FAIL — `isPersonal` getter doesn't exist on `BandSummary`.

- [ ] **Step 3: Add the new fields to `BandSummary`**

Replace the contents of `/home/eddie/github/tts_bandmate/lib/features/auth/data/models/band_summary.dart`:

```dart
class BandSummary {
  const BandSummary({
    required this.id,
    required this.name,
    required this.isOwner,
    this.isPersonal = false,
    this.logoUrl,
  });

  final int id;
  final String name;
  final bool isOwner;
  final bool isPersonal;
  final String? logoUrl;

  factory BandSummary.fromJson(Map<String, dynamic> json) {
    return BandSummary(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      isOwner: (json['is_owner'] as bool?) ?? false,
      isPersonal: (json['is_personal'] as bool?) ?? false,
      logoUrl: json['logo_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'is_owner': isOwner,
        'is_personal': isPersonal,
        'logo_url': logoUrl,
      };

  @override
  String toString() =>
      'BandSummary(id: $id, name: $name, isOwner: $isOwner, isPersonal: $isPersonal)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BandSummary &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/models/band_summary_test.dart
```

Expected: PASS (3 tests).

- [ ] **Step 5: Run analyzer + full test suite for regressions**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: no analyzer errors, all tests pass. Existing test fixtures using `const BandSummary(...)` keep working because `isPersonal` defaults to `false`.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/auth/data/models/band_summary.dart test/models/band_summary_test.dart && git commit -m "feat(auth): add isPersonal and logoUrl to BandSummary"
```

---

### Task 7: Mobile — Add `avatarUrl` to `AuthUser`

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/auth/data/models/auth_user.dart`
- Test: `/home/eddie/github/tts_bandmate/test/models/auth_user_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `/home/eddie/github/tts_bandmate/test/models/auth_user_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';

void main() {
  group('AuthUser.fromJson', () {
    test('parses avatarUrl when present', () {
      final user = AuthUser.fromJson({
        'id': 1,
        'name': 'Eddie',
        'email': 'e@e.com',
        'avatar_url': 'https://example.com/me.png',
      });
      expect(user.avatarUrl, equals('https://example.com/me.png'));
    });

    test('defaults avatarUrl to null when missing', () {
      final user = AuthUser.fromJson({
        'id': 2,
        'name': 'Sam',
        'email': 's@e.com',
      });
      expect(user.avatarUrl, isNull);
    });

    test('round-trips via toJson/fromJsonString', () {
      const original = AuthUser(
        id: 3,
        name: 'X',
        email: 'x@x.com',
        avatarUrl: 'https://example.com/x.png',
      );
      final round = AuthUser.fromJsonString(original.toJsonString());
      expect(round.avatarUrl, equals('https://example.com/x.png'));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/models/auth_user_test.dart
```

Expected: FAIL — `avatarUrl` not on `AuthUser`.

- [ ] **Step 3: Add the field**

Replace `/home/eddie/github/tts_bandmate/lib/features/auth/data/models/auth_user.dart`:

```dart
import 'dart:convert';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
  });

  final int id;
  final String name;
  final String email;
  final String? avatarUrl;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'avatar_url': avatarUrl,
      };

  String toJsonString() => jsonEncode(toJson());

  factory AuthUser.fromJsonString(String jsonString) =>
      AuthUser.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

  @override
  String toString() =>
      'AuthUser(id: $id, name: $name, email: $email)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email;

  @override
  int get hashCode => Object.hash(id, email);
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/models/auth_user_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run analyzer + full test suite for regressions**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS. The `_fakeUser` fixture in `test/auth_provider_test.dart` keeps working because `avatarUrl` defaults to `null`.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/auth/data/models/auth_user.dart test/models/auth_user_test.dart && git commit -m "feat(auth): add avatarUrl to AuthUser"
```

---

### Task 8: Mobile — Add nested `band` field to `BookingSummary`

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/bookings/data/models/booking_summary.dart`
- Test: `/home/eddie/github/tts_bandmate/test/models/booking_summary_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `/home/eddie/github/tts_bandmate/test/models/booking_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';

void main() {
  group('BookingSummary.fromJson', () {
    test('parses nested band field for non-personal band', () {
      final booking = BookingSummary.fromJson({
        'id': 1,
        'name': 'Wedding',
        'date': '2026-06-01',
        'is_paid': false,
        'contacts': [],
        'band': {
          'id': 10,
          'name': 'Test Band',
          'is_personal': false,
          'logo_url': 'https://example.com/logo.png',
        },
      });
      expect(booking.band, isNotNull);
      expect(booking.band!.id, equals(10));
      expect(booking.band!.name, equals('Test Band'));
      expect(booking.band!.isPersonal, isFalse);
      expect(booking.band!.logoUrl, equals('https://example.com/logo.png'));
    });

    test('parses nested band field for personal band', () {
      final booking = BookingSummary.fromJson({
        'id': 2,
        'name': 'Church',
        'date': '2026-06-02',
        'is_paid': false,
        'contacts': [],
        'band': {
          'id': 99,
          'name': "Eddie's Band",
          'is_personal': true,
          'logo_url': null,
        },
      });
      expect(booking.band, isNotNull);
      expect(booking.band!.isPersonal, isTrue);
      expect(booking.band!.logoUrl, isNull);
    });

    test('tolerates missing band field (legacy payloads)', () {
      final booking = BookingSummary.fromJson({
        'id': 3,
        'name': 'Old',
        'date': '2026-06-03',
        'is_paid': false,
        'contacts': [],
      });
      expect(booking.band, isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/models/booking_summary_test.dart
```

Expected: FAIL — `band` getter doesn't exist on `BookingSummary`.

- [ ] **Step 3: Add the `band` field**

In `/home/eddie/github/tts_bandmate/lib/features/bookings/data/models/booking_summary.dart`, replace the file contents:

```dart
import 'package:intl/intl.dart';
import '../../../auth/data/models/band_summary.dart';
import 'booking_contact.dart';

class BookingSummary {
  const BookingSummary({
    required this.id,
    required this.name,
    required this.date,
    this.startTime,
    this.endTime,
    this.venueName,
    this.venueAddress,
    this.status,
    this.price,
    this.eventTypeId,
    this.notes,
    this.amountPaid,
    this.amountDue,
    required this.isPaid,
    required this.contacts,
    this.band,
  });

  final int id;
  final String name;
  final String date;
  final String? startTime;
  final String? endTime;
  final String? venueName;
  final String? venueAddress;
  final String? status;
  final String? price;
  final int? eventTypeId;
  final String? notes;
  final String? amountPaid;
  final String? amountDue;
  final bool isPaid;
  final List<BookingContact> contacts;

  /// Optional nested band identity. Present on the new `/me/bookings` payload
  /// and on per-band `/bookings` responses; absent on legacy payloads.
  final BandSummary? band;

  factory BookingSummary.fromJson(Map<String, dynamic> json) {
    final rawContacts = json['contacts'];
    final contacts = rawContacts is List
        ? rawContacts
            .cast<Map<String, dynamic>>()
            .map(BookingContact.fromJson)
            .toList()
        : <BookingContact>[];

    final rawBand = json['band'];
    final band = rawBand is Map<String, dynamic>
        ? BandSummary.fromJson(rawBand)
        : null;

    return BookingSummary(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      date: json['date'] as String,
      startTime: json['start_time'] as String?,
      endTime: json['end_time'] as String?,
      venueName: json['venue_name'] as String?,
      venueAddress: json['venue_address'] as String?,
      status: json['status'] as String?,
      price: json['price'] as String?,
      eventTypeId: json['event_type_id'] == null
          ? null
          : (json['event_type_id'] as num).toInt(),
      notes: json['notes'] as String?,
      amountPaid: json['amount_paid'] as String?,
      amountDue: json['amount_due'] as String?,
      isPaid: (json['is_paid'] as bool?) ?? false,
      contacts: contacts,
      band: band,
    );
  }

  DateTime get parsedDate {
    try {
      return DateTime.parse(date);
    } catch (_) {
      return DateTime.now();
    }
  }

  String get displayPrice {
    if (price == null) return '—';
    final parsed = double.tryParse(price!);
    if (parsed == null) return price!;
    return NumberFormat.currency(symbol: '\$').format(parsed);
  }

  @override
  String toString() => 'BookingSummary(id: $id, name: $name, date: $date)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingSummary &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
```

**Note:** `BandSummary` is reused as the `band` type — there's no need for a separate model. The fact that `BandSummary.isOwner` is irrelevant in this context is OK; it'll come back as `false` from the API since the booking response's `band` object doesn't include ownership info, but the chip widget only reads `id`, `name`, `logoUrl`, `isPersonal`.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/models/booking_summary_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run analyzer + full test suite for regressions**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/data/models/booking_summary.dart test/models/booking_summary_test.dart && git commit -m "feat(bookings): add nested band field to BookingSummary"
```

---

### Task 9: Mobile — Add nested `band` field to `EventSummary`

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/events/data/models/event_summary.dart`
- Test: `/home/eddie/github/tts_bandmate/test/models/event_summary_test.dart` (extend existing file)

- [ ] **Step 1: Write the failing test**

Append to `/home/eddie/github/tts_bandmate/test/models/event_summary_test.dart` (or add a new `group` if the file exists). If it doesn't exist, create it with this content:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

void main() {
  group('EventSummary.fromJson — band field', () {
    test('parses nested band when present', () {
      final event = EventSummary.fromJson({
        'key': 'evt-1',
        'title': 'A Gig',
        'date': '2026-06-01',
        'event_source': 'booking',
        'band': {
          'id': 7,
          'name': 'Test Band',
          'is_personal': false,
          'logo_url': null,
        },
      });
      expect(event.band, isNotNull);
      expect(event.band!.id, equals(7));
      expect(event.band!.isPersonal, isFalse);
    });

    test('tolerates missing band field', () {
      final event = EventSummary.fromJson({
        'key': 'evt-2',
        'title': 'Old',
        'date': '2026-06-02',
        'event_source': 'band_event',
      });
      expect(event.band, isNull);
    });

    test('parses personal band', () {
      final event = EventSummary.fromJson({
        'key': 'evt-3',
        'title': 'Church',
        'date': '2026-06-03',
        'event_source': 'booking',
        'band': {
          'id': 99,
          'name': "Eddie's Band",
          'is_personal': true,
          'logo_url': null,
        },
      });
      expect(event.band!.isPersonal, isTrue);
    });
  });
}
```

If `test/models/event_summary_test.dart` already exists, add the `group(...)` block inside the existing `void main()`.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/models/event_summary_test.dart
```

Expected: FAIL — `band` getter doesn't exist.

- [ ] **Step 3: Add the `band` field to `EventSummary`**

Replace `/home/eddie/github/tts_bandmate/lib/features/events/data/models/event_summary.dart`:

```dart
import '../../../auth/data/models/band_summary.dart';

class EventSummary {
  const EventSummary({
    this.id,
    required this.key,
    required this.title,
    required this.date,
    this.time,
    this.eventType,
    required this.eventSource,
    this.venueName,
    this.venueAddress,
    this.status,
    this.liveSessionId,
    this.rosterStatus,
    this.band,
  });

  final int? id;
  final String key;
  final String title;
  final String date;
  final String? time;
  final String? eventType;
  final String eventSource;
  final String? venueName;
  final String? venueAddress;
  final String? status;
  final int? liveSessionId;
  final String? rosterStatus;

  /// Optional nested band identity for rendering a band/personal chip on the
  /// dashboard. Absent on legacy payloads.
  final BandSummary? band;

  factory EventSummary.fromJson(Map<String, dynamic> json) {
    final rawBand = json['band'];
    final band = rawBand is Map<String, dynamic>
        ? BandSummary.fromJson(rawBand)
        : null;

    return EventSummary(
      id: json['id'] == null ? null : (json['id'] as num).toInt(),
      key: json['key'] as String,
      title: json['title'] as String,
      date: json['date'] as String,
      time: json['time'] as String?,
      eventType: json['event_type'] as String?,
      eventSource: json['event_source'] as String? ?? 'band_event',
      venueName: json['venue_name'] as String?,
      venueAddress: json['venue_address'] as String?,
      status: json['status'] as String?,
      liveSessionId: json['live_session_id'] == null
          ? null
          : (json['live_session_id'] as num).toInt(),
      rosterStatus: json['roster_status'] as String?,
      band: band,
    );
  }

  String? get gigIconPath {
    if (isRehearsal) return null;
    final type = eventType?.toLowerCase().replaceAll(' ', '') ?? '';
    const base = 'assets/images/gigIcons';
    return switch (type) {
      'bar' => '$base/bar.png',
      'casino' => '$base/casino.png',
      'charity' => '$base/charity.png',
      'festival' => '$base/festival.png',
      'mardigras' => '$base/mardiGras.png',
      'private' => '$base/private.png',
      'special' => '$base/special.png',
      'wedding' => '$base/wedding.png',
      _ => '$base/other.png',
    };
  }

  bool get isRehearsal =>
      eventSource == 'rehearsal' || eventSource == 'rehearsal_schedule';

  DateTime get parsedDate {
    try {
      return DateTime.parse(date);
    } catch (_) {
      return DateTime.now();
    }
  }

  @override
  String toString() =>
      'EventSummary(id: $id, key: $key, title: $title, date: $date)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventSummary &&
          runtimeType == other.runtimeType &&
          key == other.key;

  @override
  int get hashCode => key.hashCode;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/models/event_summary_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run analyzer + full test suite for regressions**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/events/data/models/event_summary.dart test/models/event_summary_test.dart && git commit -m "feat(events): add nested band field to EventSummary"
```

---

### Task 10: Mobile — Add `mobileMeBookings` API endpoint constant + repository method

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/core/network/api_endpoints.dart`
- Modify: `/home/eddie/github/tts_bandmate/lib/features/bookings/data/bookings_repository.dart`
- Test: `/home/eddie/github/tts_bandmate/test/features/bookings/bookings_repository_user_bookings_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `/home/eddie/github/tts_bandmate/test/features/bookings/bookings_repository_user_bookings_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<void>? cancel) =>
      handler(options);
}

ResponseBody _json(int status, Object body) {
  final encoded = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(encoded, status, headers: {
    'content-type': ['application/json'],
  });
}

void main() {
  test('getAllUserBookings hits /me/bookings and parses bookings', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async {
        expect(req.method, equals('GET'));
        expect(req.path, equals('/api/mobile/me/bookings'));
        return _json(200, {
          'bookings': [
            {
              'id': 1,
              'name': 'Wedding',
              'date': '2026-06-01',
              'is_paid': false,
              'contacts': [],
              'band': {
                'id': 10,
                'name': 'Test Band',
                'is_personal': false,
                'logo_url': null,
              },
            },
            {
              'id': 2,
              'name': 'Church',
              'date': '2026-06-02',
              'is_paid': false,
              'contacts': [],
              'band': {
                'id': 99,
                'name': "Eddie's Band",
                'is_personal': true,
                'logo_url': null,
              },
            },
          ],
        });
      });

    final repo = BookingsRepository(dio);
    final results = await repo.getAllUserBookings();

    expect(results, hasLength(2));
    expect(results[0].band!.id, equals(10));
    expect(results[1].band!.isPersonal, isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/bookings_repository_user_bookings_test.dart
```

Expected: FAIL — `getAllUserBookings` method doesn't exist; `mobileMeBookings` constant doesn't exist.

- [ ] **Step 3: Add the API endpoint constant**

In `/home/eddie/github/tts_bandmate/lib/core/network/api_endpoints.dart`, add after the existing `mobileMe` constant:

```dart
  static const String mobileMeBookings = '/api/mobile/me/bookings';
```

- [ ] **Step 4: Add the repository method**

In `/home/eddie/github/tts_bandmate/lib/features/bookings/data/bookings_repository.dart`, after the `getBandBookings` method, add:

```dart
  /// Fetches bookings across all bands the authenticated user belongs to.
  ///
  /// Used by the multi-band Bookings tab. Filters mirror [getBandBookings].
  Future<List<BookingSummary>> getAllUserBookings({
    String? status,
    bool upcomingOnly = false,
    int? year,
  }) async {
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (upcomingOnly) queryParams['upcoming'] = '1';
    if (year != null) queryParams['year'] = year.toString();

    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileMeBookings,
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final data = response.data!;
    final rawList = data['bookings'] as List<dynamic>;
    return rawList
        .cast<Map<String, dynamic>>()
        .map(BookingSummary.fromJson)
        .toList();
  }
```

Verify the file's existing import of `ApiEndpoints` (it's referenced via `package:tts_bandmate/core/providers/core_providers.dart` in this file — confirm and adjust). If `ApiEndpoints` isn't imported, add:

```dart
import '../../../core/network/api_endpoints.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/bookings_repository_user_bookings_test.dart
```

Expected: PASS.

- [ ] **Step 6: Run analyzer + full test suite**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/core/network/api_endpoints.dart lib/features/bookings/data/bookings_repository.dart test/features/bookings/bookings_repository_user_bookings_test.dart && git commit -m "feat(bookings): add /me/bookings repository method"
```

---

### Task 11: Mobile — Add `userBookingsProvider`

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/bookings/providers/bookings_provider.dart`
- Test: `/home/eddie/github/tts_bandmate/test/providers/user_bookings_provider_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `/home/eddie/github/tts_bandmate/test/providers/user_bookings_provider_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) =>
      handler(o);
}

ResponseBody _json(int s, Object b) =>
    ResponseBody.fromBytes(utf8.encode(jsonEncode(b)), s, headers: {
      'content-type': ['application/json'],
    });

void main() {
  test('userBookingsProvider fetches via /me/bookings', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async {
        expect(req.path, equals('/api/mobile/me/bookings'));
        return _json(200, {
          'bookings': [
            {
              'id': 1,
              'name': 'Gig',
              'date': '2026-06-01',
              'is_paid': false,
              'contacts': [],
              'band': {
                'id': 10,
                'name': 'A',
                'is_personal': false,
                'logo_url': null,
              },
            },
          ],
        });
      });

    final container = ProviderContainer(overrides: [
      bookingsRepositoryProvider.overrideWithValue(BookingsRepository(dio)),
    ]);
    addTearDown(container.dispose);

    final result = await container
        .read(userBookingsProvider(const UserBookingsParams()).future);

    expect(result, hasLength(1));
    expect(result.first.band!.id, equals(10));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/providers/user_bookings_provider_test.dart
```

Expected: FAIL — `userBookingsProvider` and `UserBookingsParams` don't exist.

- [ ] **Step 3: Add the provider**

In `/home/eddie/github/tts_bandmate/lib/features/bookings/providers/bookings_provider.dart`, add after the existing `bandBookingsProvider`:

```dart
// ── User bookings (multi-band) ────────────────────────────────────────────────

class UserBookingsParams {
  const UserBookingsParams({
    this.status,
    this.upcomingOnly = false,
    this.year,
  });

  final String? status;
  final bool upcomingOnly;
  final int? year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserBookingsParams &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          upcomingOnly == other.upcomingOnly &&
          year == other.year;

  @override
  int get hashCode => Object.hash(status, upcomingOnly, year);
}

final userBookingsProvider =
    FutureProvider.family<List<BookingSummary>, UserBookingsParams>(
  (ref, params) {
    final repo = ref.watch(bookingsRepositoryProvider);
    return repo.getAllUserBookings(
      status: params.status,
      upcomingOnly: params.upcomingOnly,
      year: params.year,
    );
  },
);
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/providers/user_bookings_provider_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run analyzer + full test suite**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/providers/bookings_provider.dart test/providers/user_bookings_provider_test.dart && git commit -m "feat(bookings): add userBookingsProvider for multi-band view"
```

---

### Task 12: Mobile — Add `personalBandProvider`

**Files:**
- Create: `/home/eddie/github/tts_bandmate/lib/shared/providers/personal_band_provider.dart`
- Test: `/home/eddie/github/tts_bandmate/test/providers/personal_band_provider_test.dart` (new)

The provider derives the personal band from `authProvider`'s bands list and exposes `ensureExists()` which calls `bandsProvider.notifier.goSolo()` (already implemented) when no personal band exists.

- [ ] **Step 1: Write the failing tests**

Create `/home/eddie/github/tts_bandmate/test/providers/personal_band_provider_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/network/api_client.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/shared/providers/personal_band_provider.dart';

class _FakeSecureStorage extends SecureStorage {
  _FakeSecureStorage() : super(const FlutterSecureStorage());
  final Map<String, String?> _m = {};
  @override Future<String?> readToken() async => _m['t'];
  @override Future<void> writeToken(String t) async => _m['t'] = t;
  @override Future<void> deleteToken() async => _m.remove('t');
  @override Future<String?> readBandId() async => _m['b'];
  @override Future<void> writeBandId(String id) async => _m['b'] = id;
  @override Future<void> deleteBandId() async => _m.remove('b');
  @override Future<String?> readUser() async => _m['u'];
  @override Future<void> writeUser(String u) async => _m['u'] = u;
  @override Future<void> clear() async => _m.clear();
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override void close({bool force = false}) {}
  @override Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) => handler(o);
}

ResponseBody _json(int s, Object b) =>
    ResponseBody.fromBytes(utf8.encode(jsonEncode(b)), s, headers: {
      'content-type': ['application/json'],
    });

class _StubApiClient extends ApiClient {
  _StubApiClient({required super.storage, required Dio dio}) : _stub = dio;
  final Dio _stub;
  @override Dio get dio => _stub;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RouteStorage routeStorage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    routeStorage = RouteStorage(await SharedPreferences.getInstance());
  });

  ProviderContainer makeContainer({
    required _FakeSecureStorage storage,
    required Dio dio,
    required AuthState initialAuth,
  }) {
    final container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(_StubApiClient(storage: storage, dio: dio)),
      routeStorageProvider.overrideWith((_) async => routeStorage),
    ]);
    // Manually inject auth state so we don't have to drive a real login.
    container.read(authProvider.notifier).state = AsyncValue.data(initialAuth);
    return container;
  }

  test('returns existing personal band without API call', () async {
    final personal = const BandSummary(
      id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true,
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((_) async => fail('Should not call API'));

    final container = makeContainer(
      storage: _FakeSecureStorage(),
      dio: dio,
      initialAuth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [
          const BandSummary(id: 10, name: 'Real', isOwner: true),
          personal,
        ],
      ),
    );
    addTearDown(container.dispose);

    final result = await container
        .read(personalBandProvider.notifier)
        .ensureExists();

    expect(result.id, equals(99));
    expect(result.isPersonal, isTrue);
  });

  test('creates personal band when missing and API succeeds', () async {
    int soloCalls = 0;
    int meCalls = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async {
        if (req.path == '/api/mobile/bands/solo' && req.method == 'POST') {
          soloCalls++;
          return _json(201, {
            'bands': [
              {'id': 10, 'name': 'Real', 'is_owner': true, 'is_personal': false},
              {'id': 99, 'name': "Eddie's Band", 'is_owner': true, 'is_personal': true},
            ],
          });
        }
        if (req.path == '/api/mobile/auth/me' && req.method == 'GET') {
          meCalls++;
          return _json(200, {
            'user': {'id': 1, 'name': 'Eddie', 'email': 'e@e.com'},
            'bands': [
              {'id': 10, 'name': 'Real', 'is_owner': true, 'is_personal': false},
              {'id': 99, 'name': "Eddie's Band", 'is_owner': true, 'is_personal': true},
            ],
          });
        }
        return _json(404, {'message': 'unexpected ${req.method} ${req.path}'});
      });

    final storage = _FakeSecureStorage();
    await storage.writeToken('test-token');

    final container = makeContainer(
      storage: storage,
      dio: dio,
      initialAuth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [const BandSummary(id: 10, name: 'Real', isOwner: true)],
      ),
    );
    addTearDown(container.dispose);

    final result = await container
        .read(personalBandProvider.notifier)
        .ensureExists();

    expect(soloCalls, equals(1));
    expect(meCalls, equals(1), reason: 'auth should refresh after solo');
    expect(result.id, equals(99));
    expect(result.isPersonal, isTrue);

    // Verify the auth state now contains the personal band.
    final auth = container.read(authProvider).value;
    expect(auth, isA<AuthAuthenticated>());
    final updatedBands = (auth as AuthAuthenticated).bands;
    expect(updatedBands.any((b) => b.isPersonal), isTrue);
  });

  test('propagates error and leaves state unchanged when API fails', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async => _json(500, {'message': 'server fire'}));

    final storage = _FakeSecureStorage();
    await storage.writeToken('test-token');

    final container = makeContainer(
      storage: storage,
      dio: dio,
      initialAuth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [const BandSummary(id: 10, name: 'Real', isOwner: true)],
      ),
    );
    addTearDown(container.dispose);

    expect(
      () => container.read(personalBandProvider.notifier).ensureExists(),
      throwsA(anything),
    );

    // Auth state still has just the one real band.
    final auth = container.read(authProvider).value as AuthAuthenticated;
    expect(auth.bands, hasLength(1));
    expect(auth.bands.any((b) => b.isPersonal), isFalse);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/providers/personal_band_provider_test.dart
```

Expected: FAIL — `personalBandProvider` doesn't exist.

- [ ] **Step 3: Create the provider**

Create `/home/eddie/github/tts_bandmate/lib/shared/providers/personal_band_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/models/band_summary.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/bands/providers/bands_provider.dart';

/// Riverpod notifier exposing the user's personal band, creating one lazily
/// when needed via `POST /api/mobile/bands/solo`.
///
/// The personal band is hidden from band-selector / band-switcher UIs but
/// shows up as items in aggregated lists (Dashboard, Bookings tab) with a
/// personal-treatment chip (user's avatar + "Personal").
class PersonalBandNotifier extends Notifier<void> {
  @override
  void build() {}

  /// The user's personal band, derived from [authProvider]. Returns null if
  /// the user has not yet created (or had auto-created) a personal band.
  BandSummary? get personalBand {
    final auth = ref.read(authProvider).value;
    if (auth is! AuthAuthenticated) return null;
    for (final band in auth.bands) {
      if (band.isPersonal) return band;
    }
    return null;
  }

  /// Returns the user's personal band, creating one server-side via
  /// `POST /bands/solo` if needed. After creation the auth state is
  /// refreshed so the rest of the app sees the new band.
  ///
  /// Throws if the user is not authenticated, or if the API call fails.
  Future<BandSummary> ensureExists() async {
    final existing = personalBand;
    if (existing != null) return existing;

    await ref.read(bandsProvider.notifier).goSolo();

    final created = personalBand;
    if (created == null) {
      throw StateError(
        'Personal band creation succeeded but band did not appear in auth state',
      );
    }
    return created;
  }
}

final personalBandProvider =
    NotifierProvider<PersonalBandNotifier, void>(() => PersonalBandNotifier());
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/providers/personal_band_provider_test.dart
```

Expected: PASS (3 tests).

- [ ] **Step 5: Run analyzer + full test suite**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/shared/providers/personal_band_provider.dart test/providers/personal_band_provider_test.dart && git commit -m "feat: add personalBandProvider with lazy creation"
```

---

### Task 13: Mobile — Build the `BandIdentityChip` widget

**Files:**
- Create: `/home/eddie/github/tts_bandmate/lib/shared/widgets/band_identity_chip.dart`
- Test: `/home/eddie/github/tts_bandmate/test/widgets/band_identity_chip_test.dart` (new)

The widget reads the authenticated user (for personal-band avatar) directly from `authProvider`, so callers just pass a `BandSummary`.

- [ ] **Step 1: Write the failing tests**

Create `/home/eddie/github/tts_bandmate/test/widgets/band_identity_chip_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/shared/widgets/band_identity_chip.dart';

Widget _wrap(Widget child, {required AuthState auth}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(() {
        return _FixedAuthNotifier(auth);
      }),
    ],
    child: CupertinoApp(home: CupertinoPageScaffold(child: child)),
  );
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;

  @override
  Future<AuthState> build() async => _fixed;
}

void main() {
  testWidgets('renders band name for non-personal band', (tester) async {
    const band = BandSummary(
      id: 10, name: 'The Rocking Eds', isOwner: true, isPersonal: false,
    );
    await tester.pumpWidget(_wrap(
      const BandIdentityChip(band: band),
      auth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: const [band],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('The Rocking Eds'), findsOneWidget);
    expect(find.text('Personal'), findsNothing);
  });

  testWidgets('renders "Personal" label for personal band', (tester) async {
    const band = BandSummary(
      id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true,
    );
    await tester.pumpWidget(_wrap(
      const BandIdentityChip(band: band),
      auth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: const [band],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text("Eddie's Band"), findsNothing);
  });

  testWidgets('renders band initials when no logoUrl', (tester) async {
    const band = BandSummary(
      id: 10, name: 'Acme', isOwner: true, isPersonal: false,
    );
    await tester.pumpWidget(_wrap(
      const BandIdentityChip(band: band),
      auth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: const [band],
      ),
    ));
    await tester.pumpAndSettle();
    // Expect the first letter of the band name to appear in the avatar.
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('renders user initials for personal band when no avatar', (tester) async {
    const band = BandSummary(
      id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true,
    );
    await tester.pumpWidget(_wrap(
      const BandIdentityChip(band: band),
      auth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie Mullins', email: 'e@e.com'),
        bands: const [band],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('E'), findsOneWidget); // user's first initial
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/widgets/band_identity_chip_test.dart
```

Expected: FAIL — `BandIdentityChip` doesn't exist.

- [ ] **Step 3: Create the widget**

Create `/home/eddie/github/tts_bandmate/lib/shared/widgets/band_identity_chip.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/models/auth_user.dart';
import '../../features/auth/data/models/band_summary.dart';
import '../../features/auth/providers/auth_provider.dart';

/// A horizontal `[avatar] [label]` row identifying a band — or, for personal
/// bands, the authenticated user. Used on Dashboard cards, Bookings tab cards,
/// and the booking-detail header.
class BandIdentityChip extends ConsumerWidget {
  const BandIdentityChip({
    super.key,
    required this.band,
    this.size = 18,
    this.textStyle,
  });

  final BandSummary band;

  /// Avatar diameter in logical pixels. Defaults to a compact size suitable
  /// for cards.
  final double size;

  /// Optional text style override for the label.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (band.isPersonal) {
      final auth = ref.watch(authProvider).value;
      final user = (auth is AuthAuthenticated) ? auth.user : null;
      return _Row(
        avatar: _Avatar(
          imageUrl: user?.avatarUrl,
          fallbackInitial: _initial(user?.name ?? 'You'),
          size: size,
        ),
        label: 'Personal',
        textStyle: textStyle,
      );
    }
    return _Row(
      avatar: _Avatar(
        imageUrl: band.logoUrl,
        fallbackInitial: _initial(band.name),
        size: size,
      ),
      label: band.name,
      textStyle: textStyle,
    );
  }

  static String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.avatar, required this.label, this.textStyle});
  final Widget avatar;
  final String label;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        avatar,
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle ??
                TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.imageUrl,
    required this.fallbackInitial,
    required this.size,
  });

  final String? imageUrl;
  final String fallbackInitial;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CupertinoColors.systemBlue
            .resolveFrom(context)
            .withValues(alpha: 0.15),
        image: imageUrl != null
            ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: imageUrl != null
          ? null
          : Center(
              child: Text(
                fallbackInitial,
                style: TextStyle(
                  fontSize: size * 0.55,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                ),
              ),
            ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/widgets/band_identity_chip_test.dart
```

Expected: PASS (4 tests).

- [ ] **Step 5: Run analyzer + full test suite**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/shared/widgets/band_identity_chip.dart test/widgets/band_identity_chip_test.dart && git commit -m "feat(shared): add BandIdentityChip widget"
```

---

### Task 14: Mobile — Filter personal band from `BandSelectorScreen`

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/auth/screens/band_selector_screen.dart:43-49`
- Test: `/home/eddie/github/tts_bandmate/test/widgets/band_selector_filters_personal_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `/home/eddie/github/tts_bandmate/test/widgets/band_selector_filters_personal_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/auth/screens/band_selector_screen.dart';

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override
  Future<AuthState> build() async => _fixed;
}

void main() {
  testWidgets('hides personal band from the band-selector list', (tester) async {
    final authState = AuthAuthenticated(
      user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
      bands: const [
        BandSummary(id: 10, name: 'The Real Band', isOwner: true),
        BandSummary(id: 11, name: 'Side Project', isOwner: false),
        BandSummary(
          id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true,
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [authProvider.overrideWith(() => _FixedAuthNotifier(authState))],
      child: const CupertinoApp(home: BandSelectorScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('The Real Band'), findsOneWidget);
    expect(find.text('Side Project'), findsOneWidget);
    expect(find.text("Eddie's Band"), findsNothing,
        reason: 'Personal band must be hidden from the selector');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/widgets/band_selector_filters_personal_test.dart
```

Expected: FAIL — current selector shows all bands including personal.

- [ ] **Step 3: Filter out personal bands**

In `/home/eddie/github/tts_bandmate/lib/features/auth/screens/band_selector_screen.dart`, find the `final bands = authState.bands;` line and replace the surrounding logic. Replace lines 43–62 (the `final bands = ...` through the `ListView.separated` body) with:

```dart
            final bands = authState.bands.where((b) => !b.isPersonal).toList();

            if (bands.isEmpty) {
              // Router guard redirects to /bands which shows PathSelectionScreen.
              // This branch is a safety fallback only.
              return const Center(child: CupertinoActivityIndicator());
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: bands.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final band = bands[index];
                return _BandTile(
                  band: band,
                  onTap: () => _selectBand(context, ref, band),
                );
              },
            );
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/widgets/band_selector_filters_personal_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run analyzer + full test suite**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/auth/screens/band_selector_screen.dart test/widgets/band_selector_filters_personal_test.dart && git commit -m "feat(auth): hide personal band from band selector"
```

---

### Task 15: Mobile — Build the `CreateBookingSheet` widget

**Files:**
- Create: `/home/eddie/github/tts_bandmate/lib/features/bookings/widgets/create_booking_sheet.dart`
- Test: `/home/eddie/github/tts_bandmate/test/widgets/create_booking_sheet_test.dart` (new)

The sheet shows real bands at the top, a divider, and a "Personal gig" row. Tapping a real band invokes a callback with the band ID; tapping "Personal gig" calls `personalBandProvider.ensureExists()` and then invokes the callback with the resulting band ID. On error during `ensureExists`, an inline error message appears.

- [ ] **Step 1: Write the failing tests**

Create `/home/eddie/github/tts_bandmate/test/widgets/create_booking_sheet_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/network/api_client.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/bookings/widgets/create_booking_sheet.dart';

class _FakeSecureStorage extends SecureStorage {
  _FakeSecureStorage() : super(const FlutterSecureStorage());
  final Map<String, String?> _m = {};
  @override Future<String?> readToken() async => _m['t'];
  @override Future<void> writeToken(String t) async => _m['t'] = t;
  @override Future<void> deleteToken() async => _m.remove('t');
  @override Future<String?> readBandId() async => _m['b'];
  @override Future<void> writeBandId(String id) async => _m['b'] = id;
  @override Future<void> deleteBandId() async => _m.remove('b');
  @override Future<String?> readUser() async => _m['u'];
  @override Future<void> writeUser(String u) async => _m['u'] = u;
  @override Future<void> clear() async => _m.clear();
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override void close({bool force = false}) {}
  @override Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) => handler(o);
}

ResponseBody _json(int s, Object b) =>
    ResponseBody.fromBytes(utf8.encode(jsonEncode(b)), s, headers: {
      'content-type': ['application/json'],
    });

class _StubApiClient extends ApiClient {
  _StubApiClient({required super.storage, required Dio dio}) : _stub = dio;
  final Dio _stub;
  @override Dio get dio => _stub;
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override Future<AuthState> build() async => _fixed;
}

Future<Widget> _wrap({
  required Widget child,
  required AuthState auth,
  required Dio dio,
  required _FakeSecureStorage storage,
}) async {
  SharedPreferences.setMockInitialValues({});
  final routeStorage = RouteStorage(await SharedPreferences.getInstance());
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(_StubApiClient(storage: storage, dio: dio)),
      routeStorageProvider.overrideWith((_) async => routeStorage),
      authProvider.overrideWith(() => _FixedAuthNotifier(auth)),
    ],
    child: CupertinoApp(home: CupertinoPageScaffold(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders real bands and Personal gig row', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: selected.add),
      auth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: const [
          BandSummary(id: 10, name: 'The Real Band', isOwner: true),
          BandSummary(id: 11, name: 'Side Project', isOwner: false),
        ],
      ),
      dio: Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = _StubAdapter((_) async => _json(200, {})),
      storage: _FakeSecureStorage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('The Real Band'), findsOneWidget);
    expect(find.text('Side Project'), findsOneWidget);
    expect(find.text('Personal gig'), findsOneWidget);
  });

  testWidgets('hides real-bands section when user has no real bands', (tester) async {
    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: (_) {}),
      auth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: const [
          BandSummary(id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true),
        ],
      ),
      dio: Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = _StubAdapter((_) async => _json(200, {})),
      storage: _FakeSecureStorage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Personal gig'), findsOneWidget);
    expect(find.text("Eddie's Band"), findsNothing,
        reason: 'Personal band should not be listed as a real band');
  });

  testWidgets('tapping a real band invokes callback with that band id', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: selected.add),
      auth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: const [BandSummary(id: 10, name: 'The Real Band', isOwner: true)],
      ),
      dio: Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = _StubAdapter((_) async => _json(200, {})),
      storage: _FakeSecureStorage(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('The Real Band'));
    await tester.pumpAndSettle();
    expect(selected, equals([10]));
  });

  testWidgets('tapping Personal gig with no personal band creates one then invokes callback',
      (tester) async {
    final selected = <int>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async {
        if (req.path == '/api/mobile/bands/solo' && req.method == 'POST') {
          return _json(201, {
            'bands': [
              {'id': 10, 'name': 'Real', 'is_owner': true, 'is_personal': false},
              {'id': 99, 'name': "Eddie's Band", 'is_owner': true, 'is_personal': true},
            ],
          });
        }
        if (req.path == '/api/mobile/auth/me' && req.method == 'GET') {
          return _json(200, {
            'user': {'id': 1, 'name': 'Eddie', 'email': 'e@e.com'},
            'bands': [
              {'id': 10, 'name': 'Real', 'is_owner': true, 'is_personal': false},
              {'id': 99, 'name': "Eddie's Band", 'is_owner': true, 'is_personal': true},
            ],
          });
        }
        return _json(404, {});
      });
    final storage = _FakeSecureStorage();
    await storage.writeToken('t');

    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: selected.add),
      auth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: const [BandSummary(id: 10, name: 'Real', isOwner: true)],
      ),
      dio: dio,
      storage: storage,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Personal gig'));
    await tester.pumpAndSettle();

    expect(selected, equals([99]));
  });

  testWidgets('tapping Personal gig on API failure shows inline error', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async => _json(500, {'message': 'fire'}));

    final storage = _FakeSecureStorage();
    await storage.writeToken('t');

    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: (_) {}),
      auth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: const [BandSummary(id: 10, name: 'Real', isOwner: true)],
      ),
      dio: dio,
      storage: storage,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Personal gig'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Try again'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/widgets/create_booking_sheet_test.dart
```

Expected: FAIL — `CreateBookingSheet` doesn't exist.

- [ ] **Step 3: Create the widget**

Create `/home/eddie/github/tts_bandmate/lib/features/bookings/widgets/create_booking_sheet.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/personal_band_provider.dart';
import '../../../shared/widgets/band_identity_chip.dart';
import '../../auth/data/models/band_summary.dart';
import '../../auth/providers/auth_provider.dart';

/// A sheet shown when the user taps "+" to create a new booking.
///
/// Real bands are listed at the top; tapping one invokes [onBandSelected]
/// with that band's id. A "Personal gig" row at the bottom creates the
/// personal band lazily (via `POST /bands/solo`) on first use, then invokes
/// [onBandSelected] with the personal band's id.
class CreateBookingSheet extends ConsumerStatefulWidget {
  const CreateBookingSheet({super.key, required this.onBandSelected});

  /// Invoked with the chosen band id. The caller is responsible for
  /// dismissing the sheet and navigating to the booking form.
  final void Function(int bandId) onBandSelected;

  @override
  ConsumerState<CreateBookingSheet> createState() => _CreateBookingSheetState();
}

class _CreateBookingSheetState extends ConsumerState<CreateBookingSheet> {
  bool _personalLoading = false;
  String? _personalError;

  Future<void> _onPersonalTap() async {
    setState(() {
      _personalLoading = true;
      _personalError = null;
    });
    try {
      final personal =
          await ref.read(personalBandProvider.notifier).ensureExists();
      if (!mounted) return;
      widget.onBandSelected(personal.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _personalError = "Couldn't set up personal gigs. Try again.";
      });
    } finally {
      if (mounted) setState(() => _personalLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider).value;
    final bands = (auth is AuthAuthenticated)
        ? auth.bands.where((b) => !b.isPersonal).toList()
        : <BandSummary>[];

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _GrabHandle(),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                'Create booking for',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
            for (final band in bands)
              _BandRow(
                band: band,
                onTap: () => widget.onBandSelected(band.id),
              ),
            if (bands.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  height: 0.5,
                  color: CupertinoColors.separator.resolveFrom(context),
                ),
              ),
            _PersonalRow(
              loading: _personalLoading,
              onTap: _personalLoading ? null : _onPersonalTap,
            ),
            if (_personalError != null) ...[
              const SizedBox(height: 8),
              Text(
                _personalError!,
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemRed.resolveFrom(context),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey3.resolveFrom(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _BandRow extends StatelessWidget {
  const _BandRow({required this.band, required this.onTap});
  final BandSummary band;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            BandIdentityChip(
              band: band,
              size: 28,
              textStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
            const Spacer(),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonalRow extends ConsumerWidget {
  const _PersonalRow({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            // Personal-band-shaped chip but we always render "Personal gig"
            // here (not just "Personal") to make the action clear.
            Icon(
              CupertinoIcons.person_crop_circle_fill,
              size: 28,
              color: CupertinoColors.systemBlue.resolveFrom(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Personal gig',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  Text(
                    'Just for me, not tied to a band',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
            if (loading)
              const CupertinoActivityIndicator(radius: 9)
            else
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/widgets/create_booking_sheet_test.dart
```

Expected: PASS (5 tests).

- [ ] **Step 5: Run analyzer + full test suite**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/widgets/create_booking_sheet.dart test/widgets/create_booking_sheet_test.dart && git commit -m "feat(bookings): add CreateBookingSheet with Personal gig entry"
```

---

### Task 16: Mobile — Render `BandIdentityChip` on Dashboard `EventCard`

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/dashboard/widgets/event_card.dart:50-94`
- Test: extend `/home/eddie/github/tts_bandmate/test/widgets/event_card_test.dart`

- [ ] **Step 1: Add a failing test**

Append to (or replace) the body of `test/widgets/event_card_test.dart` to include this test (preserve existing tests):

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/dashboard/widgets/event_card.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override Future<AuthState> build() async => _fixed;
}

void main() {
  testWidgets('EventCard shows band name when event has band', (tester) async {
    final event = EventSummary.fromJson({
      'key': 'evt-1',
      'title': 'A Gig',
      'date': '2026-06-01',
      'event_source': 'booking',
      'band': {
        'id': 10, 'name': 'The Rocking Eds', 'is_personal': false, 'logo_url': null,
      },
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(AuthAuthenticated(
              user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
              bands: const [],
            ))),
      ],
      child: CupertinoApp(
        home: CupertinoPageScaffold(child: EventCard(event: event)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('The Rocking Eds'), findsOneWidget);
  });

  testWidgets('EventCard shows "Personal" when event is on personal band', (tester) async {
    final event = EventSummary.fromJson({
      'key': 'evt-2',
      'title': 'Church',
      'date': '2026-06-02',
      'event_source': 'booking',
      'band': {
        'id': 99, 'name': "Eddie's Band", 'is_personal': true, 'logo_url': null,
      },
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(AuthAuthenticated(
              user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
              bands: const [],
            ))),
      ],
      child: CupertinoApp(
        home: CupertinoPageScaffold(child: EventCard(event: event)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Personal'), findsOneWidget);
  });

  testWidgets('EventCard renders without chip when band is missing', (tester) async {
    final event = EventSummary.fromJson({
      'key': 'evt-3',
      'title': 'Old',
      'date': '2026-06-03',
      'event_source': 'band_event',
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(AuthAuthenticated(
              user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
              bands: const [],
            ))),
      ],
      child: CupertinoApp(
        home: CupertinoPageScaffold(child: EventCard(event: event)),
      ),
    ));
    await tester.pumpAndSettle();
    // No band chip visible — should not throw and should render the title.
    expect(find.text('Old'), findsOneWidget);
  });
}
```

If `event_card_test.dart` already has a `void main()` block, merge these `testWidgets` calls into it.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/widgets/event_card_test.dart
```

Expected: FAIL — `EventCard` doesn't render band identity yet.

- [ ] **Step 3: Render the chip in `EventCard`**

In `/home/eddie/github/tts_bandmate/lib/features/dashboard/widgets/event_card.dart`, add the import at the top:

```dart
import '../../../shared/widgets/band_identity_chip.dart';
```

Then update the `Column` inside the `Padding` (around lines 49-94) so the title row appears, then the date, then the band chip (when band is non-null), then the venue. Replace the existing inner `Column` with:

```dart
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: CupertinoColors.label.resolveFrom(context)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (event.status != null) StatusChip(status: event.status!),
                        if (event.rosterStatus != null &&
                            event.rosterStatus != 'none' &&
                            event.rosterStatus!.isNotEmpty)
                          _RosterDot(status: event.rosterStatus!),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(event),
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                    ),
                    if (event.band != null) ...[
                      const SizedBox(height: 4),
                      BandIdentityChip(band: event.band!),
                    ],
                    if (event.venueName != null &&
                        event.venueName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.venueName!,
                        style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/widgets/event_card_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run analyzer + full test suite**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/dashboard/widgets/event_card.dart test/widgets/event_card_test.dart && git commit -m "feat(dashboard): show band identity chip on event cards"
```

---

### Task 17: Mobile — Convert Bookings tab to multi-band view

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/bookings/screens/bookings_screen.dart`
- Test: `/home/eddie/github/tts_bandmate/test/features/bookings/bookings_screen_multi_band_test.dart` (new)

The screen no longer reads `selectedBandProvider`. Instead, the body uses `userBookingsProvider` and renders `BandIdentityChip` on each `_BookingCard`. The "+" button opens `CreateBookingSheet`.

- [ ] **Step 1: Write the failing test**

Create `/home/eddie/github/tts_bandmate/test/features/bookings/bookings_screen_multi_band_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/network/api_client.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/bookings/screens/bookings_screen.dart';

class _FakeSecureStorage extends SecureStorage {
  _FakeSecureStorage() : super(const FlutterSecureStorage());
  final Map<String, String?> _m = {};
  @override Future<String?> readToken() async => _m['t'];
  @override Future<void> writeToken(String t) async => _m['t'] = t;
  @override Future<void> deleteToken() async => _m.remove('t');
  @override Future<String?> readBandId() async => _m['b'];
  @override Future<void> writeBandId(String id) async => _m['b'] = id;
  @override Future<void> deleteBandId() async => _m.remove('b');
  @override Future<String?> readUser() async => _m['u'];
  @override Future<void> writeUser(String u) async => _m['u'] = u;
  @override Future<void> clear() async => _m.clear();
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override void close({bool force = false}) {}
  @override Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) => handler(o);
}

ResponseBody _json(int s, Object b) =>
    ResponseBody.fromBytes(utf8.encode(jsonEncode(b)), s, headers: {
      'content-type': ['application/json'],
    });

class _StubApiClient extends ApiClient {
  _StubApiClient({required super.storage, required Dio dio}) : _stub = dio;
  final Dio _stub;
  @override Dio get dio => _stub;
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override Future<AuthState> build() async => _fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bookings screen lists bookings across multiple bands with chips',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final routeStorage = RouteStorage(await SharedPreferences.getInstance());
    final storage = _FakeSecureStorage();
    await storage.writeToken('t');

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async {
        if (req.path == '/api/mobile/me/bookings') {
          return _json(200, {
            'bookings': [
              {
                'id': 1,
                'name': 'Big Show',
                'date': '${DateTime.now().year}-06-01',
                'is_paid': false,
                'contacts': [],
                'status': 'confirmed',
                'band': {
                  'id': 10,
                  'name': 'The Rocking Eds',
                  'is_personal': false,
                  'logo_url': null,
                },
              },
              {
                'id': 2,
                'name': 'Sunday Service',
                'date': '${DateTime.now().year}-06-02',
                'is_paid': false,
                'contacts': [],
                'status': 'confirmed',
                'band': {
                  'id': 99,
                  'name': "Eddie's Band",
                  'is_personal': true,
                  'logo_url': null,
                },
              },
            ],
          });
        }
        return _json(404, {});
      });

    final widget = ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        apiClientProvider
            .overrideWithValue(_StubApiClient(storage: storage, dio: dio)),
        routeStorageProvider.overrideWith((_) async => routeStorage),
        authProvider.overrideWith(() => _FixedAuthNotifier(AuthAuthenticated(
              user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
              bands: const [
                BandSummary(id: 10, name: 'The Rocking Eds', isOwner: true),
              ],
            ))),
      ],
      child: const CupertinoApp(home: BookingsScreen()),
    );

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(find.text('Big Show'), findsOneWidget);
    expect(find.text('Sunday Service'), findsOneWidget);
    expect(find.text('The Rocking Eds'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/bookings_screen_multi_band_test.dart
```

Expected: FAIL — current screen still uses `selectedBandProvider` and per-band fetch.

- [ ] **Step 3: Refactor `BookingsScreen` to use `userBookingsProvider`**

Replace the entire contents of `/home/eddie/github/tts_bandmate/lib/features/bookings/screens/bookings_screen.dart` with:

```dart
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';
import 'package:tts_bandmate/shared/widgets/band_identity_chip.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import 'package:tts_bandmate/shared/widgets/status_chip.dart';
import '../data/models/booking_summary.dart';
import '../providers/bookings_provider.dart';
import '../widgets/create_booking_sheet.dart';

// ── Filter ────────────────────────────────────────────────────────────────────

enum _BookingsFilter { all, confirmed, pending, draft }

extension _BookingsFilterLabel on _BookingsFilter {
  String get label => switch (this) {
        _BookingsFilter.all => 'All',
        _BookingsFilter.confirmed => 'Confirmed',
        _BookingsFilter.pending => 'Pending',
        _BookingsFilter.draft => 'Draft',
      };
}

// ── List item discriminated union ─────────────────────────────────────────────

sealed class _ListItem {}

final class _HeaderItem extends _ListItem {
  _HeaderItem(this.label, this.monthIndex);
  final String label;
  final int monthIndex;
}

final class _CardItem extends _ListItem {
  _CardItem(this.booking);
  final BookingSummary booking;
}

// ── Root screen ───────────────────────────────────────────────────────────────

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  _BookingsFilter _filter = _BookingsFilter.all;
  int _selectedYear = DateTime.now().year;

  Future<void> _onNewBooking(BuildContext context) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) {
        return CreateBookingSheet(
          onBandSelected: (bandId) {
            Navigator.of(sheetContext).pop();
            context.push('/bookings/$bandId/new');
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _BookingsBody(
      filter: _filter,
      selectedYear: _selectedYear,
      onFilterChanged: (f) => setState(() => _filter = f),
      onYearChanged: (y) => setState(() => _selectedYear = y),
      onNewBooking: () => _onNewBooking(context),
    );
  }
}

class _BookingsBody extends ConsumerStatefulWidget {
  const _BookingsBody({
    required this.filter,
    required this.selectedYear,
    required this.onFilterChanged,
    required this.onYearChanged,
    required this.onNewBooking,
  });

  final _BookingsFilter filter;
  final int selectedYear;
  final void Function(_BookingsFilter) onFilterChanged;
  final void Function(int) onYearChanged;
  final VoidCallback onNewBooking;

  @override
  ConsumerState<_BookingsBody> createState() => _BookingsBodyState();
}

class _BookingsBodyState extends ConsumerState<_BookingsBody> {
  final ScrollController _scrollController = ScrollController();

  int? _lastScrolledYear;
  _BookingsFilter? _lastScrolledFilter;

  UserBookingsParams get _params =>
      UserBookingsParams(year: widget.selectedYear);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeScrollToCurrentMonth(List<_ListItem> items) {
    final now = DateTime.now();
    final isCurrentYear = widget.selectedYear == now.year;
    final comboChanged = widget.selectedYear != _lastScrolledYear ||
        widget.filter != _lastScrolledFilter;

    if (!isCurrentYear || !comboChanged) return;

    const double headerHeight = 46.0;
    const double cardHeight = 80.0;

    double offset = 0;
    bool found = false;
    for (final item in items) {
      if (item is _HeaderItem) {
        if (item.monthIndex == now.month) {
          found = true;
          break;
        }
        offset += headerHeight;
      } else {
        offset += cardHeight;
      }
    }

    if (!found) return;

    _lastScrolledYear = widget.selectedYear;
    _lastScrolledFilter = widget.filter;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          offset.clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(userBookingsProvider(_params));

    return CupertinoPageScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;
          return Center(
            child: SizedBox(
              width: maxWidth,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  CupertinoSliverRefreshControl(
                    onRefresh: () async =>
                        ref.invalidate(userBookingsProvider(_params)),
                  ),
                  CupertinoSliverNavigationBar(
                    largeTitle: const Text('Bookings'),
                    trailing: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: widget.onNewBooking,
                      child: const Icon(CupertinoIcons.add),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyControls(
                      filter: widget.filter,
                      onFilterChanged: widget.onFilterChanged,
                      year: widget.selectedYear,
                      onYearChanged: widget.onYearChanged,
                    ),
                  ),
                  bookingsAsync.when(
                    loading: () => const SliverFillRemaining(
                      child: Center(child: CupertinoActivityIndicator()),
                    ),
                    error: (e, _) => SliverFillRemaining(
                      child: ErrorView(
                        message: ErrorView.friendlyMessage(e),
                        onRetry: () =>
                            ref.invalidate(userBookingsProvider(_params)),
                      ),
                    ),
                    data: (bookings) {
                      final items = _buildListItems(bookings, widget.filter);
                      _maybeScrollToCurrentMonth(items);

                      if (items.isEmpty) {
                        return SliverFillRemaining(
                          child: EmptyStateView(
                            icon: CupertinoIcons.calendar_badge_minus,
                            title: 'No bookings in ${widget.selectedYear}',
                            subtitle: _emptySubtitle(widget.filter),
                          ),
                        );
                      }
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = items[index];
                            return switch (item) {
                              _HeaderItem(:final label) =>
                                _MonthHeader(label: label),
                              _CardItem(:final booking) => _BookingCard(
                                  booking: booking,
                                  onTap: () {
                                    final bandId = booking.band?.id;
                                    if (bandId != null) {
                                      context.push(
                                        '/bookings/$bandId/${booking.id}',
                                      );
                                    }
                                  },
                                ),
                            };
                          },
                          childCount: items.length,
                        ),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<_ListItem> _buildListItems(
      List<BookingSummary> bookings, _BookingsFilter filter) {
    final sorted = [...bookings]
      ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));

    final filtered = switch (filter) {
      _BookingsFilter.all => sorted,
      _BookingsFilter.draft =>
        sorted.where((b) => b.status?.toLowerCase() == 'draft').toList(),
      _BookingsFilter.confirmed =>
        sorted.where((b) => b.status?.toLowerCase() == 'confirmed').toList(),
      _BookingsFilter.pending =>
        sorted.where((b) => b.status?.toLowerCase() == 'pending').toList(),
    };

    if (filtered.isEmpty) return [];

    final items = <_ListItem>[];
    String? lastMonthKey;

    for (final booking in filtered) {
      final d = booking.parsedDate;
      final monthKey =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

      if (monthKey != lastMonthKey) {
        items.add(_HeaderItem(DateFormat('MMMM yyyy').format(d), d.month));
        lastMonthKey = monthKey;
      }
      items.add(_CardItem(booking));
    }

    return items;
  }

  String _emptySubtitle(_BookingsFilter filter) => switch (filter) {
        _BookingsFilter.confirmed => 'No confirmed bookings this year.',
        _BookingsFilter.pending => 'No pending bookings this year.',
        _BookingsFilter.draft => 'No draft bookings this year.',
        _BookingsFilter.all => 'Try a different year or add a new booking.',
      };
}

class _StickyControls extends SliverPersistentHeaderDelegate {
  _StickyControls({
    required this.filter,
    required this.onFilterChanged,
    required this.year,
    required this.onYearChanged,
  });

  final _BookingsFilter filter;
  final void Function(_BookingsFilter) onFilterChanged;
  final int year;
  final void Function(int) onYearChanged;

  static const double _height = 116.0;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  bool shouldRebuild(_StickyControls old) =>
      filter != old.filter || year != old.year;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final brightness = CupertinoTheme.of(context).brightness ??
        MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark
                      ? CupertinoColors.systemBackground.darkColor
                      : CupertinoColors.systemBackground)
                  .withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (isDark ? CupertinoColors.white : CupertinoColors.black)
                    .withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FilterPills(current: filter, onChanged: onFilterChanged),
                _YearStepper(year: year, onChanged: onYearChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  const _FilterPills({required this.current, required this.onChanged});
  final _BookingsFilter current;
  final void Function(_BookingsFilter) onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: _BookingsFilter.values.map((f) {
          final isSelected = current == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? CupertinoColors.systemBlue.resolveFrom(context)
                      : CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? CupertinoColors.white
                        : CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _YearStepper extends StatelessWidget {
  const _YearStepper({required this.year, required this.onChanged});
  final int year;
  final void Function(int) onChanged;

  static const int _minYear = 2000;
  static final int _maxYear = DateTime.now().year + 3;

  @override
  Widget build(BuildContext context) {
    final canGoBack = year > _minYear;
    final canGoForward = year < _maxYear;
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final disabledColor = CupertinoColors.tertiaryLabel.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onPressed: canGoBack ? () => onChanged(year - 1) : null,
            child: Icon(
              CupertinoIcons.chevron_left,
              size: 18,
              color: canGoBack ? labelColor : disabledColor,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              year.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onPressed: canGoForward ? () => onChanged(year + 1) : null,
            child: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: canGoForward ? labelColor : disabledColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, this.onTap});
  final BookingSummary booking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColor(context, booking.status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              booking.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (booking.status != null)
                            StatusChip(status: booking.status!),
                        ],
                      ),
                      if (booking.band != null) ...[
                        const SizedBox(height: 4),
                        BandIdentityChip(band: booking.band!),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(booking),
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                      if (booking.venueName != null &&
                          booking.venueName!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.location,
                              size: 11,
                              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                booking.venueName!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        booking.displayPrice,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.systemBlue.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(BookingSummary booking) {
    final dateStr = DateFormat('EEE, MMM d, yyyy').format(booking.parsedDate);
    if (booking.startTime != null && booking.startTime!.isNotEmpty) {
      return '$dateStr at ${toAmPm(booking.startTime!)}';
    }
    return dateStr;
  }

  Color _accentColor(BuildContext context, String? status) =>
      switch (status?.toLowerCase()) {
        'confirmed' => CupertinoColors.systemGreen.resolveFrom(context),
        'pending' => CupertinoColors.systemOrange.resolveFrom(context),
        'draft' => CupertinoColors.systemBlue.resolveFrom(context),
        'cancelled' || 'canceled' =>
          CupertinoColors.systemRed.resolveFrom(context),
        _ => CupertinoColors.systemFill.resolveFrom(context),
      };
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/bookings_screen_multi_band_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run analyzer + full test suite**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/screens/bookings_screen.dart test/features/bookings/bookings_screen_multi_band_test.dart && git commit -m "feat(bookings): convert tab to multi-band view with create sheet"
```

---

### Task 18: Mobile — Wire Dashboard "+" button to `CreateBookingSheet`

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/dashboard/screens/dashboard_screen.dart`

The Dashboard screen has a "+" or similar entry point for creating bookings/events. Verify how the screen currently triggers booking creation and replace that flow with `CreateBookingSheet`.

- [ ] **Step 1: Inspect the current Dashboard creation entry point**

```bash
grep -n 'context.push\|onPressed' /home/eddie/github/tts_bandmate/lib/features/dashboard/screens/dashboard_screen.dart | head -20
```

If no creation affordance exists today, add one in the `CupertinoSliverNavigationBar.trailing` (mirroring the bookings screen pattern). If one exists and routes to `/bookings/{bandId}/new` using the selected band, replace its handler with the sheet.

- [ ] **Step 2: Add (or replace) the handler**

Wherever the create-booking action lives in the Dashboard, replace its `onPressed` with:

```dart
onPressed: () async {
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) {
      return CreateBookingSheet(
        onBandSelected: (bandId) {
          Navigator.of(sheetContext).pop();
          context.push('/bookings/$bandId/new');
        },
      );
    },
  );
},
```

Add the import at the top of the file:

```dart
import '../../bookings/widgets/create_booking_sheet.dart';
```

If the Dashboard doesn't currently expose a "+" affordance, add one to the nav bar trailing slot:

```dart
CupertinoSliverNavigationBar(
  largeTitle: const Text('Dashboard'),
  trailing: CupertinoButton(
    padding: EdgeInsets.zero,
    onPressed: () async {
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => CreateBookingSheet(
          onBandSelected: (bandId) {
            Navigator.of(sheetContext).pop();
            context.push('/bookings/$bandId/new');
          },
        ),
      );
    },
    child: const Icon(CupertinoIcons.add),
  ),
),
```

- [ ] **Step 3: Run analyzer + full test suite**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 4: Manual smoke check (no automated test for this small wiring)**

```bash
cd /home/eddie/github/tts_bandmate && flutter run -d chrome --dart-define=BASE_URL=http://localhost:8715
```

In the running app, log in, tap "+" on the Dashboard, verify the sheet opens with real bands and a Personal gig row. Cancel out without creating; the manual test in Task 20 will exercise creation.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/dashboard/screens/dashboard_screen.dart && git commit -m "feat(dashboard): open CreateBookingSheet from + button"
```

---

### Task 19: Mobile — Show `BandIdentityChip` on booking detail header

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/bookings/screens/booking_detail_screen.dart` (line ~229 area, where the nav bar `middle` is set, plus the body header)

The booking detail nav bar currently shows just `Text(b.name)`. We add a `BandIdentityChip` immediately below the booking title in the body so the band/personal identity is visible when viewing a booking. Keeping the nav bar as the booking name preserves the existing UX; the chip lives in the body where there's room.

- [ ] **Step 1: Locate the booking title in the detail body**

```bash
grep -n 'b.name\|b\.venue\|booking.name' /home/eddie/github/tts_bandmate/lib/features/bookings/screens/booking_detail_screen.dart | head -10
```

Find the body section where the booking title and venue/date are rendered.

- [ ] **Step 2: Add the chip below the booking title in the body**

In `booking_detail_screen.dart`, add the import:

```dart
import '../../../shared/widgets/band_identity_chip.dart';
```

In the body where the booking title or venue/date currently renders, add the chip immediately after the title (or near the top of the detail body):

```dart
if (b.band != null) ...[
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: BandIdentityChip(band: b.band!),
  ),
],
```

The exact placement depends on the existing layout — pick the spot directly under the booking title or directly above the date/venue line, whichever reads most naturally.

- [ ] **Step 3: Verify `BookingDetail` model carries the `band` field**

```bash
grep -n 'band\|fromJson' /home/eddie/github/tts_bandmate/lib/features/bookings/data/models/booking_detail.dart | head -20
```

If `BookingDetail` doesn't yet include a nested `band`, mirror the change from Task 8 — add a `final BandSummary? band` field, parse it in `fromJson` from `json['band']`, and add the import for `BandSummary`. The backend already returns it (Task 2 added the field to the formatter, which feeds both `index` and `show`).

- [ ] **Step 4: Run analyzer + full test suite**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/bookings/screens/booking_detail_screen.dart lib/features/bookings/data/models/booking_detail.dart && git commit -m "feat(bookings): show band identity chip on booking detail"
```

---

### Task 20: Manual smoke verification end-to-end

This task has no code; it verifies the spec's manual smoke list. Run against a local backend with the changes from tasks 1–5 deployed.

- [ ] **Step 1: First-time personal gig creation**

```bash
cd /home/eddie/github/tts_bandmate && flutter run -d chrome --dart-define=BASE_URL=http://localhost:8715
```

In a browser at `http://localhost:8715`-paired backend session: log in as a user who has at least one real band but **no personal band yet**. Tap "+" on the Dashboard. Verify the sheet shows real bands followed by a divider and a "Personal gig" row. Tap "Personal gig". Verify the form opens. Fill in name, date, venue. Save. Verify the booking appears on the Dashboard with the user's avatar/initial + "Personal" label.

- [ ] **Step 2: Personal gig appears in Bookings tab**

Navigate to the Bookings tab. Verify the gig from Step 1 is in the list, with the same Personal chip.

- [ ] **Step 3: Subsequent personal gig (no extra API call)**

Tap "+" again on the Dashboard, tap "Personal gig". Verify the form opens immediately without the loading indicator (no `POST /bands/solo` should fire — open browser devtools, Network tab, to confirm).

- [ ] **Step 4: Real-band gig still works**

Tap "+", tap one of your real bands. Verify the form opens for that band. Save. Verify the booking shows up on the Dashboard with that band's avatar/name.

- [ ] **Step 5: Editing a personal gig**

Tap the personal gig from Step 1. Verify the booking detail screen opens with the user's avatar + "Personal" in the header. Edit the name, save. Verify the change appears on the list.

- [ ] **Step 6: Solo musician (only personal band) flow**

Log out, sign up a fresh account, choose "Go Solo" on the path-selection screen. Land on Dashboard. Verify the user has only their personal band. Tap "+". Verify the sheet shows **only** the "Personal gig" row (no real-bands section). Create a gig. Verify it appears on the Dashboard and Bookings tab.

- [ ] **Step 7: Personal band hidden from selectors**

Log in as a multi-band user who also has a personal band. Navigate to band-switching UI (currently `/bands` selector — accessible during onboarding only, but the test still applies as a regression check). Verify the personal band does **not** appear in the list.

- [ ] **Step 8: Run full automated suite once more before sign-off**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test
```

```bash
cd /home/eddie/github/TTS && php artisan test --filter=Mobile
```

Both should pass. Commit nothing — this task is verification only.

---

## Summary of commits

| # | Subject |
|---|---|
| 1 | feat(mobile): include is_personal and logo_url in formatBands |
| 2 | feat(mobile): include band field on formatted bookings |
| 3 | feat(mobile): add /me/bookings aggregating endpoint |
| 4 | feat(mobile): include band field on dashboard events |
| 5 | feat(mobile): include avatar_url in formatUser |
| 6 | feat(auth): add isPersonal and logoUrl to BandSummary |
| 7 | feat(auth): add avatarUrl to AuthUser |
| 8 | feat(bookings): add nested band field to BookingSummary |
| 9 | feat(events): add nested band field to EventSummary |
| 10 | feat(bookings): add /me/bookings repository method |
| 11 | feat(bookings): add userBookingsProvider for multi-band view |
| 12 | feat: add personalBandProvider with lazy creation |
| 13 | feat(shared): add BandIdentityChip widget |
| 14 | feat(auth): hide personal band from band selector |
| 15 | feat(bookings): add CreateBookingSheet with Personal gig entry |
| 16 | feat(dashboard): show band identity chip on event cards |
| 17 | feat(bookings): convert tab to multi-band view with create sheet |
| 18 | feat(dashboard): open CreateBookingSheet from + button |
| 19 | feat(bookings): show band identity chip on booking detail |

Plus no commits in Task 20 (manual verification).
