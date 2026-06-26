# Finances Trends (Mobile) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only "Trends" tab to the mobile Finances screen: a per-month paid/unpaid/forecast/band-cut chart with an always-visible booking-count row, a year selector, and time travel (an "As of" date + "vs Current" compare with deltas) — backed by a new server-bucketed endpoint.

**Architecture:** A new Laravel mobile endpoint (`GET /api/mobile/bands/{band}/finances/trends`) reuses the existing snapshot-aware `FinanceServices::getPaidUnpaid($band, $snapshotDate)` + `addNetAmount`, buckets bookings by month server-side, and returns a compact per-month cents series (+ optional `current_months` when comparing) and `available_years`. The Flutter app adds a `FinanceTrends` model, `fetchTrends` repo method, a `trendsProvider` family, and a `TrendsView` (chart + count row + summary cards + controls) rendered as a 4th segment in `FinancesScreen`. The chart uses `fl_chart`, mirroring `lib/features/stats/screens/widgets/earnings_bar_chart.dart`.

**Tech Stack:** Laravel (PHP 8, Eloquent), Pest/PHPUnit; Flutter (Dart), Riverpod v2 `AsyncNotifierProvider.family`, `fl_chart`, `intl`.

**Repos:** Backend tasks run in `/home/eddie/github/TTS` (PHP via `docker compose exec app …`; PRs target `staging`). Mobile tasks run in this worktree `/home/eddie/github/tts_bandmate/.claude/worktrees/feat+event-media-upload` on branch `feat/finances-trends-mobile` (PR targets `main`). This branch is already rebased on the merged Revenue work, so the Finances screen has `_FinancesTab { unpaid, paid, revenue }`.

---

## File Structure

**Backend (`TTS`):**
- Modify: `app/Http/Controllers/Api/Mobile/FinancesController.php` — add `trends()`.
- Modify: `routes/api.php` — register `mobile.finances.trends` in the `mobile.band:read:bookings` group.
- Create: `tests/Feature/Api/Mobile/FinanceTrendsTest.php`.

**Mobile (`TTS-App`):**
- Create: `lib/features/finances/data/models/finance_trends.dart` — `TrendMonth` + `FinanceTrends` with derived totals/deltas.
- Modify: `lib/features/finances/data/finances_repository.dart` — add `fetchTrends`.
- Modify: `lib/core/network/api_endpoints.dart` — add `mobileBandFinancesTrends`.
- Modify: `lib/features/finances/providers/finances_provider.dart` — add `TrendsParams` + `trendsProvider`.
- Create: `lib/features/finances/screens/widgets/trends_chart.dart` — `fl_chart` bars+lines, tap tooltip.
- Create: `lib/features/finances/screens/widgets/trends_count_row.dart` — per-month count row.
- Create: `lib/features/finances/screens/widgets/trends_view.dart` — controls + chart + count row + cards + states.
- Modify: `lib/features/finances/screens/finances_screen.dart` — add `trends` tab + wiring.
- Create: `test/features/finances/finance_trends_test.dart` — model unit tests.
- Create: `test/features/finances/trends_provider_test.dart` — provider test.

---

## Backend Tasks (run in `/home/eddie/github/TTS`)

### Task 1: Trends endpoint

**Files:**
- Modify: `app/Http/Controllers/Api/Mobile/FinancesController.php`
- Modify: `routes/api.php` (the `mobile.band:read:bookings` group, near the `mobile.finances.*` routes ~line 258-263)
- Test: `tests/Feature/Api/Mobile/FinanceTrendsTest.php`

- [ ] **Step 1: Write the failing feature test**

Create `tests/Feature/Api/Mobile/FinanceTrendsTest.php`. **Read the existing `tests/Feature/Api/Mobile/FinanceRevenueTest.php` first** and copy its exact patterns for: band creation, granting `read:bookings` band access, token/`X-Band-ID` auth, and the 403-for-non-member expectation. Use the same payment/booking factory helpers those finance tests use (a booking needs a band, a price, events with dates for `start_date`, and payments for `amount_paid`). The behaviors:

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\Bands;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class FinanceTrendsTest extends TestCase
{
    use RefreshDatabase;

    // Copy auth/factory helpers from FinanceRevenueTest (actingMember etc).

    public function test_buckets_paid_unpaid_forecast_net_count_by_month_in_cents(): void
    {
        // Arrange a band with the active payout config (e.g. percentage band cut)
        // and 2 bookings in the requested year, in different months, with known
        // price / amount_paid and a start_date (first event date). One cancelled
        // booking that must be EXCLUDED.
        // Assert response 200 with months[] of length 12, the right month rows
        // carrying paid/unpaid/forecast/net/count in CENTS, others zero-filled,
        // and the cancelled booking not counted.
    }

    public function test_available_years_lists_distinct_booking_years_desc(): void
    {
        // Bookings spanning 2024, 2025, 2026 → available_years == [2026,2025,2024]
        // regardless of the ?year filter.
    }

    public function test_snapshot_date_limits_primary_series_by_created_at(): void
    {
        // Two bookings same month/year; one created BEFORE snapshot, one AFTER.
        // With ?snapshot_date=<between>, months[] reflects only the earlier one.
        // With ?compare_with_current=1, current_months[] reflects BOTH.
    }

    public function test_compare_without_snapshot_omits_current_months(): void
    {
        // ?compare_with_current=1 but no snapshot_date → response has no
        // 'current_months' key (or null).
    }

    public function test_scopes_to_band_and_requires_access(): void
    {
        // Another band's bookings don't leak; a non-member gets 403.
    }
}
```

> Verify the exact JSON via `assertJsonPath`/`assertJsonCount`. For cents: a price of `1500.00` is stored as `150000` (Price cast ×100); `paymentsByYear`/`amount` sums are in cents already, but `getPaidUnpaid` exposes `price`/`amount_paid`/`net_amount` as DOLLAR-valued numbers on the booking — so the controller multiplies by 100 and rounds. Assert accordingly (e.g. a $1500 booking fully paid → `paid: 150000`).

- [ ] **Step 2: Run the test to verify it fails**

Run: `docker compose exec app php artisan test --filter=FinanceTrendsTest`
Expected: FAIL — route undefined (404).

- [ ] **Step 3: Add the route**

In `routes/api.php`, inside the `Route::middleware('mobile.band:read:bookings')->group(...)` block holding `mobile.finances.index/unpaid/paid/revenue`, add:

```php
            Route::get('/bands/{band}/finances/trends', [App\Http\Controllers\Api\Mobile\FinancesController::class, 'trends'])->name('mobile.finances.trends');
```

- [ ] **Step 4: Add the controller method**

In `app/Http/Controllers/Api/Mobile/FinancesController.php` add the method below. It injects `FinanceServices` (already a constructor dependency on this controller) and uses the imported `Request` type. It buckets by month server-side, mirroring the web `processDataByMonth`, and emits cents.

```php
    /**
     * GET /api/mobile/bands/{band}/finances/trends
     *
     * Per-month paid/unpaid/forecast/net/count for a year (cents), scoped to the
     * band. Optional ?snapshot_date=Y-m-d limits the primary series to bookings
     * created on/before that date; ?compare_with_current=1 (only with a snapshot)
     * additionally returns the current (unfiltered) series as current_months.
     */
    public function trends(Request $request): JsonResponse
    {
        $band = $request->input('mobile_band');
        $year = $request->integer('year') ?: (int) date('Y');
        $snapshotDate = $request->input('snapshot_date'); // 'Y-m-d' or null
        $compare = $request->boolean('compare_with_current');

        $months = $this->bucketByMonth($band, $year, $snapshotDate);

        $payload = [
            'year' => $year,
            'snapshot_date' => $snapshotDate,
            'available_years' => $this->availableYears($band),
            'months' => $months,
        ];

        if ($compare && $snapshotDate) {
            $payload['current_months'] = $this->bucketByMonth($band, $year, null);
        }

        return response()->json($payload);
    }

    /**
     * Returns 12 zero-filled month rows (cents) for $year, summing non-cancelled
     * bookings whose start_date falls in $year. $snapshotDate (nullable) is passed
     * through to getPaidUnpaid for created_at filtering.
     */
    private function bucketByMonth($band, int $year, ?string $snapshotDate): array
    {
        $bands = $this->financeServices->getPaidUnpaid([$band], $snapshotDate);
        $b = $bands->first();
        $bookings = collect($b->paidBookings)->concat(collect($b->unpaidBookings));

        $rows = [];
        for ($m = 1; $m <= 12; $m++) {
            $rows[$m] = ['month' => $m, 'paid' => 0.0, 'unpaid' => 0.0, 'forecast' => 0.0, 'net' => 0.0, 'count' => 0];
        }

        foreach ($bookings as $booking) {
            if (($booking->status ?? null) === 'cancelled') {
                continue;
            }
            if (empty($booking->start_date)) {
                continue;
            }
            $date = \Carbon\Carbon::parse($booking->start_date);
            if ((int) $date->year !== $year) {
                continue;
            }
            $m = (int) $date->month;
            $price = (float) $booking->price;
            $paid = (float) $booking->amount_paid;
            $net = (float) ($booking->net_amount ?? 0);

            $rows[$m]['forecast'] += $price;
            $rows[$m]['paid'] += $paid;
            $rows[$m]['unpaid'] += max(0, $price - $paid);
            $rows[$m]['net'] += $net;
            $rows[$m]['count'] += 1;
        }

        return array_values(array_map(fn ($r) => [
            'month' => $r['month'],
            'paid' => (int) round($r['paid'] * 100),
            'unpaid' => (int) round($r['unpaid'] * 100),
            'forecast' => (int) round($r['forecast'] * 100),
            'net' => (int) round($r['net'] * 100),
            'count' => $r['count'],
        ], $rows));
    }

    /** Distinct years across the band's bookings (start_date), descending. */
    private function availableYears($band): array
    {
        $bands = $this->financeServices->getPaidUnpaid([$band], null);
        $b = $bands->first();
        $bookings = collect($b->paidBookings)->concat(collect($b->unpaidBookings));

        return $bookings
            ->filter(fn ($bk) => ($bk->status ?? null) !== 'cancelled' && !empty($bk->start_date))
            ->map(fn ($bk) => (int) \Carbon\Carbon::parse($bk->start_date)->year)
            ->unique()
            ->sortDesc()
            ->values()
            ->all();
    }
```

> If `start_date` is not present on the booking objects returned by `getPaidUnpaid`, check how the web reads it (the explore notes say `start_date` is "derived from first event date"). Inspect the `Bookings` model for a `start_date` accessor / first-event date; if it's an accessor, `$booking->start_date` works. If bookings expose events instead, derive the first event date the same way the model/web does. Confirm before finalizing — do not invent a field.

- [ ] **Step 5: Run the test to verify it passes**

Run: `docker compose exec app php artisan test --filter=FinanceTrendsTest`
Expected: PASS.

- [ ] **Step 6: Commit** (on a feature branch off `staging`, e.g. `feat/mobile-finances-trends` — do NOT commit to staging)

```bash
git add app/Http/Controllers/Api/Mobile/FinancesController.php routes/api.php tests/Feature/Api/Mobile/FinanceTrendsTest.php
git commit -m "feat(mobile-api): add band finances trends endpoint"
```

---

## Mobile Tasks (run in this worktree, branch `feat/finances-trends-mobile`)

### Task 2: FinanceTrends model

**Files:**
- Create: `lib/features/finances/data/models/finance_trends.dart`
- Test: `test/features/finances/finance_trends_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/finances/finance_trends_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_trends.dart';

Map<String, dynamic> _month(int m, {int paid = 0, int unpaid = 0, int forecast = 0, int net = 0, int count = 0}) =>
    {'month': m, 'paid': paid, 'unpaid': unpaid, 'forecast': forecast, 'net': net, 'count': count};

void main() {
  group('FinanceTrends.fromJson', () {
    test('parses months, available_years, snapshot_date', () {
      final t = FinanceTrends.fromJson({
        'year': 2026,
        'snapshot_date': '2025-06-15',
        'available_years': [2026, 2025],
        'months': [_month(2, paid: 300000, unpaid: 120000, forecast: 420000, net: 84000, count: 2)],
      });
      expect(t.year, 2026);
      expect(t.snapshotDate, '2025-06-15');
      expect(t.availableYears, [2026, 2025]);
      expect(t.months.single.paidCents, 300000);
      expect(t.months.single.count, 2);
      expect(t.currentMonths, isNull);
    });

    test('parses current_months when present', () {
      final t = FinanceTrends.fromJson({
        'year': 2026,
        'available_years': [2026],
        'months': [_month(1)],
        'current_months': [_month(1, paid: 500000, count: 3)],
      });
      expect(t.currentMonths, isNotNull);
      expect(t.currentMonths!.single.paidCents, 500000);
    });
  });

  group('derived totals', () {
    final t = FinanceTrends.fromJson({
      'year': 2026,
      'available_years': [2026],
      'months': [
        _month(1, paid: 100000, unpaid: 50000, forecast: 150000, net: 30000, count: 2),
        _month(2, paid: 200000, unpaid: 0, forecast: 200000, net: 40000, count: 1),
      ],
    });

    test('sums per-series totals', () {
      expect(t.totalPaidCents, 300000);
      expect(t.totalUnpaidCents, 50000);
      expect(t.totalForecastCents, 350000);
      expect(t.totalNetCents, 70000);
      expect(t.totalCount, 3);
    });

    test('isEmpty true only when every month is all-zero', () {
      final empty = FinanceTrends.fromJson({
        'year': 2026, 'available_years': [], 'months': [_month(1), _month(2)],
      });
      expect(empty.isEmpty, isTrue);
      expect(t.isEmpty, isFalse);
    });
  });

  group('compare deltas', () {
    final t = FinanceTrends.fromJson({
      'year': 2026,
      'snapshot_date': '2025-06-15',
      'available_years': [2026],
      'months': [_month(1, paid: 100000, count: 2)],
      'current_months': [_month(1, paid: 250000, count: 5)],
    });

    test('current totals sum current_months', () {
      expect(t.currentTotalPaidCents, 250000);
      expect(t.currentTotalCount, 5);
    });

    test('deltas are current minus snapshot', () {
      expect(t.deltaPaidCents, 150000);
      expect(t.deltaCount, 3);
    });

    test('deltas are null when not comparing', () {
      final noCompare = FinanceTrends.fromJson({
        'year': 2026, 'available_years': [2026], 'months': [_month(1, paid: 100000)],
      });
      expect(noCompare.deltaPaidCents, isNull);
      expect(noCompare.currentTotalPaidCents, isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/finances/finance_trends_test.dart`
Expected: FAIL — model doesn't exist.

- [ ] **Step 3: Write the model**

Create `lib/features/finances/data/models/finance_trends.dart`:

```dart
/// One month's bucketed finance figures. All `*Cents` are in cents.
class TrendMonth {
  const TrendMonth({
    required this.month,
    required this.paidCents,
    required this.unpaidCents,
    required this.forecastCents,
    required this.netCents,
    required this.count,
  });

  final int month; // 1..12
  final int paidCents;
  final int unpaidCents;
  final int forecastCents;
  final int netCents;
  final int count;

  factory TrendMonth.fromJson(Map<String, dynamic> json) {
    int c(String k) => (json[k] as num?)?.toInt() ?? 0;
    return TrendMonth(
      month: c('month'),
      paidCents: c('paid'),
      unpaidCents: c('unpaid'),
      forecastCents: c('forecast'),
      netCents: c('net'),
      count: c('count'),
    );
  }

  bool get isZero =>
      paidCents == 0 &&
      unpaidCents == 0 &&
      forecastCents == 0 &&
      netCents == 0 &&
      count == 0;
}

/// Per-month finance trends for a band+year, optionally with a snapshot and a
/// current (unfiltered) comparison series.
class FinanceTrends {
  const FinanceTrends({
    required this.year,
    required this.snapshotDate,
    required this.availableYears,
    required this.months,
    required this.currentMonths,
  });

  final int year;
  final String? snapshotDate;
  final List<int> availableYears;
  final List<TrendMonth> months;
  final List<TrendMonth>? currentMonths;

  factory FinanceTrends.fromJson(Map<String, dynamic> json) {
    List<TrendMonth> parse(List<dynamic> raw) =>
        raw.cast<Map<String, dynamic>>().map(TrendMonth.fromJson).toList();
    final current = json['current_months'];
    return FinanceTrends(
      year: (json['year'] as num).toInt(),
      snapshotDate: json['snapshot_date'] as String?,
      availableYears:
          (json['available_years'] as List<dynamic>? ?? const []).cast<num>().map((e) => e.toInt()).toList(),
      months: parse(json['months'] as List<dynamic>? ?? const []),
      currentMonths: current is List ? parse(current) : null,
    );
  }

  bool get comparing => currentMonths != null;

  // ── Snapshot totals ──
  int get totalPaidCents => months.fold(0, (s, m) => s + m.paidCents);
  int get totalUnpaidCents => months.fold(0, (s, m) => s + m.unpaidCents);
  int get totalForecastCents => months.fold(0, (s, m) => s + m.forecastCents);
  int get totalNetCents => months.fold(0, (s, m) => s + m.netCents);
  int get totalCount => months.fold(0, (s, m) => s + m.count);

  /// True when there is no activity at all (every month all-zero).
  bool get isEmpty => months.every((m) => m.isZero);

  // ── Current totals (null unless comparing) ──
  int? get currentTotalPaidCents =>
      currentMonths?.fold(0, (s, m) => s! + m.paidCents);
  int? get currentTotalUnpaidCents =>
      currentMonths?.fold(0, (s, m) => s! + m.unpaidCents);
  int? get currentTotalForecastCents =>
      currentMonths?.fold(0, (s, m) => s! + m.forecastCents);
  int? get currentTotalNetCents =>
      currentMonths?.fold(0, (s, m) => s! + m.netCents);
  int? get currentTotalCount =>
      currentMonths?.fold(0, (s, m) => s! + m.count);

  // ── Deltas (current − snapshot), null unless comparing ──
  int? get deltaPaidCents =>
      comparing ? currentTotalPaidCents! - totalPaidCents : null;
  int? get deltaUnpaidCents =>
      comparing ? currentTotalUnpaidCents! - totalUnpaidCents : null;
  int? get deltaForecastCents =>
      comparing ? currentTotalForecastCents! - totalForecastCents : null;
  int? get deltaNetCents =>
      comparing ? currentTotalNetCents! - totalNetCents : null;
  int? get deltaCount => comparing ? currentTotalCount! - totalCount : null;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/finances/finance_trends_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/finances/data/models/finance_trends.dart test/features/finances/finance_trends_test.dart
git commit -m "feat(finances): add FinanceTrends model with totals and deltas"
```

---

### Task 3: Endpoint constant + fetchTrends

**Files:**
- Modify: `lib/core/network/api_endpoints.dart` (after `mobileBandFinancesRevenue`)
- Modify: `lib/features/finances/data/finances_repository.dart`

- [ ] **Step 1: Add the endpoint constant**

In `lib/core/network/api_endpoints.dart`, after `mobileBandFinancesRevenue`:

```dart
  static String mobileBandFinancesTrends(int bandId) =>
      '/api/mobile/bands/$bandId/finances/trends';
```

- [ ] **Step 2: Add the repository method**

In `lib/features/finances/data/finances_repository.dart`, add the import alongside the others:

```dart
import 'models/finance_trends.dart';
```

Add this method inside `FinancesRepository`, after `fetchRevenue`:

```dart
  /// Fetches per-month finance trends for [bandId] and [year]. When
  /// [snapshotDate] (YYYY-MM-DD) is set, the primary series is as-of that date;
  /// [compareWithCurrent] (only meaningful with a snapshot) also returns the
  /// current series for comparison.
  Future<FinanceTrends> fetchTrends(
    int bandId, {
    required int year,
    String? snapshotDate,
    bool compareWithCurrent = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandFinancesTrends(bandId),
      queryParameters: {
        'year': year.toString(),
        if (snapshotDate != null) 'snapshot_date': snapshotDate,
        if (compareWithCurrent) 'compare_with_current': '1',
      },
    );
    return FinanceTrends.fromJson(response.data!);
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/core/network/api_endpoints.dart lib/features/finances/data/finances_repository.dart`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/core/network/api_endpoints.dart lib/features/finances/data/finances_repository.dart
git commit -m "feat(finances): add fetchTrends repository method + endpoint"
```

---

### Task 4: trendsProvider

**Files:**
- Modify: `lib/features/finances/providers/finances_provider.dart`
- Test: `test/features/finances/trends_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/finances/trends_provider_test.dart`. Mirror the fake-repo `implements FinancesRepository` style used in `test/features/finances/revenue_provider_test.dart` (stub the other fetch methods with `UnimplementedError`):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/finances_repository.dart';
import 'package:tts_bandmate/features/finances/data/models/band_revenue.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_booking.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_trends.dart';
import 'package:tts_bandmate/features/finances/providers/finances_provider.dart';

class _FakeRepo implements FinancesRepository {
  int calls = 0;
  int? lastYear;
  String? lastSnapshot;
  bool? lastCompare;

  @override
  Future<FinanceTrends> fetchTrends(int bandId,
      {required int year, String? snapshotDate, bool compareWithCurrent = false}) async {
    calls++;
    lastYear = year;
    lastSnapshot = snapshotDate;
    lastCompare = compareWithCurrent;
    return FinanceTrends.fromJson({
      'year': year, 'available_years': [year], 'months': [
        {'month': 1, 'paid': 1000, 'unpaid': 0, 'forecast': 1000, 'net': 200, 'count': 1}
      ],
    });
  }

  @override
  Future<List<FinanceBooking>> fetchUnpaid(int bandId, {int? year}) => throw UnimplementedError();
  @override
  Future<List<FinanceBooking>> fetchPaid(int bandId, {int? year}) => throw UnimplementedError();
  @override
  Future<BandRevenue> fetchRevenue(int bandId) => throw UnimplementedError();
}

void main() {
  ProviderContainer containerWith(_FakeRepo repo) =>
      ProviderContainer(overrides: [financesRepositoryProvider.overrideWithValue(repo)]);

  test('TrendsParams value-equality', () {
    const a = TrendsParams(bandId: 1, year: 2026, snapshotDate: null, compareWithCurrent: false);
    const b = TrendsParams(bandId: 1, year: 2026, snapshotDate: null, compareWithCurrent: false);
    const c = TrendsParams(bandId: 1, year: 2026, snapshotDate: '2025-06-15', compareWithCurrent: false);
    expect(a, b);
    expect(a == c, isFalse);
  });

  test('trendsProvider forwards params and loads', () async {
    final fake = _FakeRepo();
    final container = containerWith(fake);
    addTearDown(container.dispose);

    const params = TrendsParams(bandId: 7, year: 2025, snapshotDate: '2024-12-31', compareWithCurrent: true);
    final result = await container.read(trendsProvider(params).future);

    expect(result.year, 2025);
    expect(fake.lastYear, 2025);
    expect(fake.lastSnapshot, '2024-12-31');
    expect(fake.lastCompare, isTrue);
  });

  test('refresh re-fetches', () async {
    final fake = _FakeRepo();
    final container = containerWith(fake);
    addTearDown(container.dispose);

    const params = TrendsParams(bandId: 1, year: 2026, snapshotDate: null, compareWithCurrent: false);
    await container.read(trendsProvider(params).future);
    await container.read(trendsProvider(params).notifier).refresh();
    expect(fake.calls, 2);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/finances/trends_provider_test.dart`
Expected: FAIL — `TrendsParams`/`trendsProvider` undefined.

- [ ] **Step 3: Add params + provider**

In `lib/features/finances/providers/finances_provider.dart`, add the import:

```dart
import '../data/models/finance_trends.dart';
```

Append after `revenueProvider`:

```dart
class TrendsParams {
  const TrendsParams({
    required this.bandId,
    required this.year,
    required this.snapshotDate,
    required this.compareWithCurrent,
  });

  final int bandId;
  final int year;
  final String? snapshotDate;
  final bool compareWithCurrent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrendsParams &&
          runtimeType == other.runtimeType &&
          bandId == other.bandId &&
          year == other.year &&
          snapshotDate == other.snapshotDate &&
          compareWithCurrent == other.compareWithCurrent;

  @override
  int get hashCode => Object.hash(bandId, year, snapshotDate, compareWithCurrent);
}

class _TrendsNotifier extends AsyncNotifier<FinanceTrends> {
  _TrendsNotifier(this._params);
  final TrendsParams _params;

  Future<FinanceTrends> _fetch() => ref.read(financesRepositoryProvider).fetchTrends(
        _params.bandId,
        year: _params.year,
        snapshotDate: _params.snapshotDate,
        compareWithCurrent: _params.compareWithCurrent,
      );

  @override
  Future<FinanceTrends> build() => _fetch();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }
}

final trendsProvider =
    AsyncNotifierProvider.family<_TrendsNotifier, FinanceTrends, TrendsParams>(
  (arg) => _TrendsNotifier(arg),
);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/finances/trends_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/finances/providers/finances_provider.dart test/features/finances/trends_provider_test.dart
git commit -m "feat(finances): add trendsProvider + TrendsParams"
```

---

### Task 5: Trends chart widget

**Files:**
- Create: `lib/features/finances/screens/widgets/trends_chart.dart`

- [ ] **Step 1: Write the widget**

Create `lib/features/finances/screens/widgets/trends_chart.dart`. Grouped paid/unpaid bars per month + forecast/net line overlays on a single $ axis, with a tap tooltip. When `currentMonths` is present (comparing), the snapshot bars render at full opacity and current bars render faded behind. Model on `lib/features/stats/screens/widgets/earnings_bar_chart.dart`.

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/finance_trends.dart';

/// Per-month finance chart: paid + unpaid bars with forecast/net line overlays
/// on a single dollar axis. Tap a month for a tooltip with its figures.
class TrendsChart extends StatelessWidget {
  const TrendsChart({super.key, required this.trends});

  final FinanceTrends trends;

  static const _monthLabels = [
    'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'
  ];

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final blue = CupertinoColors.systemBlue.resolveFrom(context);
    final gray = CupertinoColors.systemGrey.resolveFrom(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final purple = CupertinoColors.systemPurple.resolveFrom(context);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);

    final months = trends.months;
    double dollars(int cents) => cents / 100.0;

    // Max across paid+unpaid stack and the forecast/net lines, for the axis.
    double maxY = 0;
    for (final m in months) {
      final stack = dollars(m.paidCents + m.unpaidCents);
      final f = dollars(m.forecastCents);
      maxY = [maxY, stack, f].reduce((a, b) => a > b ? a : b);
    }
    final chartMax = maxY > 0 ? maxY * 1.1 : 100;

    final barGroups = months.asMap().entries.map((e) {
      final m = e.value;
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: dollars(m.paidCents + m.unpaidCents),
            width: 9,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
            color: const Color(0x00000000),
            rodStackItems: [
              BarChartRodStackItem(0, dollars(m.paidCents), blue),
              BarChartRodStackItem(
                dollars(m.paidCents),
                dollars(m.paidCents + m.unpaidCents),
                gray.withValues(alpha: 0.55),
              ),
            ],
          ),
        ],
      );
    }).toList();

    // Forecast (green) and net (purple) lines, x = month index.
    LineChartBarData line(Color color, double Function(TrendMonth) sel) =>
        LineChartBarData(
          spots: [
            for (var i = 0; i < months.length; i++)
              FlSpot(i.toDouble(), sel(months[i])),
          ],
          isCurved: false,
          color: color,
          barWidth: 1.8,
          dotData: const FlDotData(show: false),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 220,
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            BarChart(
              BarChartData(
                maxY: chartMax.toDouble(),
                barGroups: barGroups,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: CupertinoColors.separator.resolveFrom(context),
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _monthLabels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_monthLabels[idx],
                              style: TextStyle(fontSize: 10, color: secondaryLabel)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, _) => Text(currency.format(value),
                          style: TextStyle(fontSize: 9, color: secondaryLabel)),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, rod, __) {
                      final m = months[group.x.toInt()];
                      final money = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
                      return BarTooltipItem(
                        '${DateFormat('MMMM').format(DateTime(trends.year, m.month))}\n'
                        '${m.count} ${m.count == 1 ? 'booking' : 'bookings'}\n'
                        '${money.format(dollars(m.paidCents))} paid\n'
                        '${money.format(dollars(m.unpaidCents))} unpaid\n'
                        '${money.format(dollars(m.forecastCents))} forecast\n'
                        '${money.format(dollars(m.netCents))} band cut',
                        const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: CupertinoColors.white),
                      );
                    },
                  ),
                ),
              ),
            ),
            // Forecast + net lines drawn over the bars, sharing the same axis.
            IgnorePointer(
              child: LineChart(
                LineChartData(
                  minX: -0.5,
                  maxX: months.length - 0.5,
                  minY: 0,
                  maxY: chartMax.toDouble(),
                  lineBarsData: [
                    line(green, (m) => dollars(m.forecastCents)),
                    line(purple, (m) => dollars(m.netCents)),
                  ],
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
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

> Note: the line overlay must share the bar chart's Y range and left padding so the lines align with the bars. The `reservedSize: 48` left axis offsets the bars; the overlaid LineChart hides its own titles, so account for the same left inset by wrapping the `LineChart` in a `Padding(left: 48)` if the lines look shifted on-device. Verify alignment in Task 8's manual run and adjust the left padding only if needed.

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/finances/screens/widgets/trends_chart.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/features/finances/screens/widgets/trends_chart.dart
git commit -m "feat(finances): add trends chart widget"
```

---

### Task 6: Trends count row widget

**Files:**
- Create: `lib/features/finances/screens/widgets/trends_count_row.dart`

- [ ] **Step 1: Write the widget**

Create `lib/features/finances/screens/widgets/trends_count_row.dart`. A 12-slot row of per-month booking counts, evenly spaced to align under the chart's month columns.

```dart
import 'package:flutter/cupertino.dart';
import '../../data/models/finance_trends.dart';

/// A per-month booking-count strip shown directly under the chart, so a low
/// dollar month visibly correlates with few bookings.
class TrendsCountRow extends StatelessWidget {
  const TrendsCountRow({super.key, required this.trends});

  final FinanceTrends trends;

  @override
  Widget build(BuildContext context) {
    final orange = CupertinoColors.systemOrange.resolveFrom(context);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);

    return Padding(
      // Match the chart's horizontal inset; the left pad approximates the
      // chart's reserved y-axis width so counts sit under their bars.
      padding: const EdgeInsets.fromLTRB(64, 6, 28, 0),
      child: Row(
        children: [
          for (final m in trends.months)
            Expanded(
              child: Center(
                child: Text(
                  '${m.count}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: m.count > 0 ? FontWeight.w700 : FontWeight.w400,
                    color: m.count > 0 ? orange : secondaryLabel,
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

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/finances/screens/widgets/trends_count_row.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/features/finances/screens/widgets/trends_count_row.dart
git commit -m "feat(finances): add per-month booking-count row"
```

---

### Task 7: TrendsView (controls + chart + count + cards + states)

**Files:**
- Create: `lib/features/finances/screens/widgets/trends_view.dart`

- [ ] **Step 1: Write the view**

Create `lib/features/finances/screens/widgets/trends_view.dart`. A `ConsumerStatefulWidget` holding local view state (`_year`, `_snapshotDate`, `_compare`) and returning a sliver. It watches `trendsProvider(TrendsParams(...))`, renders the controls row (year selector, "As of" pill, "vs Current" toggle), then chart + count row + summary cards (+ delta badges), with loading/error/empty states. Uses `EmptyStateView` (icon/title/subtitle) and `ErrorView` (message/onRetry) which already exist.

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../../data/models/finance_trends.dart';
import '../../providers/finances_provider.dart';
import 'trends_chart.dart';
import 'trends_count_row.dart';

final _money = NumberFormat.currency(symbol: '\$');
String _fmtCents(int cents) => _money.format(cents / 100.0);

/// Trends tab body (sliver). Holds year/snapshot/compare state locally and
/// drives trendsProvider.
class TrendsView extends ConsumerStatefulWidget {
  const TrendsView({super.key, required this.bandId});

  final int bandId;

  @override
  ConsumerState<TrendsView> createState() => _TrendsViewState();
}

class _TrendsViewState extends ConsumerState<TrendsView> {
  int _year = DateTime.now().year;
  String? _snapshotDate; // YYYY-MM-DD
  bool _compare = false;

  TrendsParams get _params => TrendsParams(
        bandId: widget.bandId,
        year: _year,
        snapshotDate: _snapshotDate,
        compareWithCurrent: _compare,
      );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trendsProvider(_params));

    return async.when(
      loading: () => const SliverFillRemaining(
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => SliverFillRemaining(
        child: ErrorView(
          message: ErrorView.friendlyMessage(e),
          onRetry: () => ref.read(trendsProvider(_params).notifier).refresh(),
        ),
      ),
      data: (trends) => SliverList(
        delegate: SliverChildListDelegate([
          const SizedBox(height: 8),
          _ControlsRow(
            year: _year,
            availableYears: trends.availableYears,
            snapshotDate: _snapshotDate,
            compare: _compare,
            onYear: (y) => setState(() => _year = y),
            onPickDate: _pickSnapshot,
            onClearDate: () => setState(() {
              _snapshotDate = null;
              _compare = false;
            }),
            onToggleCompare: (v) => setState(() => _compare = v),
          ),
          const SizedBox(height: 8),
          if (trends.isEmpty)
            _EmptyBody(year: _year)
          else ...[
            TrendsChart(trends: trends),
            TrendsCountRow(trends: trends),
            const _Legend(),
            const SizedBox(height: 12),
            _SummaryCards(trends: trends),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Future<void> _pickSnapshot() async {
    DateTime temp = _snapshotDate != null
        ? DateTime.parse(_snapshotDate!)
        : DateTime.now();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: 300,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CupertinoButton(
                  onPressed: () {
                    setState(() =>
                        _snapshotDate = DateFormat('yyyy-MM-dd').format(temp));
                    Navigator.pop(context);
                  },
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: temp,
                maximumDate: DateTime.now(),
                onDateTimeChanged: (d) => temp = d,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Controls ──────────────────────────────────────────────────────────────────

class _ControlsRow extends StatelessWidget {
  const _ControlsRow({
    required this.year,
    required this.availableYears,
    required this.snapshotDate,
    required this.compare,
    required this.onYear,
    required this.onPickDate,
    required this.onClearDate,
    required this.onToggleCompare,
  });

  final int year;
  final List<int> availableYears;
  final String? snapshotDate;
  final bool compare;
  final void Function(int) onYear;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final void Function(bool) onToggleCompare;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final tint = CupertinoColors.systemBlue.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Year selector
              GestureDetector(
                onTap: () => _showYearPicker(context),
                child: _Pill(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$year',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: label)),
                    const SizedBox(width: 2),
                    Icon(CupertinoIcons.chevron_down, size: 12, color: label),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              // As-of pill
              GestureDetector(
                onTap: onPickDate,
                child: _Pill(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(CupertinoIcons.clock, size: 13, color: tint),
                    const SizedBox(width: 4),
                    Text(
                      snapshotDate == null
                          ? 'All time'
                          : 'As of ${DateFormat('MMM d, yyyy').format(DateTime.parse(snapshotDate!))}',
                      style: TextStyle(fontSize: 13, color: label),
                    ),
                    if (snapshotDate != null) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onClearDate,
                        child: Icon(CupertinoIcons.clear_circled_solid,
                            size: 14,
                            color: CupertinoColors.tertiaryLabel.resolveFrom(context)),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
          if (snapshotDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text('Compare with current',
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context))),
                  const SizedBox(width: 8),
                  CupertinoSwitch(value: compare, onChanged: onToggleCompare),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showYearPicker(BuildContext context) {
    final years = availableYears.isNotEmpty ? availableYears : [year];
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: 250,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: CupertinoPicker(
          itemExtent: 36,
          scrollController: FixedExtentScrollController(
            initialItem: years.indexOf(year) < 0 ? 0 : years.indexOf(year),
          ),
          onSelectedItemChanged: (i) => onYear(years[i]),
          children: [for (final y in years) Center(child: Text('$y'))],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: CupertinoColors.separator.resolveFrom(context), width: 0.5),
      ),
      child: child,
    );
  }
}

// ── Legend ────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: CupertinoColors.secondaryLabel.resolveFrom(context))),
        ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(spacing: 14, runSpacing: 6, children: [
        item(CupertinoColors.systemBlue.resolveFrom(context), 'Paid'),
        item(CupertinoColors.systemGrey.resolveFrom(context), 'Unpaid'),
        item(CupertinoColors.systemGreen.resolveFrom(context), 'Forecast'),
        item(CupertinoColors.systemPurple.resolveFrom(context), 'Band cut'),
      ]),
    );
  }
}

// ── Summary cards ─────────────────────────────────────────────────────────────

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.trends});
  final FinanceTrends trends;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: _StatCard(
                label: 'Paid',
                value: _fmtCents(trends.totalPaidCents),
                tint: CupertinoColors.systemBlue.resolveFrom(context),
                deltaCents: trends.deltaPaidCents,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Outstanding',
                value: _fmtCents(trends.totalUnpaidCents),
                tint: CupertinoColors.systemGrey.resolveFrom(context),
                deltaCents: trends.deltaUnpaidCents,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _StatCard(
                label: 'Band cut',
                value: _fmtCents(trends.totalNetCents),
                tint: CupertinoColors.systemPurple.resolveFrom(context),
                deltaCents: trends.deltaNetCents,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Bookings',
                value: '${trends.totalCount}',
                tint: CupertinoColors.systemOrange.resolveFrom(context),
                deltaCount: trends.deltaCount,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.tint,
    this.deltaCents,
    this.deltaCount,
  });

  final String label;
  final String value;
  final Color tint;
  final int? deltaCents;
  final int? deltaCount;

  @override
  Widget build(BuildContext context) {
    final delta = deltaCents ?? deltaCount;
    final isMoney = deltaCents != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context))),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tint)),
          if (delta != null && delta != 0) ...[
            const SizedBox(height: 2),
            _DeltaBadge(delta: delta, isMoney: isMoney),
          ],
        ],
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.delta, required this.isMoney});
  final int delta;
  final bool isMoney;

  @override
  Widget build(BuildContext context) {
    final up = delta > 0;
    final color = up
        ? CupertinoColors.systemGreen.resolveFrom(context)
        : CupertinoColors.systemRed.resolveFrom(context);
    final text = isMoney ? _fmtCents(delta.abs()) : '${delta.abs()}';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(up ? CupertinoIcons.arrow_up : CupertinoIcons.arrow_down, size: 11, color: color),
      const SizedBox(width: 2),
      Text('$text vs snapshot',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    ]);
  }
}

// ── Empty ─────────────────────────────────────────────────────────────────────

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.year});
  final int year;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: EmptyStateView(
        icon: CupertinoIcons.chart_bar,
        title: 'No activity in $year',
        subtitle: 'Try another year or clear the snapshot date.',
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/finances/screens/widgets/trends_view.dart`
Expected: No issues found. (If `EmptyStateView`/`ErrorView` params differ, match their real signatures — both are already used in this feature.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/finances/screens/widgets/trends_view.dart
git commit -m "feat(finances): add TrendsView with controls, chart, count, cards"
```

---

### Task 8: Wire the Trends tab into FinancesScreen

**Files:**
- Modify: `lib/features/finances/screens/finances_screen.dart`

- [ ] **Step 1: Add `trends` to the enum + import**

Change:
```dart
enum _FinancesTab { unpaid, paid, revenue }
```
to:
```dart
enum _FinancesTab { unpaid, paid, revenue, trends }
```

Add the import with the other widget imports:
```dart
import 'widgets/trends_view.dart';
```

- [ ] **Step 2: Add the segment**

In the `CupertinoSegmentedControl<_FinancesTab>` `children` map, after the `revenue` entry, add:

```dart
                  _FinancesTab.trends: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Trends'),
                  ),
```

- [ ] **Step 3: Update the two `switch`es over `_FinancesTab`**

The `bookingsAsync` switch currently returns `null` for `revenue`; add a `trends` case that also returns `null`:

```dart
    final bookingsAsync = switch (widget.tab) {
      _FinancesTab.unpaid => ref.watch(unpaidServicesProvider(_params)),
      _FinancesTab.paid => ref.watch(paidServicesProvider(_params)),
      _FinancesTab.revenue => null,
      _FinancesTab.trends => null,
    };
```

The refresh switch must add a `trends` case. Note `TrendsView` owns its own `TrendsParams`, so the screen-level refresh can't know the exact params; refresh the unpaid/paid/revenue cases as before and make `trends` a no-op `Future` (pull-to-refresh inside the Trends data is still available via the provider, and changing controls refetches). Use:

```dart
          CupertinoSliverRefreshControl(
            onRefresh: () => switch (widget.tab) {
              _FinancesTab.unpaid =>
                ref.read(unpaidServicesProvider(_params).notifier).refresh(),
              _FinancesTab.paid =>
                ref.read(paidServicesProvider(_params).notifier).refresh(),
              _FinancesTab.revenue =>
                ref.read(revenueProvider(widget.bandId).notifier).refresh(),
              _FinancesTab.trends => Future<void>.value(),
            },
          ),
```

- [ ] **Step 4: Gate chrome and render TrendsView**

The Unpaid/Paid-only chrome is currently gated by `if (widget.tab != _FinancesTab.revenue) ...[ ... ] else RevenueView(...)`. Change it so the chrome shows only for unpaid/paid, and route revenue/trends to their views. Replace the `if (... != revenue) ...[ ... ] else RevenueView(bandId: widget.bandId),` structure with:

```dart
          if (widget.tab == _FinancesTab.unpaid ||
              widget.tab == _FinancesTab.paid) ...[
            // (existing year stepper, name search, status pills, bookingsAsync!.when(...) slivers unchanged)
          ] else if (widget.tab == _FinancesTab.revenue)
            RevenueView(bandId: widget.bandId)
          else
            TrendsView(bandId: widget.bandId),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
```

> The `bookingsAsync!.when(...)` inside the unpaid/paid block stays as-is (bookingsAsync is non-null for those two tabs). Only the outer `if` condition and the `else` branches change.

- [ ] **Step 5: Verify analyze + run the finances tests**

Run: `flutter analyze lib/features/finances/`
Expected: No issues found.

Run: `flutter test test/features/finances/`
Expected: All pass (existing + the new model/provider tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/finances/screens/finances_screen.dart
git commit -m "feat(finances): add Trends tab to finances screen"
```

---

### Task 9: Manual verification + PRs

- [ ] **Step 1: Full static analysis**

Run: `flutter analyze`
Expected: No new errors/lints from this feature (pre-existing warnings in secure_storage/main.dart are unrelated).

- [ ] **Step 2: Run the app and verify the Trends tab**

Run: `flutter run -d chrome --dart-define=BASE_URL=http://localhost:8715` (or a device), with the backend running so `/finances/trends` is live. Verify:
- Trends tab shows the chart (paid/unpaid bars + forecast/band-cut lines), with the per-month count row aligned beneath the bars (adjust `TrendsCountRow` left padding or the chart line inset if misaligned).
- Tapping a month shows the tooltip (count + four $ figures).
- Year selector switches years; the chart updates.
- Setting an "As of" date filters the data; enabling "vs Current" shows delta badges on the cards.
- A year with no activity shows the "No activity in <year>" empty state with controls still visible.

> Requires the Task 1 backend endpoint running against the same `BASE_URL`. If the backend isn't deployed, verify the other three tabs still work and defer live Trends verification.

- [ ] **Step 3: Open the PRs**

Backend (in `/home/eddie/github/TTS`, base `staging`):
```bash
gh pr create --base staging --title "feat(mobile-api): band finances trends endpoint" --body "Server-bucketed per-month paid/unpaid/forecast/net/count (cents) for the mobile Trends tab, with snapshot_date + compare_with_current."
```

Mobile (in this worktree, base `main`):
```bash
gh pr create --base main --title "feat(finances): trends chart + time travel on mobile (web parity, slice 2)" --body "Adds a Trends tab: per-month chart (paid/unpaid bars + forecast/band-cut lines), always-visible booking-count row + tap tooltip, year selector, and time travel (As-of date + vs-Current deltas). Backed by the new trends endpoint."
```

---

## Notes for the implementer

- **Two repos, sequence:** Do Task 1 (backend) first; the mobile model/provider build and unit-test against fakes, but live verification (Task 9) needs the endpoint.
- **Backend repo rules:** never run PHP on the host — `docker compose exec app …`. Backend PRs target `staging`.
- **Mobile repo rules:** PRs target `main`; stay on `feat/finances-trends-mobile`.
- **Cents everywhere:** API returns cents; divide by 100 only at display (`/100.0`, `_fmtCents`). Don't double-divide.
- **Read a sibling first:** for the backend test (Task 1) and provider test (Task 4), copy patterns from `FinanceRevenueTest.php` and `revenue_provider_test.dart` respectively.
- **`start_date` confirmation (Task 1):** before finalizing the controller, confirm `$booking->start_date` exists on the objects from `getPaidUnpaid` (web reads it as "first event date"). If it's not a direct field, derive it the way the model/web does — do not invent it.
- **Chart line/bar alignment (Tasks 5-7):** the overlaid forecast/net LineChart must share the BarChart's Y-range and left inset; verify on-device and adjust only the left padding if lines look shifted.
```
