# Library Aggregation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Library screen aggregate charts across every band the user belongs to, with a bands-only filter sheet (modeled on the dashboard's `CalendarFilterSheet`) and a band-picker `CreateChartSheet` (modeled on `CreateBookingSheet`); after creating a chart, push the user straight to the chart detail screen so they can immediately upload PDFs.

**Architecture:** New backend endpoint `GET /api/mobile/charts` returns charts from every band of `Auth::user()->allBands()` with a nested `band` block (id, name, logo_url, is_personal). Flutter `Chart` model gets a nullable nested `ChartBand`. `LibraryNotifier` rewrites `build()` to call the new aggregated repo method; the screen drops its `selectedBandProvider` shell and applies a new `libraryFilterProvider` (Set\<int\> hiddenBandIds) before grouping. Row avatars become `BandAvatar.forBand` / `BandAvatar.forUser`. The `+` button routes through a band-picker sheet for multi-band users (skip for single-band) and pushes chart detail after create.

**Tech Stack:** Flutter / Dart / Riverpod v2 (frontend), Laravel + PHPUnit (backend). Cupertino UI throughout. No code generation in use; `Chart.fromJson` stays hand-written.

**Spec:** [docs/superpowers/specs/2026-05-02-library-aggregation-design.md](../specs/2026-05-02-library-aggregation-design.md)

**Branch:** `feature/library-aggregation` (already created off `origin/main`; the spec commit is at `89f9f7c`).

**Working directories:** Flutter app at `/home/eddie/github/tts_bandmate`; Laravel backend at `/home/eddie/github/TTS`. Backend is a separate repo; commits are independent.

---

## File structure

### Backend (Laravel — `/home/eddie/github/TTS`)

| File | What changes | Why |
|---|---|---|
| `app/Http/Controllers/Api/Mobile/MusicController.php` | Add `chartsForUser` method | All mobile chart endpoints already live in this controller; keep them together |
| `routes/api.php` | Add `Route::get('/charts', ...)` inside the `auth:sanctum` group at the user level (alongside `/me/bookings`, `/dashboard`) | Aggregate endpoint is band-agnostic, must not be inside `mobile.band:*` middleware |
| `tests/Feature/Api/Mobile/MobileChartsAggregateTest.php` | New | Cover scoping, band block shape, personal band, auth, empty state |

### Flutter (`/home/eddie/github/tts_bandmate`)

| File | What changes | Why |
|---|---|---|
| `lib/features/library/data/models/chart.dart` | Add `ChartBand` class; add `final ChartBand? band` to `Chart` | Renders band avatar + filterable by band on the merged list |
| `lib/features/library/data/library_repository.dart` | Add `getAllCharts()` method | Calls the new aggregated endpoint |
| `lib/features/library/providers/library_provider.dart` | Rewrite `LibraryNotifier.build()` to call `getAllCharts()`; change `createChart` signature to take a `BandSummary` so the new chart can be stamped with its band | Aggregated load + correct band stamping for optimistic insert |
| `lib/features/library/providers/library_filter_provider.dart` | New | Mirrors `calendar_filter_provider.dart` (bands-only) |
| `lib/features/library/widgets/library_filter_button.dart` | New | Mirrors `calendar_filter_button.dart` |
| `lib/features/library/widgets/library_filter_sheet.dart` | New | Mirrors `calendar_filter_sheet.dart` minus the event-types section |
| `lib/features/library/widgets/create_chart_sheet.dart` | New | Mirrors `create_booking_sheet.dart` |
| `lib/features/library/screens/library_screen.dart` | Drop `selectedBandProvider` shell; apply filter before `_buildGroups`; swap initials avatar for `BandAvatar`; overlay floating filter button; route `+` through new sheet; push detail after create | Implements the merged UX |
| `lib/features/library/screens/create_chart_screen.dart` | Update `_save()` to call `createChart(band: ...)` with the resolved `BandSummary` | Threads the band metadata through |
| `lib/core/network/api_endpoints.dart` | Add `mobileChartsAll = '/api/mobile/charts'` | Endpoint constant |

### Flutter tests (`/home/eddie/github/tts_bandmate/test`)

| File | What changes | Why |
|---|---|---|
| `test/features/library/providers/library_filter_provider_test.dart` | New | Toggle, clear, equality |
| `test/features/library/data/models/chart_test.dart` | New | `Chart.fromJson` parses (and tolerates missing) `band` block |
| `test/features/library/providers/library_provider_test.dart` | New | Build → getAllCharts; createChart insert with band stamp; deleteChart by id |
| `test/features/library/widgets/library_filter_button_test.dart` | New | Active fill flip; badge count |
| `test/features/library/widgets/library_filter_sheet_test.dart` | New | Renders bands; tap toggles; Clear All visibility; personal label |
| `test/features/library/widgets/create_chart_sheet_test.dart` | New | Multi-band rows; tap dispatches; Personal flow + spinner; failure path |
| `test/features/library/screens/library_screen_test.dart` | New | Aggregated render; filter applies; "all hidden" empty state; `+` shortcut/sheet |

---

## Conventions for every task

- **Commit cadence:** one commit per task at the green-bar (after the test step passes), using a concise conventional-commit message that names the feature area.
- **Backend tests:** `cd /home/eddie/github/TTS && ./vendor/bin/phpunit --filter <name>` from the Laravel repo root.
- **Flutter tests:** `flutter test test/path/to_test.dart` from the Flutter repo root. Single-test filter: append `--plain-name "<name>"`.
- **`flutter analyze`** is the lint check; run after each task that changes Dart code, fix anything new before committing.
- **Working directory:** always state which repo a step runs in. Tasks 1-3 are in TTS (backend); tasks 4+ are in tts_bandmate (Flutter).
- **No `mkdir`** is ever required: every directory referenced below already exists; `Write` will create files inside them.

---

## Phase 1 — Backend (Laravel)

### Task 1: Backend feature test — `chartsForUser` aggregates across bands

**Files:**
- Create: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/MobileChartsAggregateTest.php`

This test will fail until Task 2 lands the controller method and Task 3 lands the route. We follow standard TDD: write the failing test first.

- [ ] **Step 1: Write the failing test file**

Use the dashboard test (`DashboardEventBandFieldTest.php`) as the structural reference — it already shows how to set up a user with bands, hit a mobile endpoint with a sanctum token, and assert on response shape. Charts use the `Charts` Eloquent model and band ownership uses `BandOwners`.

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\BandOwners;
use App\Models\Bands;
use App\Models\Charts;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class MobileChartsAggregateTest extends TestCase
{
    use RefreshDatabase;

    private function makeBand(string $name, bool $isPersonal = false): Bands
    {
        return Bands::create([
            'name'        => $name,
            'site_name'   => str()->slug($name) . '-' . uniqid(),
            'is_personal' => $isPersonal,
        ]);
    }

    public function test_returns_charts_from_all_user_bands(): void
    {
        $user = User::factory()->create();

        $bandA = $this->makeBand('Band A');
        $bandB = $this->makeBand('Band B');
        BandOwners::create(['user_id' => $user->id, 'band_id' => $bandA->id]);
        BandOwners::create(['user_id' => $user->id, 'band_id' => $bandB->id]);

        Charts::create(['band_id' => $bandA->id, 'title' => 'A1']);
        Charts::create(['band_id' => $bandA->id, 'title' => 'A2']);
        Charts::create(['band_id' => $bandA->id, 'title' => 'A3']);
        Charts::create(['band_id' => $bandB->id, 'title' => 'B1']);
        Charts::create(['band_id' => $bandB->id, 'title' => 'B2']);
        Charts::create(['band_id' => $bandB->id, 'title' => 'B3']);

        $token = $user->createToken('test')->plainTextToken;
        $response = $this->withToken($token)->getJson('/api/mobile/charts');

        $response->assertOk();
        $charts = $response->json('charts');
        $this->assertCount(6, $charts);
    }

    public function test_excludes_charts_from_bands_user_is_not_in(): void
    {
        $user = User::factory()->create();
        $other = User::factory()->create();

        $userBand = $this->makeBand('Mine');
        $otherBand = $this->makeBand('Theirs');
        BandOwners::create(['user_id' => $user->id, 'band_id' => $userBand->id]);
        BandOwners::create(['user_id' => $other->id, 'band_id' => $otherBand->id]);

        Charts::create(['band_id' => $userBand->id, 'title' => 'Mine 1']);
        Charts::create(['band_id' => $otherBand->id, 'title' => 'Theirs 1']);

        $token = $user->createToken('test')->plainTextToken;
        $response = $this->withToken($token)->getJson('/api/mobile/charts');

        $response->assertOk();
        $titles = collect($response->json('charts'))->pluck('title');
        $this->assertContains('Mine 1', $titles);
        $this->assertNotContains('Theirs 1', $titles);
    }

    public function test_each_chart_includes_band_block(): void
    {
        $user = User::factory()->create();
        $band = $this->makeBand('My Band');
        BandOwners::create(['user_id' => $user->id, 'band_id' => $band->id]);

        Charts::create(['band_id' => $band->id, 'title' => 'Stardust']);

        $token = $user->createToken('test')->plainTextToken;
        $response = $this->withToken($token)->getJson('/api/mobile/charts');

        $response->assertOk();
        $chart = $response->json('charts.0');

        $this->assertArrayHasKey('band', $chart);
        $this->assertSame($band->id, $chart['band']['id']);
        $this->assertSame('My Band', $chart['band']['name']);
        $this->assertFalse($chart['band']['is_personal']);
        $this->assertArrayHasKey('logo_url', $chart['band']);
    }

    public function test_includes_personal_band_charts_with_is_personal_true(): void
    {
        $user = User::factory()->create();
        $personal = $this->makeBand("{$user->name}'s Band", isPersonal: true);
        BandOwners::create(['user_id' => $user->id, 'band_id' => $personal->id]);

        Charts::create(['band_id' => $personal->id, 'title' => 'Solo Etude']);

        $token = $user->createToken('test')->plainTextToken;
        $response = $this->withToken($token)->getJson('/api/mobile/charts');

        $response->assertOk();
        $chart = $response->json('charts.0');
        $this->assertTrue($chart['band']['is_personal']);
    }

    public function test_unauthenticated_user_returns_401(): void
    {
        $response = $this->getJson('/api/mobile/charts');
        $response->assertStatus(401);
    }

    public function test_returns_empty_array_when_user_has_no_bands(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('test')->plainTextToken;
        $response = $this->withToken($token)->getJson('/api/mobile/charts');
        $response->assertOk();
        $this->assertSame([], $response->json('charts'));
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from the TTS repo root:

```bash
cd /home/eddie/github/TTS && ./vendor/bin/phpunit --filter MobileChartsAggregateTest
```

Expected: failures because the route doesn't exist (likely 404 with HTML response, breaking `json()` assertions).

- [ ] **Step 3: Commit the failing test**

```bash
cd /home/eddie/github/TTS && git add tests/Feature/Api/Mobile/MobileChartsAggregateTest.php && git commit -m "test(api/mobile): add aggregated charts endpoint feature test (failing)"
```

---

### Task 2: Backend implementation — `chartsForUser` controller method

**Files:**
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/MusicController.php`

The aggregated method scopes by `Auth::user()->allBands()` (which already de-dupes owner/member/sub bands). Each chart's `band` block uses `TokenService::resolveLogoUrl($band->logo)` for `logo_url` to match the dashboard's pattern.

- [ ] **Step 1: Add the `chartsForUser` method**

Add this method to `MusicController` immediately after the existing `charts` method (around line 64). Add `use Auth;` at the top of the file if it isn't already imported (it isn't — the file has `use Illuminate\Http\Request` etc., but no Auth import).

Add this `use` near the existing imports at the top of the file:

```php
use App\Services\Mobile\TokenService;
use Illuminate\Support\Facades\Auth;
```

Add this method after `charts()` (insert before `chartDetail()`):

```php
    /**
     * List all charts across every band the authenticated user belongs to.
     *
     * Each chart is shaped via the same fields as the per-band `charts` method
     * plus a nested `band` block ({id, name, logo_url, is_personal}) so the
     * mobile client can render the band avatar without an extra round trip.
     */
    public function chartsForUser(Request $_request): JsonResponse
    {
        $user = Auth::user();
        $bands = $user->allBands();
        $bandIds = $bands->pluck('id')->all();

        if (empty($bandIds)) {
            return response()->json(['charts' => []]);
        }

        $bandLookup = $bands->keyBy('id');

        $charts = Charts::whereIn('band_id', $bandIds)
            ->withCount('uploads')
            ->orderBy('title')
            ->get();

        return response()->json([
            'charts' => $charts->map(function ($ch) use ($bandLookup) {
                $band = $bandLookup[$ch->band_id] ?? null;
                return [
                    'id'            => $ch->id,
                    'band_id'       => $ch->band_id,
                    'title'         => $ch->title ?? '',
                    'composer'      => $ch->composer ?? '',
                    'description'   => $ch->description ?? '',
                    'price'         => $ch->price ?? 0,
                    'public'        => (bool) $ch->public,
                    'uploads_count' => $ch->uploads_count ?? 0,
                    'band'          => $band ? [
                        'id'          => $band->id,
                        'name'        => $band->name,
                        'is_personal' => (bool) $band->is_personal,
                        'logo_url'    => TokenService::resolveLogoUrl($band->logo),
                    ] : null,
                ];
            })->values(),
        ]);
    }
```

- [ ] **Step 2: Run the test — still fails because route is not yet wired**

```bash
cd /home/eddie/github/TTS && ./vendor/bin/phpunit --filter MobileChartsAggregateTest
```

Expected: still 404. Method exists but no route hits it yet.

- [ ] **Step 3: Commit (work-in-progress allowed; route lands next)**

```bash
cd /home/eddie/github/TTS && git add app/Http/Controllers/Api/Mobile/MusicController.php && git commit -m "feat(api/mobile): add chartsForUser controller method"
```

---

### Task 3: Backend route — wire `/api/mobile/charts`

**Files:**
- Modify: `/home/eddie/github/TTS/routes/api.php`

The route lives at the user level (band-agnostic), alongside `/me/bookings` and `/dashboard`. It must be inside the `auth:sanctum` group but **outside** any `mobile.band:*` middleware group.

- [ ] **Step 1: Add the route**

Find the line:

```php
Route::get('/dashboard', [App\Http\Controllers\Api\Mobile\DashboardController::class, 'index'])->name('mobile.dashboard');
```

(should be around line 78). Add the new route immediately after it:

```php
        // Aggregating charts across all of the user's bands (band-agnostic).
        Route::get('/charts', [App\Http\Controllers\Api\Mobile\MusicController::class, 'chartsForUser'])->name('mobile.charts.for-user');
```

- [ ] **Step 2: Run the test — should pass now**

```bash
cd /home/eddie/github/TTS && ./vendor/bin/phpunit --filter MobileChartsAggregateTest
```

Expected: all six tests pass.

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/TTS && git add routes/api.php && git commit -m "feat(api/mobile): wire GET /api/mobile/charts (aggregated)"
```

---

## Phase 2 — Flutter data layer

All remaining tasks run in the Flutter repo: `cd /home/eddie/github/tts_bandmate`.

### Task 4: API endpoint constant

**Files:**
- Modify: `lib/core/network/api_endpoints.dart`

- [ ] **Step 1: Add the constant**

Find the line:

```dart
  static String mobileBandCharts(int bandId) => '/api/mobile/bands/$bandId/charts';
```

Add directly above it:

```dart
  static const String mobileChartsAll = '/api/mobile/charts';
```

- [ ] **Step 2: Verify analyzer**

```bash
flutter analyze lib/core/network/api_endpoints.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/network/api_endpoints.dart && git commit -m "feat(library): add mobileChartsAll endpoint constant"
```

---

### Task 5: `Chart` model — add `ChartBand` and `band` field, with tests

**Files:**
- Modify: `lib/features/library/data/models/chart.dart`
- Create: `test/features/library/data/models/chart_test.dart`

The new `band` field is **nullable** so that responses from the existing per-band endpoint (which doesn't include a `band` block) still parse cleanly.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/data/models/chart_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';

void main() {
  group('Chart.fromJson — band block', () {
    test('parses nested band object with all fields', () {
      final chart = Chart.fromJson({
        'id': 1,
        'band_id': 7,
        'title': 'Stardust',
        'composer': 'Hoagy Carmichael',
        'description': '',
        'price': 0,
        'public': false,
        'uploads_count': 0,
        'band': {
          'id': 7,
          'name': 'Trio',
          'is_personal': false,
          'logo_url': 'https://example.com/logo.png',
        },
      });

      expect(chart.band, isNotNull);
      expect(chart.band!.id, 7);
      expect(chart.band!.name, 'Trio');
      expect(chart.band!.isPersonal, false);
      expect(chart.band!.logoUrl, 'https://example.com/logo.png');
    });

    test('parses is_personal: true for personal band', () {
      final chart = Chart.fromJson({
        'id': 2,
        'band_id': 9,
        'title': 'Etude',
        'composer': '',
        'description': '',
        'price': 0,
        'public': false,
        'uploads_count': 0,
        'band': {
          'id': 9,
          'name': "Eddie's Band",
          'is_personal': true,
          'logo_url': null,
        },
      });

      expect(chart.band!.isPersonal, true);
      expect(chart.band!.logoUrl, isNull);
    });

    test('tolerates missing band field (per-band endpoint response)', () {
      final chart = Chart.fromJson({
        'id': 3,
        'band_id': 5,
        'title': 'Body and Soul',
        'composer': '',
        'description': '',
        'price': 0,
        'public': false,
        'uploads_count': 0,
        // no 'band' key
      });

      expect(chart.band, isNull);
      expect(chart.title, 'Body and Soul');
    });

    test('tolerates band: null', () {
      final chart = Chart.fromJson({
        'id': 4,
        'band_id': 5,
        'title': 'Caravan',
        'composer': '',
        'description': '',
        'price': 0,
        'public': false,
        'uploads_count': 0,
        'band': null,
      });

      expect(chart.band, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/features/library/data/models/chart_test.dart
```

Expected: compile error — `chart.band` doesn't exist.

- [ ] **Step 3: Add `ChartBand` and update `Chart`**

Modify `lib/features/library/data/models/chart.dart`. Insert the `ChartBand` class after the existing `ChartUpload` class (around line 30, before `class Chart`):

```dart
/// Lightweight band identifier carried on a [Chart] when fetched from the
/// aggregated `GET /api/mobile/charts` endpoint. Nullable on [Chart] because
/// per-band endpoint responses do not include this block.
class ChartBand {
  const ChartBand({
    required this.id,
    required this.name,
    required this.isPersonal,
    this.logoUrl,
  });

  final int id;
  final String name;
  final bool isPersonal;
  final String? logoUrl;

  factory ChartBand.fromJson(Map<String, dynamic> json) => ChartBand(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        isPersonal: json['is_personal'] as bool? ?? false,
        logoUrl: json['logo_url'] as String?,
      );
}
```

Then in the `Chart` class:

1. Add field `final ChartBand? band;` after `uploads`:

```dart
  final List<ChartUpload> uploads;
  final ChartBand? band;
```

2. Add `this.band` to the constructor:

```dart
  const Chart({
    required this.id,
    required this.bandId,
    required this.title,
    required this.composer,
    required this.description,
    required this.price,
    required this.isPublic,
    required this.uploadsCount,
    required this.uploads,
    this.band,
  });
```

3. Update `fromJson` to parse the `band` block tolerantly (add as the last entry, before the closing `)`):

```dart
  factory Chart.fromJson(Map<String, dynamic> json) => Chart(
        id: json['id'] as int,
        bandId: json['band_id'] as int,
        title: json['title'] as String? ?? '',
        composer: json['composer'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        isPublic: json['public'] as bool? ?? false,
        uploadsCount: json['uploads_count'] as int? ?? 0,
        uploads: (json['uploads'] as List<dynamic>?)
                ?.map((u) => ChartUpload.fromJson(u as Map<String, dynamic>))
                .toList() ??
            [],
        band: json['band'] is Map<String, dynamic>
            ? ChartBand.fromJson(json['band'] as Map<String, dynamic>)
            : null,
      );
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/library/data/models/chart_test.dart
```

Expected: all four tests pass.

- [ ] **Step 5: Run analyzer**

```bash
flutter analyze lib/features/library/data/models/chart.dart test/features/library/data/models/chart_test.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/data/models/chart.dart test/features/library/data/models/chart_test.dart && git commit -m "feat(library): add nested ChartBand to Chart model"
```

---

### Task 6: `LibraryRepository.getAllCharts()`

**Files:**
- Modify: `lib/features/library/data/library_repository.dart`

The new method mirrors `getCharts(bandId)` but hits `mobileChartsAll` and reads from the same `charts` JSON key. (The repository file currently only imports `models/chart.dart`; the import you'll see in the file is `import 'package:tts_bandmate/core/providers/core_providers.dart';` — `ApiEndpoints` is re-exported from `core_providers.dart`.)

- [ ] **Step 1: Add the method**

Insert immediately after the existing `getCharts(int bandId)` method:

```dart
  /// Fetches every chart across all bands the authenticated user belongs to.
  ///
  /// Each [Chart] in the returned list has its [Chart.band] populated, which
  /// the merged Library screen uses to render avatars and apply band filters.
  Future<List<Chart>> getAllCharts() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileChartsAll,
    );

    final data = response.data!;
    final rawList = data['charts'] as List<dynamic>;
    return rawList
        .cast<Map<String, dynamic>>()
        .map(Chart.fromJson)
        .toList();
  }
```

- [ ] **Step 2: Run analyzer**

```bash
flutter analyze lib/features/library/data/library_repository.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/library/data/library_repository.dart && git commit -m "feat(library): add LibraryRepository.getAllCharts()"
```

---

### Task 7: `libraryFilterProvider` (new) with tests

**Files:**
- Create: `lib/features/library/providers/library_filter_provider.dart`
- Create: `test/features/library/providers/library_filter_provider_test.dart`

This is a near-verbatim subset of `calendar_filter_provider.dart`, with the event-types axis removed.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/providers/library_filter_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/library/providers/library_filter_provider.dart';

void main() {
  group('LibraryFilterState', () {
    test('default state is not active', () {
      const state = LibraryFilterState();
      expect(state.isActive, false);
      expect(state.activeCount, 0);
      expect(state.hiddenBandIds, isEmpty);
    });

    test('isActive flips when bands are hidden', () {
      const state = LibraryFilterState(hiddenBandIds: {7});
      expect(state.isActive, true);
      expect(state.activeCount, 1);
    });

    test('value-equality on identical hidden sets', () {
      const a = LibraryFilterState(hiddenBandIds: {1, 2});
      const b = LibraryFilterState(hiddenBandIds: {1, 2});
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different hidden sets are not equal', () {
      const a = LibraryFilterState(hiddenBandIds: {1});
      const b = LibraryFilterState(hiddenBandIds: {2});
      expect(a, isNot(equals(b)));
    });
  });

  group('LibraryFilterNotifier', () {
    test('toggleBand adds and removes a band id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(libraryFilterProvider.notifier);

      notifier.toggleBand(5);
      expect(container.read(libraryFilterProvider).hiddenBandIds, {5});

      notifier.toggleBand(5);
      expect(container.read(libraryFilterProvider).hiddenBandIds, isEmpty);
    });

    test('clear resets state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(libraryFilterProvider.notifier);
      notifier.toggleBand(1);
      notifier.toggleBand(2);
      expect(container.read(libraryFilterProvider).isActive, true);

      notifier.clear();
      expect(container.read(libraryFilterProvider).isActive, false);
      expect(container.read(libraryFilterProvider).hiddenBandIds, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/features/library/providers/library_filter_provider_test.dart
```

Expected: compile error — provider does not exist.

- [ ] **Step 3: Implement the provider**

Create `lib/features/library/providers/library_filter_provider.dart`:

```dart
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory filter state for the merged Library screen.
///
/// Bands are stored as a *hidden* set — the default state hides nothing.
/// Resets on app restart (no persistence). Mirrors the dashboard's
/// `CalendarFilterState`, minus the event-types axis.
class LibraryFilterState {
  const LibraryFilterState({this.hiddenBandIds = const {}});

  /// Band ids the user has chosen to hide on the Library list.
  final Set<int> hiddenBandIds;

  bool get isActive => hiddenBandIds.isNotEmpty;
  int get activeCount => hiddenBandIds.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryFilterState &&
          const SetEquality<int>().equals(hiddenBandIds, other.hiddenBandIds);

  @override
  int get hashCode => const SetEquality<int>().hash(hiddenBandIds);

  LibraryFilterState copyWith({Set<int>? hiddenBandIds}) =>
      LibraryFilterState(hiddenBandIds: hiddenBandIds ?? this.hiddenBandIds);
}

class LibraryFilterNotifier extends Notifier<LibraryFilterState> {
  @override
  LibraryFilterState build() => const LibraryFilterState();

  void toggleBand(int bandId) {
    final next = Set<int>.from(state.hiddenBandIds);
    if (!next.add(bandId)) next.remove(bandId);
    state = state.copyWith(hiddenBandIds: next);
  }

  void clear() => state = const LibraryFilterState();
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilterState>(
  LibraryFilterNotifier.new,
);
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/features/library/providers/library_filter_provider_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Run analyzer**

```bash
flutter analyze lib/features/library/providers/library_filter_provider.dart test/features/library/providers/library_filter_provider_test.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/providers/library_filter_provider.dart test/features/library/providers/library_filter_provider_test.dart && git commit -m "feat(library): add libraryFilterProvider (bands-only)"
```

---

### Task 8: Rewrite `LibraryNotifier` for aggregated load + band-stamped create

**Files:**
- Modify: `lib/features/library/providers/library_provider.dart`
- Create: `test/features/library/providers/library_provider_test.dart`

Two changes to `LibraryNotifier`:

1. `build()` now loads all charts via `getAllCharts()` (no band id arg) and the screen no longer calls `load(bandId)`. We keep an explicit `refresh()` method for pull-to-refresh.
2. `createChart` takes a `BandSummary band` parameter (in place of the bare `int bandId`) so the notifier can stamp the resulting `Chart` with the correct `ChartBand`. The repo call still uses `band.id` to address the per-band endpoint.

This task is mocked via `LibraryRepository` overrides — the tests don't hit the network.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/providers/library_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/library/data/library_repository.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';
import 'package:tts_bandmate/features/library/providers/library_provider.dart';

class _FakeRepo implements LibraryRepository {
  _FakeRepo({this.charts = const []});

  List<Chart> charts;
  Chart? lastCreated;
  int? lastDeletedChartId;

  @override
  Future<List<Chart>> getAllCharts() async => charts;

  @override
  Future<Chart> createChart(
    int bandId, {
    required String title,
    String? composer,
    String? description,
    double? price,
    bool isPublic = false,
  }) async {
    final newChart = Chart(
      id: 999,
      bandId: bandId,
      title: title,
      composer: composer ?? '',
      description: description ?? '',
      price: price ?? 0.0,
      isPublic: isPublic,
      uploadsCount: 0,
      uploads: const [],
      // Repo does NOT stamp band — that is the notifier's job.
      band: null,
    );
    lastCreated = newChart;
    return newChart;
  }

  @override
  Future<void> deleteChart(int bandId, int chartId) async {
    lastDeletedChartId = chartId;
  }

  // Unused in these tests; satisfy the interface with throws.
  @override
  Future<List<Chart>> getCharts(int bandId) => throw UnimplementedError();
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ProviderContainer _container(_FakeRepo repo) {
  final container = ProviderContainer(overrides: [
    libraryRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  return container;
}

const _bandA = BandSummary(id: 1, name: 'Band A', isOwner: true);

void main() {
  group('LibraryNotifier.build', () {
    test('loads all charts via getAllCharts()', () async {
      final repo = _FakeRepo(charts: [
        Chart(
          id: 10,
          bandId: 1,
          title: 'Hello',
          composer: '',
          description: '',
          price: 0,
          isPublic: false,
          uploadsCount: 0,
          uploads: const [],
          band: const ChartBand(id: 1, name: 'Band A', isPersonal: false),
        ),
      ]);
      final container = _container(repo);

      final state = await container.read(libraryProvider.future);
      expect(state.charts, hasLength(1));
      expect(state.charts.first.title, 'Hello');
    });
  });

  group('LibraryNotifier.createChart', () {
    test('inserts the new chart with a ChartBand stamped from the picked band',
        () async {
      final repo = _FakeRepo(charts: const []);
      final container = _container(repo);

      // Force build to complete first.
      await container.read(libraryProvider.future);

      final chart = await container
          .read(libraryProvider.notifier)
          .createChart(_bandA, title: 'Stardust');

      expect(chart.title, 'Stardust');
      expect(chart.band, isNotNull);
      expect(chart.band!.id, 1);
      expect(chart.band!.name, 'Band A');

      final state = container.read(libraryProvider).value!;
      expect(state.charts.any((c) => c.id == chart.id), true);
      expect(state.charts.firstWhere((c) => c.id == chart.id).band!.id, 1);
    });
  });

  group('LibraryNotifier.deleteChart', () {
    test('removes by chart id regardless of band', () async {
      final c1 = Chart(
        id: 11,
        bandId: 1,
        title: 'A',
        composer: '',
        description: '',
        price: 0,
        isPublic: false,
        uploadsCount: 0,
        uploads: const [],
        band: const ChartBand(id: 1, name: 'A', isPersonal: false),
      );
      final c2 = Chart(
        id: 12,
        bandId: 2,
        title: 'B',
        composer: '',
        description: '',
        price: 0,
        isPublic: false,
        uploadsCount: 0,
        uploads: const [],
        band: const ChartBand(id: 2, name: 'B', isPersonal: false),
      );
      final repo = _FakeRepo(charts: [c1, c2]);
      final container = _container(repo);

      await container.read(libraryProvider.future);

      await container.read(libraryProvider.notifier).deleteChart(1, 11);

      final state = container.read(libraryProvider).value!;
      expect(state.charts.map((c) => c.id), [12]);
      expect(repo.lastDeletedChartId, 11);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/features/library/providers/library_provider_test.dart
```

Expected: compile error — `createChart` signature does not accept a `BandSummary`.

- [ ] **Step 3: Rewrite `LibraryNotifier`**

Open `lib/features/library/providers/library_provider.dart`. Replace the entire `LibraryNotifier` class (and its provider declaration) with:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/models/band_summary.dart';
import '../data/library_repository.dart';
import '../data/models/chart.dart';

// ── Library state ─────────────────────────────────────────────────────────────

class LibraryState {
  const LibraryState({
    this.charts = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Chart> charts;
  final bool isLoading;
  final String? error;

  LibraryState copyWith({
    List<Chart>? charts,
    bool? isLoading,
    String? error,
  }) =>
      LibraryState(
        charts: charts ?? this.charts,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

// ── Library notifier ──────────────────────────────────────────────────────────

class LibraryNotifier extends AsyncNotifier<LibraryState> {
  @override
  Future<LibraryState> build() async {
    final repo = ref.read(libraryRepositoryProvider);
    final charts = await repo.getAllCharts();
    return LibraryState(charts: charts);
  }

  /// Re-fetches the merged charts list. Used by pull-to-refresh.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(libraryRepositoryProvider);
      final charts = await repo.getAllCharts();
      return LibraryState(charts: charts);
    });
  }

  /// Creates a new chart for [band], optimistically inserting it (sorted) into
  /// the merged list. The new chart is stamped with a [ChartBand] derived from
  /// [band] so the row avatar and band filter both work without a full reload.
  Future<Chart> createChart(
    BandSummary band,
    {
    required String title,
    String? composer,
    String? description,
    double? price,
    bool isPublic = false,
  }) async {
    final repo = ref.read(libraryRepositoryProvider);
    final created = await repo.createChart(
      band.id,
      title: title,
      composer: composer,
      description: description,
      price: price,
      isPublic: isPublic,
    );

    final stamped = Chart(
      id: created.id,
      bandId: created.bandId,
      title: created.title,
      composer: created.composer,
      description: created.description,
      price: created.price,
      isPublic: created.isPublic,
      uploadsCount: created.uploadsCount,
      uploads: created.uploads,
      band: ChartBand(
        id: band.id,
        name: band.name,
        isPersonal: band.isPersonal,
        logoUrl: band.logoUrl,
      ),
    );

    final current = state.value ?? const LibraryState();
    final updated = [...current.charts, stamped]
      ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    state = AsyncData(current.copyWith(charts: updated));
    return stamped;
  }

  /// Removes a chart from local state and the server.
  Future<void> deleteChart(int bandId, int chartId) async {
    final repo = ref.read(libraryRepositoryProvider);
    await repo.deleteChart(bandId, chartId);

    final current = state.value ?? const LibraryState();
    final updated =
        current.charts.where((c) => c.id != chartId).toList();
    state = AsyncData(current.copyWith(charts: updated));
  }
}

final libraryProvider =
    AsyncNotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);

// ── Chart detail ──────────────────────────────────────────────────────────────

/// Fetches a single [Chart] by band + chart ID.
final chartDetailProvider = FutureProvider.autoDispose
    .family<Chart, ({int bandId, int chartId})>((ref, args) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getChart(args.bandId, args.chartId);
});

// ── Chart upload state ────────────────────────────────────────────────────────

class ChartUploadState {
  const ChartUploadState({
    this.isUploading = false,
    this.progress = 0.0,
    this.error,
    this.lastUploaded,
  });

  final bool isUploading;
  final double progress;
  final String? error;
  final ChartUpload? lastUploaded;

  ChartUploadState copyWith({
    bool? isUploading,
    double? progress,
    String? Function()? error,
    ChartUpload? Function()? lastUploaded,
  }) =>
      ChartUploadState(
        isUploading: isUploading ?? this.isUploading,
        progress: progress ?? this.progress,
        error: error != null ? error() : this.error,
        lastUploaded:
            lastUploaded != null ? lastUploaded() : this.lastUploaded,
      );
}

class ChartUploadNotifier extends Notifier<ChartUploadState> {
  @override
  ChartUploadState build() => const ChartUploadState();

  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  Future<void> uploadChartFile(
    int bandId,
    int chartId, {
    required PlatformFile file,
    required String displayName,
    required int uploadTypeId,
    String? notes,
  }) async {
    state = const ChartUploadState(isUploading: true, progress: 0.0);
    try {
      final upload = await _repo.uploadChartFile(
        bandId,
        chartId,
        file: file,
        displayName: displayName,
        uploadTypeId: uploadTypeId,
        notes: notes,
        onProgress: (p) => state = state.copyWith(progress: p),
      );
      state = ChartUploadState(lastUploaded: upload);
    } catch (e) {
      state = ChartUploadState(error: e.toString());
    }
  }

  Future<void> deleteChartUpload(
    int bandId,
    int chartId,
    int uploadId,
  ) async {
    state = const ChartUploadState(isUploading: true);
    try {
      await _repo.deleteChartUpload(bandId, chartId, uploadId);
      state = const ChartUploadState();
    } catch (e) {
      state = ChartUploadState(error: e.toString());
    }
  }

  void reset() => state = const ChartUploadState();
}

final chartUploadProvider =
    NotifierProvider<ChartUploadNotifier, ChartUploadState>(
  ChartUploadNotifier.new,
);
```

- [ ] **Step 4: Run the new test**

```bash
flutter test test/features/library/providers/library_provider_test.dart
```

Expected: all three tests pass.

- [ ] **Step 5: Run analyzer**

```bash
flutter analyze lib/features/library/providers/library_provider.dart test/features/library/providers/library_provider_test.dart
```

Expected: `No issues found!`

The analyzer will flag callers of the old `createChart(int, ...)` signature; those will be fixed in Tasks 12 and 14. To keep the build green between commits, run:

```bash
flutter analyze
```

Expected: errors only in `lib/features/library/screens/create_chart_screen.dart` and `lib/features/library/screens/library_screen.dart` (the callers we're about to fix). Treat these as expected; we'll fix them in their own tasks.

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/providers/library_provider.dart test/features/library/providers/library_provider_test.dart && git commit -m "feat(library): aggregated load + band-stamped createChart"
```

---

## Phase 3 — Flutter UI primitives

### Task 9: `LibraryFilterButton` widget with test

**Files:**
- Create: `lib/features/library/widgets/library_filter_button.dart`
- Create: `test/features/library/widgets/library_filter_button_test.dart`

Visually identical to `CalendarFilterButton` — same shape, same active/inactive fill flip, same badge. Reads `libraryFilterProvider` instead of `calendarFilterProvider`.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/widgets/library_filter_button_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/library/providers/library_filter_provider.dart';
import 'package:tts_bandmate/features/library/widgets/library_filter_button.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: CupertinoApp(home: CupertinoPageScaffold(child: child)),
    );

void main() {
  testWidgets('inactive: icon visible, no badge', (tester) async {
    await tester.pumpWidget(_wrap(LibraryFilterButton(onPressed: () {})));
    expect(find.byIcon(CupertinoIcons.line_horizontal_3_decrease), findsOneWidget);
    // Badge is a Text inside a circular Container; "1" should NOT be present.
    expect(find.text('1'), findsNothing);
  });

  testWidgets('active: badge shows hidden-band count', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryFilterProvider.overrideWith(() {
            final n = LibraryFilterNotifier();
            return n;
          }),
        ],
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: Consumer(
              builder: (context, ref, _) {
                // Pre-toggle two bands so the button shows "2".
                ref.read(libraryFilterProvider.notifier).toggleBand(1);
                ref.read(libraryFilterProvider.notifier).toggleBand(2);
                return LibraryFilterButton(onPressed: () {});
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tap fires onPressed', (tester) async {
    var fired = false;
    await tester.pumpWidget(
      _wrap(LibraryFilterButton(onPressed: () => fired = true)),
    );
    await tester.tap(find.byIcon(CupertinoIcons.line_horizontal_3_decrease));
    expect(fired, true);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/features/library/widgets/library_filter_button_test.dart
```

Expected: compile error — widget does not exist.

- [ ] **Step 3: Implement the widget**

Create `lib/features/library/widgets/library_filter_button.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/library_filter_provider.dart';

/// Floating circular button that opens [LibraryFilterSheet].
///
/// Renders a small red badge with the active-band count when any band is
/// hidden. Visually mirrors `CalendarFilterButton`.
class LibraryFilterButton extends ConsumerWidget {
  const LibraryFilterButton({
    super.key,
    required this.onPressed,
    this.size = 48,
  });

  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);
    final isActive = filter.isActive;
    final count = filter.activeCount;

    final fill = isActive
        ? CupertinoColors.systemBlue.resolveFrom(context)
        : CupertinoColors.tertiarySystemBackground.resolveFrom(context);
    final iconColor = isActive
        ? CupertinoColors.white
        : CupertinoColors.systemBlue.resolveFrom(context);

    return Semantics(
      label: 'Filter library',
      hint: isActive ? '$count filters active' : 'No filters active',
      button: true,
      child: SizedBox(
        width: size + 8,
        height: size + 8,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onPressed,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    CupertinoIcons.line_horizontal_3_decrease,
                    color: iconColor,
                    size: 22,
                  ),
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: CupertinoColors.systemBackground.resolveFrom(
                          context),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test**

```bash
flutter test test/features/library/widgets/library_filter_button_test.dart
```

Expected: all three tests pass.

- [ ] **Step 5: Run analyzer**

```bash
flutter analyze lib/features/library/widgets/library_filter_button.dart test/features/library/widgets/library_filter_button_test.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/widgets/library_filter_button.dart test/features/library/widgets/library_filter_button_test.dart && git commit -m "feat(library): add LibraryFilterButton"
```

---

### Task 10: `LibraryFilterSheet` widget with test

**Files:**
- Create: `lib/features/library/widgets/library_filter_sheet.dart`
- Create: `test/features/library/widgets/library_filter_sheet_test.dart`

Trimmed copy of `CalendarFilterSheet` — drop the EVENT TYPES section and the `_EventTypeSwitch` widgets. Bands list comes from `auth.bands` (so a band with no charts still shows a toggle, matching the calendar filter's behavior).

- [ ] **Step 1: Write the failing test**

Create `test/features/library/widgets/library_filter_sheet_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/library/providers/library_filter_provider.dart';
import 'package:tts_bandmate/features/library/widgets/library_filter_sheet.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com', avatarUrl: null);

const _bandA = BandSummary(id: 1, name: 'Band A', isOwner: true);
const _bandB = BandSummary(id: 2, name: 'Band B', isOwner: false);
const _personal = BandSummary(
  id: 3,
  name: "Eddie's Band",
  isOwner: true,
  isPersonal: true,
);

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._bands);
  final List<BandSummary> _bands;
  @override
  Future<AuthState> build() async =>
      AuthAuthenticated(user: _user, bands: _bands);
}

Widget _harness({required List<BandSummary> bands}) => ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _StubAuthNotifier(bands)),
      ],
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: LibraryFilterSheet(bands: bands),
        ),
      ),
    );

void main() {
  testWidgets('renders one cell per provided band', (tester) async {
    await tester.pumpWidget(_harness(bands: const [_bandA, _bandB]));
    await tester.pump();
    expect(find.text('Band A'), findsOneWidget);
    expect(find.text('Band B'), findsOneWidget);
  });

  testWidgets('personal band renders with "Personal" label', (tester) async {
    await tester.pumpWidget(_harness(bands: const [_bandA, _personal]));
    await tester.pump();
    expect(find.text('Personal'), findsOneWidget);
    // Real band still shows its real name.
    expect(find.text('Band A'), findsOneWidget);
  });

  testWidgets('tapping a band toggles it in libraryFilterProvider',
      (tester) async {
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier(const [_bandA, _bandB])),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: CupertinoPageScaffold(
          child: LibraryFilterSheet(bands: [_bandA, _bandB]),
        ),
      ),
    ));
    await tester.pump();

    expect(container.read(libraryFilterProvider).hiddenBandIds, isEmpty);

    await tester.tap(find.text('Band A'));
    await tester.pump();

    expect(container.read(libraryFilterProvider).hiddenBandIds, {1});
  });

  testWidgets('"Clear All" only visible when isActive', (tester) async {
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier(const [_bandA])),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: CupertinoPageScaffold(
          child: LibraryFilterSheet(bands: [_bandA]),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Clear All'), findsNothing);

    container.read(libraryFilterProvider.notifier).toggleBand(1);
    await tester.pump();

    expect(find.text('Clear All'), findsOneWidget);
  });
}
```

> **Note**: if `AuthUser` requires more fields than shown above, open `lib/features/auth/data/models/auth_user.dart` and supply them. The harness is intentionally minimal — adapt the constructor call to match the real model.

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/features/library/widgets/library_filter_sheet_test.dart
```

Expected: compile error — widget does not exist.

- [ ] **Step 3: Implement the sheet**

Create `lib/features/library/widgets/library_filter_sheet.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/models/band_summary.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/widgets/band_avatar.dart';
import '../providers/library_filter_provider.dart';

/// Modal popup contents for filtering the merged Library list by band.
///
/// Lives inside `showCupertinoModalPopup`. Visually mirrors
/// `CalendarFilterSheet` minus the EVENT TYPES section.
class LibraryFilterSheet extends ConsumerWidget {
  const LibraryFilterSheet({super.key, required this.bands});

  final List<BandSummary> bands;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);
    final notifier = ref.read(libraryFilterProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.only(bottom: 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _DragHandle(),
            const SizedBox(height: 8),
            _Header(
              isActive: filter.isActive,
              onClear: () {
                HapticFeedback.selectionClick();
                notifier.clear();
              },
            ),
            const SizedBox(height: 8),
            const _SectionLabel(label: 'BANDS'),
            const SizedBox(height: 8),
            _BandsRow(
              bands: bands,
              hiddenBandIds: filter.hiddenBandIds,
              onToggle: (id) {
                HapticFeedback.selectionClick();
                notifier.toggleBand(id);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey4.resolveFrom(context),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isActive, required this.onClear});
  final bool isActive;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Center(
            child: Text(
              'Filter',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          if (isActive)
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onClear,
                child: Text(
                  'Clear All',
                  style: TextStyle(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    fontSize: 15,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}

class _BandsRow extends ConsumerWidget {
  const _BandsRow({
    required this.bands,
    required this.hiddenBandIds,
    required this.onToggle,
  });

  final List<BandSummary> bands;
  final Set<int> hiddenBandIds;
  final void Function(int bandId) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider).value;
    final user = (auth is AuthAuthenticated) ? auth.user : null;
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: bands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final band = bands[i];
          final isVisible = !hiddenBandIds.contains(band.id);
          final isPersonal = band.isPersonal;
          final avatar = isPersonal
              ? BandAvatar.forUser(
                  imageUrl: user?.avatarUrl,
                  name: user?.name ?? 'You',
                  size: 36,
                )
              : BandAvatar.forBand(band: band, size: 36);
          final label = isPersonal ? 'Personal' : band.name;
          return GestureDetector(
            onTap: () => onToggle(band.id),
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              label: label,
              selected: isVisible,
              button: true,
              child: SizedBox(
                width: 64,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: isVisible ? 1.0 : 0.4,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isVisible
                                ? CupertinoColors.systemBlue
                                    .resolveFrom(context)
                                : CupertinoColors.systemGrey5
                                    .resolveFrom(context),
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: avatar,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Opacity(
                      opacity: isVisible ? 1.0 : 0.4,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test**

```bash
flutter test test/features/library/widgets/library_filter_sheet_test.dart
```

Expected: all four tests pass.

- [ ] **Step 5: Run analyzer**

```bash
flutter analyze lib/features/library/widgets/library_filter_sheet.dart test/features/library/widgets/library_filter_sheet_test.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/widgets/library_filter_sheet.dart test/features/library/widgets/library_filter_sheet_test.dart && git commit -m "feat(library): add LibraryFilterSheet (bands-only)"
```

---

### Task 11: `CreateChartSheet` band-picker with test

**Files:**
- Create: `lib/features/library/widgets/create_chart_sheet.dart`
- Create: `test/features/library/widgets/create_chart_sheet_test.dart`

Mirrors `CreateBookingSheet` line-for-line; copy from `lib/features/bookings/widgets/create_booking_sheet.dart` and rename. Section label is "Add chart to"; the personal row reads "Personal library / Just for me, not tied to a band".

The callback signature changes slightly so the screen can stamp the optimistic insert with the full `BandSummary`:

```dart
final void Function(BandSummary band) onBandSelected;
```

- [ ] **Step 1: Write the failing test**

Create `test/features/library/widgets/create_chart_sheet_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/library/widgets/create_chart_sheet.dart';
import 'package:tts_bandmate/shared/providers/personal_band_provider.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com', avatarUrl: null);
const _bandA = BandSummary(id: 1, name: 'Band A', isOwner: true);
const _bandB = BandSummary(id: 2, name: 'Band B', isOwner: false);
const _personal = BandSummary(
  id: 99,
  name: "Eddie's Band",
  isOwner: true,
  isPersonal: true,
);

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._bands);
  final List<BandSummary> _bands;
  @override
  Future<AuthState> build() async =>
      AuthAuthenticated(user: _user, bands: _bands);
}

class _StubPersonalBandNotifier extends PersonalBandNotifier {
  _StubPersonalBandNotifier({required this.willSucceed});
  final bool willSucceed;

  @override
  Future<BandSummary> ensureExists() async {
    if (!willSucceed) {
      throw StateError('boom');
    }
    return _personal;
  }
}

Widget _harness({
  required List<BandSummary> bands,
  required void Function(BandSummary) onBandSelected,
  bool personalSucceeds = true,
}) =>
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _StubAuthNotifier(bands)),
        personalBandProvider.overrideWith(
            () => _StubPersonalBandNotifier(willSucceed: personalSucceeds)),
      ],
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: CreateChartSheet(onBandSelected: onBandSelected),
        ),
      ),
    );

void main() {
  testWidgets('multi-band: shows real bands and Personal row', (tester) async {
    await tester.pumpWidget(_harness(
      bands: const [_bandA, _bandB],
      onBandSelected: (_) {},
    ));
    await tester.pump();

    expect(find.text('Band A'), findsOneWidget);
    expect(find.text('Band B'), findsOneWidget);
    expect(find.text('Personal library'), findsOneWidget);
  });

  testWidgets('tapping a band invokes onBandSelected with that band',
      (tester) async {
    BandSummary? picked;
    await tester.pumpWidget(_harness(
      bands: const [_bandA, _bandB],
      onBandSelected: (b) => picked = b,
    ));
    await tester.pump();

    await tester.tap(find.text('Band B'));
    await tester.pump();
    expect(picked?.id, _bandB.id);
  });

  testWidgets('tapping Personal calls ensureExists then onBandSelected',
      (tester) async {
    BandSummary? picked;
    await tester.pumpWidget(_harness(
      bands: const [_bandA],
      onBandSelected: (b) => picked = b,
    ));
    await tester.pump();

    await tester.tap(find.text('Personal library'));
    await tester.pump(); // start ensureExists
    await tester.pump(const Duration(milliseconds: 50)); // resolve

    expect(picked?.id, _personal.id);
    expect(picked?.isPersonal, true);
  });

  testWidgets('personal failure shows error and keeps sheet open',
      (tester) async {
    await tester.pumpWidget(_harness(
      bands: const [_bandA],
      onBandSelected: (_) => fail('should not be called'),
      personalSucceeds: false,
    ));
    await tester.pump();

    await tester.tap(find.text('Personal library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining("Couldn't"), findsOneWidget);
    // Sheet still rendered.
    expect(find.text('Band A'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/features/library/widgets/create_chart_sheet_test.dart
```

Expected: compile error — widget does not exist.

- [ ] **Step 3: Implement the sheet**

Create `lib/features/library/widgets/create_chart_sheet.dart` (this is `CreateBookingSheet` adapted: callback gives the full `BandSummary` and copy mentions "chart" instead of "booking"):

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/personal_band_provider.dart';
import '../../../shared/widgets/band_identity_chip.dart';
import '../../auth/data/models/band_summary.dart';
import '../../auth/providers/auth_provider.dart';

/// A sheet shown when the user taps "+" to add a chart to the merged library.
///
/// Real bands are listed at the top; tapping one invokes [onBandSelected]
/// with that [BandSummary]. A "Personal library" row at the bottom creates
/// the personal band lazily (via `POST /bands/solo`) on first use, then
/// invokes [onBandSelected] with the personal band.
///
/// Callers are responsible for dismissing the sheet and navigating to the
/// chart form after [onBandSelected] fires.
class CreateChartSheet extends ConsumerStatefulWidget {
  const CreateChartSheet({super.key, required this.onBandSelected});

  final void Function(BandSummary band) onBandSelected;

  @override
  ConsumerState<CreateChartSheet> createState() => _CreateChartSheetState();
}

class _CreateChartSheetState extends ConsumerState<CreateChartSheet> {
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
      widget.onBandSelected(personal);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _personalError = "Couldn't set up personal library. Try again.";
      });
    } finally {
      if (mounted) setState(() => _personalLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider).value;
    // Only expose non-personal bands in the list — the personal band is
    // selected indirectly via the "Personal library" row.
    final bands = (auth is AuthAuthenticated)
        ? auth.bands.where((b) => !b.isPersonal).toList()
        : <BandSummary>[];

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _GrabHandle(),
            const SizedBox(height: 8),
            if (bands.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  'Add chart to',
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
                  onTap: () => widget.onBandSelected(band),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  height: 0.5,
                  color: CupertinoColors.separator.resolveFrom(context),
                ),
              ),
            ],
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

class _PersonalRow extends StatelessWidget {
  const _PersonalRow({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
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
                    'Personal library',
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
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
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

- [ ] **Step 4: Run the test**

```bash
flutter test test/features/library/widgets/create_chart_sheet_test.dart
```

Expected: all four tests pass.

- [ ] **Step 5: Run analyzer**

```bash
flutter analyze lib/features/library/widgets/create_chart_sheet.dart test/features/library/widgets/create_chart_sheet_test.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/widgets/create_chart_sheet.dart test/features/library/widgets/create_chart_sheet_test.dart && git commit -m "feat(library): add CreateChartSheet (band picker)"
```

---

## Phase 4 — Wire it together

### Task 12: Update `CreateChartScreen` to take a `BandSummary`

**Files:**
- Modify: `lib/features/library/screens/create_chart_screen.dart`
- Modify: `lib/core/config/router.dart`

The library screen needs to thread the picked `BandSummary` (not just a band id) into `CreateChartScreen` so the optimistic insert can stamp the new chart's `band` correctly. The `extra` parameter on the existing `/library/new` route changes from `int` to `BandSummary`. There are no other callers of `/library/new`.

- [ ] **Step 1: Update `CreateChartScreen` constructor and `_save()`**

In `lib/features/library/screens/create_chart_screen.dart`:

1. Add to imports near the top:

```dart
import '../../auth/data/models/band_summary.dart';
```

2. Change the constructor field from `bandId` to `band`:

```dart
class CreateChartScreen extends ConsumerStatefulWidget {
  const CreateChartScreen({super.key, required this.band});

  final BandSummary band;

  @override
  ConsumerState<CreateChartScreen> createState() => _CreateChartScreenState();
}
```

3. Inside `_save()`, change the `createChart` call from `widget.bandId` to `widget.band`:

```dart
      final chart = await ref.read(libraryProvider.notifier).createChart(
            widget.band,
            title: title,
            composer: _composerController.text.trim().isEmpty
                ? null
                : _composerController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            price: price,
            isPublic: _isPublic,
          );
```

- [ ] **Step 2: Update the GoRouter `/library/new` builder**

Open `lib/core/config/router.dart` and find:

```dart
      GoRoute(
        path: '/library/new',
        builder: (_, state) => CreateChartScreen(
          bandId: state.extra as int,
        ),
      ),
```

Replace with:

```dart
      GoRoute(
        path: '/library/new',
        builder: (_, state) => CreateChartScreen(
          band: state.extra as BandSummary,
        ),
      ),
```

Add the import at the top of `router.dart` (alongside the existing library imports):

```dart
import '../../features/auth/data/models/band_summary.dart';
```

- [ ] **Step 3: Run analyzer**

```bash
flutter analyze lib/features/library/screens/create_chart_screen.dart lib/core/config/router.dart
```

Expected: `No issues found!` for these two files. The library screen will still error because it hasn't been rewritten — that lands next.

- [ ] **Step 4: Commit**

```bash
git add lib/features/library/screens/create_chart_screen.dart lib/core/config/router.dart && git commit -m "feat(library): thread BandSummary through CreateChartScreen"
```

---

### Task 13: Library screen test (failing) — covers the merged behavior

**Files:**
- Create: `test/features/library/screens/library_screen_test.dart`

We write the screen test before the rewrite so it captures the merged behavior. The test stubs the auth and library repository providers with `ProviderContainer` overrides.

- [ ] **Step 1: Write the failing screen test**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/library/data/library_repository.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';
import 'package:tts_bandmate/features/library/providers/library_filter_provider.dart';
import 'package:tts_bandmate/features/library/providers/library_provider.dart';
import 'package:tts_bandmate/features/library/screens/library_screen.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com', avatarUrl: null);
const _bandA = BandSummary(id: 1, name: 'Band A', isOwner: true);
const _bandB = BandSummary(id: 2, name: 'Band B', isOwner: false);

Chart _chart({required int id, required String title, required BandSummary band}) =>
    Chart(
      id: id,
      bandId: band.id,
      title: title,
      composer: '',
      description: '',
      price: 0,
      isPublic: false,
      uploadsCount: 0,
      uploads: const [],
      band: ChartBand(
        id: band.id,
        name: band.name,
        isPersonal: band.isPersonal,
      ),
    );

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._bands);
  final List<BandSummary> _bands;
  @override
  Future<AuthState> build() async =>
      AuthAuthenticated(user: _user, bands: _bands);
}

class _FakeRepo implements LibraryRepository {
  _FakeRepo(this._charts);
  final List<Chart> _charts;
  @override
  Future<List<Chart>> getAllCharts() async => _charts;
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

GoRouter _testRouter() => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
    ]);

Widget _harness({
  required List<BandSummary> bands,
  required List<Chart> charts,
  ProviderContainer? container,
}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier(bands)),
      libraryRepositoryProvider.overrideWithValue(_FakeRepo(charts)),
    ],
    child: CupertinoApp.router(routerConfig: _testRouter()),
  );
}

void main() {
  testWidgets('renders charts from multiple bands sorted alphabetically',
      (tester) async {
    final charts = [
      _chart(id: 1, title: 'Caravan', band: _bandA),
      _chart(id: 2, title: 'Body and Soul', band: _bandB),
      _chart(id: 3, title: 'Autumn Leaves', band: _bandA),
    ];

    await tester.pumpWidget(
      _harness(bands: const [_bandA, _bandB], charts: charts),
    );
    await tester.pumpAndSettle();

    expect(find.text('Autumn Leaves'), findsOneWidget);
    expect(find.text('Body and Soul'), findsOneWidget);
    expect(find.text('Caravan'), findsOneWidget);
  });

  testWidgets('filtering a band hides only that band\'s charts',
      (tester) async {
    final charts = [
      _chart(id: 1, title: 'Mine', band: _bandA),
      _chart(id: 2, title: 'Yours', band: _bandB),
    ];

    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier(const [_bandA, _bandB])),
      libraryRepositoryProvider.overrideWithValue(_FakeRepo(charts)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: CupertinoApp.router(routerConfig: _testRouter()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Yours'), findsOneWidget);

    // Hide Band A.
    container.read(libraryFilterProvider.notifier).toggleBand(_bandA.id);
    await tester.pumpAndSettle();

    expect(find.text('Mine'), findsNothing);
    expect(find.text('Yours'), findsOneWidget);
  });

  testWidgets('all-bands-hidden empty state shows Show all action',
      (tester) async {
    final charts = [_chart(id: 1, title: 'Mine', band: _bandA)];

    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier(const [_bandA])),
      libraryRepositoryProvider.overrideWithValue(_FakeRepo(charts)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: CupertinoApp.router(routerConfig: _testRouter()),
    ));
    await tester.pumpAndSettle();

    container.read(libraryFilterProvider.notifier).toggleBand(_bandA.id);
    await tester.pumpAndSettle();

    expect(find.textContaining('All bands hidden'), findsOneWidget);
    expect(find.text('Show all'), findsOneWidget);

    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();

    expect(container.read(libraryFilterProvider).isActive, false);
    expect(find.text('Mine'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/features/library/screens/library_screen_test.dart
```

Expected: failure — the screen still uses the old `selectedBandProvider`-based shell, so the override path doesn't exercise `getAllCharts()`. (Specifically: tests fail with the "No band selected" error view, and the all-hidden empty state doesn't exist yet.)

- [ ] **Step 3: Commit the failing test**

```bash
git add test/features/library/screens/library_screen_test.dart && git commit -m "test(library): add merged-screen behavior tests (failing)"
```

---

### Task 14: Rewrite `LibraryScreen`

**Files:**
- Modify: `lib/features/library/screens/library_screen.dart`

This is the biggest change. The new screen:
- Drops the `_LibraryScreenState` outer band-resolution shell. The screen mounts and watches `libraryProvider` directly.
- Removes the colored-initials avatar helpers (`_avatarColor`, `_avatarInitials`, `_kAvatarPalette`).
- `_ChartRow` uses `BandAvatar.forBand(band: ...)` (or `BandAvatar.forUser(...)` for personal charts) with size 38.
- Applies `libraryFilterProvider` before `_buildGroups`.
- Stacks `LibraryFilterButton` in the top-right (right inset = `_kIndexWidth + 4`, top inset = nav-bar-clear ~96).
- Adds an "all bands hidden" empty state branch with a "Show all" action.
- Routes `+` through a new `_handleAddTapped` method that decides between picker, direct push, and personal-only shortcut.
- After `CreateChartScreen.pop(chart)` completes via `context.push('/library/new', extra: band)`, fetches the awaited result and (when non-null) navigates to chart detail.

Because of the size of this change, the steps describe the swap rather than reproducing the entire 800+ line file. The new `_LibraryBodyState` becomes the screen's only stateful piece, and it accepts no constructor args (the band is no longer needed).

- [ ] **Step 1: Replace the file contents with the rewritten screen**

Open `lib/features/library/screens/library_screen.dart` and replace the entire file with:

```dart
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../../auth/data/models/band_summary.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/providers/personal_band_provider.dart';
import '../../../shared/widgets/band_avatar.dart';
import '../data/models/chart.dart';
import '../providers/library_filter_provider.dart';
import '../providers/library_provider.dart';
import '../widgets/create_chart_sheet.dart';
import '../widgets/library_filter_button.dart';
import '../widgets/library_filter_sheet.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const double _kRowHeight = 56.0;
const double _kSectionHeaderHeight = 20.0;
const double _kSearchBarHeight = 56.0;
const double _kIndexWidth = 16.0;
const double _kAvatarSize = 38.0;
const double _kFilterButtonTopInset = 8.0;

const List<String> _kAlphabetLetters = [
  '#',
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
];

// ── Helpers ───────────────────────────────────────────────────────────────────

String _sectionKey(String title) {
  if (title.isEmpty) return '#';
  final first = title[0].toUpperCase();
  final code = first.codeUnitAt(0);
  if (code >= 65 && code <= 90) return first;
  return '#';
}

Map<String, List<Chart>> _buildGroups(List<Chart> charts) {
  final sorted = List<Chart>.from(charts)
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  final map = <String, List<Chart>>{};
  for (final chart in sorted) {
    final key = _sectionKey(chart.title);
    (map[key] ??= []).add(chart);
  }

  final ordered = <String, List<Chart>>{};
  for (final letter in _kAlphabetLetters) {
    if (map.containsKey(letter)) ordered[letter] = map[letter]!;
  }
  return ordered;
}

// ── Top-level screen ──────────────────────────────────────────────────────────

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  String _query = '';
  String? _overlayLetter;
  Timer? _overlayTimer;
  bool _addInProgress = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _overlayTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() =>
      ref.read(libraryProvider.notifier).refresh();

  // ── Search ──────────────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim());
  }

  // ── Delete ───────────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteChart(BuildContext context, Chart chart) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Chart'),
        content: Text(
            'Are you sure you want to delete "${chart.title}"? This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(libraryProvider.notifier)
          .deleteChart(chart.bandId, chart.id);
    } catch (e) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Delete Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  // ── Alphabet scrubber ────────────────────────────────────────────────────────

  void _onIndexSelect(
    double dy,
    double indexHeight,
    Map<String, List<Chart>> groups,
  ) {
    final letterCount = _kAlphabetLetters.length;
    final fraction = (dy / indexHeight).clamp(0.0, 0.9999);
    final idx = (fraction * letterCount).floor();
    final tappedLetter = _kAlphabetLetters[idx.clamp(0, letterCount - 1)];

    final sectionKeys = groups.keys.toList();
    String? targetKey;
    for (final letter
        in _kAlphabetLetters.skip(_kAlphabetLetters.indexOf(tappedLetter))) {
      if (sectionKeys.contains(letter)) {
        targetKey = letter;
        break;
      }
    }
    targetKey ??= sectionKeys.isNotEmpty ? sectionKeys.last : null;

    if (targetKey != null) {
      _showOverlay(targetKey);
      _jumpToSection(targetKey, groups);
    }
  }

  void _showOverlay(String letter) {
    _overlayTimer?.cancel();
    setState(() => _overlayLetter = letter);
    _overlayTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _overlayLetter = null);
    });
  }

  void _jumpToSection(String targetKey, Map<String, List<Chart>> groups) {
    const navBarOffset = 96.0;
    double offset = navBarOffset;
    for (final key in groups.keys) {
      if (key == targetKey) break;
      offset += _kSectionHeaderHeight;
      offset += groups[key]!.length * _kRowHeight;
    }

    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  // ── Filter sheet ────────────────────────────────────────────────────────────

  void _openFilterSheet() {
    final auth = ref.read(authProvider).value;
    final bands = (auth is AuthAuthenticated) ? auth.bands : <BandSummary>[];
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => LibraryFilterSheet(bands: bands),
    );
  }

  // ── Add flow ────────────────────────────────────────────────────────────────

  Future<void> _handleAddTapped() async {
    if (_addInProgress) return;
    setState(() => _addInProgress = true);
    try {
      final auth = ref.read(authProvider).value;
      if (auth is! AuthAuthenticated) return;

      final realBands = auth.bands.where((b) => !b.isPersonal).toList();
      final personal = auth.bands.firstWhere(
        (b) => b.isPersonal,
        orElse: () => const BandSummary(id: -1, name: '', isOwner: false),
      );

      // 0 real bands → ensure personal and push form.
      if (realBands.isEmpty) {
        try {
          final p = personal.id != -1
              ? personal
              : await ref.read(personalBandProvider.notifier).ensureExists();
          await _pushCreateAndMaybeOpenDetail(p);
        } catch (e) {
          if (mounted) {
            await showCupertinoDialog<void>(
              context: context,
              builder: (ctx) => CupertinoAlertDialog(
                title: const Text('Could not create chart'),
                content: const Text("Couldn't set up personal library."),
                actions: [
                  CupertinoDialogAction(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        }
        return;
      }

      // 1 real band, no personal yet → skip the sheet.
      if (realBands.length == 1 && personal.id == -1) {
        await _pushCreateAndMaybeOpenDetail(realBands.single);
        return;
      }

      // Otherwise → show the picker.
      if (!mounted) return;
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetCtx) => CreateChartSheet(
          onBandSelected: (band) {
            Navigator.of(sheetCtx).pop();
            _pushCreateAndMaybeOpenDetail(band);
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _addInProgress = false);
    }
  }

  Future<void> _pushCreateAndMaybeOpenDetail(BandSummary band) async {
    final result = await context.push<Chart>('/library/new', extra: band);
    if (!mounted || result == null) return;
    context.push('/library/${result.id}', extra: result.bandId);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);
    final filter = ref.watch(libraryFilterProvider);
    final isSearching = _query.isNotEmpty;

    return CupertinoPageScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;

          return Center(
            child: SizedBox(
              width: maxWidth,
              child: Column(
                children: [
                  Expanded(
                    child: libraryAsync.when(
                      loading: () =>
                          const Center(child: CupertinoActivityIndicator()),
                      error: (e, _) => CustomScrollView(
                        slivers: [
                          _buildNavBar(context),
                          SliverFillRemaining(
                            child: ErrorView(
                              message: ErrorView.friendlyMessage(e),
                              onRetry: _refresh,
                            ),
                          ),
                        ],
                      ),
                      data: (state) {
                        if (state.charts.isEmpty) {
                          return CustomScrollView(
                            slivers: [
                              _buildNavBar(context),
                              const SliverFillRemaining(
                                child: EmptyStateView(
                                  icon: CupertinoIcons.music_note_list,
                                  title: 'No charts in your library',
                                  subtitle:
                                      'Charts added to any of your bands will appear here.',
                                ),
                              ),
                            ],
                          );
                        }

                        // Apply band filter.
                        final visible = state.charts
                            .where((c) =>
                                c.band == null ||
                                !filter.hiddenBandIds.contains(c.band!.id))
                            .toList();

                        // All bands hidden → distinct empty state.
                        if (visible.isEmpty && filter.isActive) {
                          return Stack(
                            children: [
                              CustomScrollView(
                                slivers: [
                                  _buildNavBar(context),
                                  SliverFillRemaining(
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            CupertinoIcons.eye_slash,
                                            size: 48,
                                            color: CupertinoColors.secondaryLabel
                                                .resolveFrom(context),
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                              'All bands hidden by filter'),
                                          const SizedBox(height: 12),
                                          CupertinoButton(
                                            onPressed: () => ref
                                                .read(libraryFilterProvider
                                                    .notifier)
                                                .clear(),
                                            child: const Text('Show all'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              _filterButtonOverlay(),
                            ],
                          );
                        }

                        final groups = _buildGroups(visible);

                        if (isSearching) {
                          final q = _query.toLowerCase();
                          final filtered = visible
                              .where((c) =>
                                  c.title.toLowerCase().contains(q) ||
                                  c.composer.toLowerCase().contains(q))
                              .toList()
                            ..sort((a, b) => a.title
                                .toLowerCase()
                                .compareTo(b.title.toLowerCase()));

                          return Stack(children: [
                            CustomScrollView(
                              slivers: [
                                _buildNavBar(context),
                                CupertinoSliverRefreshControl(
                                    onRefresh: _refresh),
                                if (filtered.isEmpty)
                                  const SliverFillRemaining(
                                    child: Center(
                                      child: Text('No matching charts',
                                          style: TextStyle(
                                              color: CupertinoColors.secondaryLabel)),
                                    ),
                                  )
                                else
                                  SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final chart = filtered[index];
                                        return _ChartRow(
                                          chart: chart,
                                          showSeparator:
                                              index < filtered.length - 1,
                                          onTap: () => context.push(
                                              '/library/${chart.id}',
                                              extra: chart.bandId),
                                          onDelete: () =>
                                              _confirmDeleteChart(context, chart),
                                        );
                                      },
                                      childCount: filtered.length,
                                    ),
                                  ),
                                const SliverToBoxAdapter(
                                    child: SizedBox(height: 16)),
                              ],
                            ),
                            _filterButtonOverlay(),
                          ]);
                        }

                        return Stack(
                          children: [
                            _GroupedScrollView(
                              groups: groups,
                              onRefresh: _refresh,
                              scrollController: _scrollController,
                              navBarBuilder: _buildNavBar,
                              onDeleteChart: (chart) =>
                                  _confirmDeleteChart(context, chart),
                            ),
                            Positioned(
                              top: 0,
                              bottom: 0,
                              right: 0,
                              width: _kIndexWidth,
                              child: _AlphabetIndex(
                                groups: groups,
                                onSelect: (dy, height) =>
                                    _onIndexSelect(dy, height, groups),
                              ),
                            ),
                            _filterButtonOverlay(),
                            if (_overlayLetter != null)
                              Center(
                                child: _LetterOverlay(letter: _overlayLetter!),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  _BottomSearchBar(
                    controller: _searchController,
                    onChanged: _onQueryChanged,
                    onAdd: _addInProgress ? null : _handleAddTapped,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavBar(BuildContext context) {
    return const CupertinoSliverNavigationBar(
      largeTitle: Text('Library'),
    );
  }

  Widget _filterButtonOverlay() => Positioned(
        top: _kFilterButtonTopInset,
        right: _kIndexWidth + 4,
        child: LibraryFilterButton(onPressed: _openFilterSheet),
      );
}

// ── Grouped scroll view ───────────────────────────────────────────────────────

class _GroupedScrollView extends StatelessWidget {
  const _GroupedScrollView({
    required this.groups,
    required this.onRefresh,
    required this.scrollController,
    required this.navBarBuilder,
    required this.onDeleteChart,
  });

  final Map<String, List<Chart>> groups;
  final Future<void> Function() onRefresh;
  final ScrollController scrollController;
  final Widget Function(BuildContext) navBarBuilder;
  final void Function(Chart) onDeleteChart;

  @override
  Widget build(BuildContext context) {
    final List<({String letter, Chart? chart, bool isLastInSection})> items =
        [];

    for (final entry in groups.entries) {
      items.add((letter: entry.key, chart: null, isLastInSection: false));
      for (var i = 0; i < entry.value.length; i++) {
        items.add((
          letter: entry.key,
          chart: entry.value[i],
          isLastInSection: i == entry.value.length - 1,
        ));
      }
    }

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: onRefresh),
        navBarBuilder(context),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              if (item.chart == null) {
                return _SectionHeader(letter: item.letter);
              }
              final chart = item.chart!;
              return _ChartRow(
                chart: chart,
                showSeparator: !item.isLastInSection,
                onTap: () => context.push('/library/${chart.id}',
                    extra: chart.bandId),
                onDelete: () => onDeleteChart(chart),
              );
            },
            childCount: items.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.letter});
  final String letter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kSectionHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            letter,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chart row ─────────────────────────────────────────────────────────────────

class _ChartRow extends ConsumerWidget {
  const _ChartRow({
    required this.chart,
    required this.showSeparator,
    this.onTap,
    this.onDelete,
  });

  final Chart chart;
  final bool showSeparator;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider).value;
    final user = (auth is AuthAuthenticated) ? auth.user : null;
    final band = chart.band;
    final isPersonal = band?.isPersonal == true;

    Widget avatar;
    if (band == null) {
      // Defensive fallback if a chart somehow lacks band metadata.
      avatar = SizedBox(
        width: _kAvatarSize,
        height: _kAvatarSize,
        child: BandAvatar.forUser(
          imageUrl: user?.avatarUrl,
          name: user?.name ?? '?',
          size: _kAvatarSize,
        ),
      );
    } else if (isPersonal) {
      avatar = BandAvatar.forUser(
        imageUrl: user?.avatarUrl,
        name: user?.name ?? band.name,
        size: _kAvatarSize,
      );
    } else {
      // BandAvatar.forBand needs a BandSummary; build one from ChartBand.
      avatar = BandAvatar.forBand(
        band: BandSummary(
          id: band.id,
          name: band.name,
          isOwner: false,
          isPersonal: band.isPersonal,
          logoUrl: band.logoUrl,
        ),
        size: _kAvatarSize,
      );
    }

    return Semantics(
      button: true,
      label: '${chart.title}, by ${chart.composer}. Long press to delete.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onDelete,
        child: Container(
          height: _kRowHeight,
          decoration: showSeparator
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: CupertinoColors.separator.resolveFrom(context),
                      width: 0.5,
                    ),
                  ),
                )
              : null,
          child: Row(
            children: [
              const SizedBox(width: 16),
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      chart.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (chart.composer.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        chart.composer,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
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
}

// ── Alphabet scrubber ─────────────────────────────────────────────────────────

class _AlphabetIndex extends StatelessWidget {
  const _AlphabetIndex({required this.groups, required this.onSelect});

  final Map<String, List<Chart>> groups;
  final void Function(double dy, double height) onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onSelect(d.localPosition.dy, totalHeight),
          onVerticalDragUpdate: (d) => onSelect(d.localPosition.dy, totalHeight),
          child: SizedBox(
            width: _kIndexWidth,
            height: totalHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _kAlphabetLetters.map((letter) {
                final isActive = groups.containsKey(letter);
                return Flexible(
                  child: Center(
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? CupertinoColors.activeBlue.resolveFrom(context)
                            : CupertinoColors.tertiaryLabel.resolveFrom(context),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _LetterOverlay extends StatelessWidget {
  const _LetterOverlay({required this.letter});
  final String letter;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xCC1C1C1E),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.white,
          ),
        ),
      ),
    );
  }
}

// ── Bottom search bar ─────────────────────────────────────────────────────────

class _BottomSearchBar extends StatelessWidget {
  const _BottomSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onAdd,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kSearchBarHeight,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: CupertinoSearchTextField(
              controller: controller,
              onChanged: onChanged,
              placeholder: 'Search',
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Add chart',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onAdd,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: onAdd == null
                      ? CupertinoColors.systemGrey4.resolveFrom(context)
                      : CupertinoColors.activeBlue.resolveFrom(context),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  CupertinoIcons.plus,
                  color: CupertinoColors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

Note: the `HapticFeedback` import was carried over even though the new screen file doesn't use it directly — leave it out unless you add a haptic on the `+` button. The above intentionally drops `selectedBandProvider` (unused now) and the initials helpers.

- [ ] **Step 2: Run the merged-screen tests**

```bash
flutter test test/features/library/screens/library_screen_test.dart
```

Expected: all three tests pass.

- [ ] **Step 3: Run the full library test suite to ensure no regressions**

```bash
flutter test test/features/library
```

Expected: every test in `test/features/library` passes.

- [ ] **Step 4: Run the analyzer over the whole project**

```bash
flutter analyze
```

Expected: `No issues found!` (the previous "errors only in callers" should now be resolved).

- [ ] **Step 5: Manual smoke check (per project CLAUDE.md UI rule)**

The command palette test is not a substitute for opening the app. Run on Linux desktop:

```bash
flutter run -d linux --dart-define=BASE_URL=http://localhost:8715
```

Confirm in the running app:
1. With a multi-band test account, the Library screen shows charts from every band, with the band's avatar on each row.
2. Tapping the floating filter button (top-right) opens the sheet; toggling a band hides its charts and updates the alphabet scrubber. Tapping "Clear All" restores them.
3. Hiding all bands shows the "All bands hidden" empty state with a "Show all" button.
4. Tapping `+` with multiple bands opens `CreateChartSheet`; picking a band lands on the new-chart form for that band.
5. After saving a new chart, the app navigates straight to chart detail (so a PDF can be uploaded).
6. With a single-band test account, tapping `+` skips the sheet and goes directly to the form.

If anything fails the smoke check, fix and re-run before committing. If the smoke check is not feasible, state explicitly that the manual test was not run, in the commit body.

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/screens/library_screen.dart && git commit -m "feat(library): aggregate charts across bands with bands-only filter"
```

---

## Self-review (post-write)

After writing the plan, the author runs through this checklist:

1. **Spec coverage:** every spec section has a task — backend endpoint (Tasks 1–3), `Chart` model + `band` (Task 5), `getAllCharts` (Task 6), filter provider (Task 7), `LibraryNotifier` rewrite + `BandSummary` create (Task 8, 12), filter button (Task 9), filter sheet (Task 10), `CreateChartSheet` (Task 11), router glue (Task 12), screen rewrite (Task 14). The `LibraryScreen` task covers band avatar swap, all-hidden empty state, push-to-detail. ✓

2. **Placeholder scan:** no "TBD"/"TODO"/"implement appropriate handling" text in the steps. Code blocks are concrete. ✓

3. **Type consistency:**
    - `createChart` takes `BandSummary` everywhere it appears (notifier in Task 8, screen in Task 12, router in Task 12). ✓
    - `ChartBand` has `id`, `name`, `isPersonal`, `logoUrl` — same fields used in tests, model, and stamping. ✓
    - `LibraryFilterState` uses `hiddenBandIds` (not `hidden`) consistently. ✓
    - `getAllCharts()` is the method name everywhere. ✓
    - `LibraryNotifier.createChart` takes `BandSummary` as first positional argument with named params; `_pushCreateAndMaybeOpenDetail` passes a `BandSummary` to `context.push('/library/new', extra: band)` and the router casts `state.extra as BandSummary`. ✓
    - `CreateChartScreen.band` field aligns with the router cast. ✓

The plan is internally consistent. Ready for execution.
