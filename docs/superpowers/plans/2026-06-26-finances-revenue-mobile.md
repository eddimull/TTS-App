# Finances Revenue (Mobile) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only "Revenue" tab to the mobile Finances screen showing total/current-year/years-active summary cards, a revenue-by-year bar chart, and a year-by-year table with year-over-year change — backed by a new mobile revenue endpoint.

**Architecture:** A thin new Laravel mobile endpoint (`GET /api/mobile/bands/{band}/finances/revenue`) wraps the existing `Bands::paymentsByYear()` aggregation (scoped to one band, excluding null-dated payments). The Flutter app gets a `BandRevenue` model, a `fetchRevenue` repository method, a `revenueProvider`, and a `RevenueView` rendered as a third segment in the existing `FinancesScreen`. The chart reuses the `fl_chart` pattern already established in `lib/features/stats/screens/widgets/earnings_bar_chart.dart`.

**Tech Stack:** Laravel (PHP 8, Eloquent), Pest/PHPUnit; Flutter (Dart), Riverpod v2 `AsyncNotifierProvider.family`, `fl_chart`, `intl`.

**Repos:** Backend tasks run in `/home/eddie/github/TTS` (run PHP via `docker compose exec app …`; PRs target `staging`). Mobile tasks run in this worktree `/home/eddie/github/tts_bandmate/.claude/worktrees/feat+event-media-upload` on branch `feat/finances-revenue-mobile` (PR targets `main`).

---

## File Structure

**Backend (`TTS`):**
- Modify: `app/Http/Controllers/Api/Mobile/FinancesController.php` — add `revenue()` method.
- Modify: `routes/api.php` — register `mobile.finances.revenue` route in the existing `mobile.band:read:bookings` group.
- Create: `tests/Feature/Api/Mobile/FinanceRevenueTest.php` — feature tests.

**Mobile (`TTS-App`):**
- Create: `lib/features/finances/data/models/band_revenue.dart` — `RevenueYear` + `BandRevenue` models with derived getters and YoY helper.
- Modify: `lib/features/finances/data/finances_repository.dart` — add `fetchRevenue`.
- Modify: `lib/core/network/api_endpoints.dart` — add `mobileBandFinancesRevenue`.
- Modify: `lib/features/finances/providers/finances_provider.dart` — add `revenueProvider`.
- Create: `lib/features/finances/screens/widgets/revenue_bar_chart.dart` — `fl_chart` bar chart.
- Create: `lib/features/finances/screens/widgets/revenue_view.dart` — cards + chart + table body.
- Modify: `lib/features/finances/screens/finances_screen.dart` — add `revenue` tab + render `RevenueView`.
- Create: `test/features/finances/band_revenue_test.dart` — model + YoY unit tests.
- Create: `test/features/finances/revenue_provider_test.dart` — provider test with fake repo.

---

## Backend Tasks (run in `/home/eddie/github/TTS`)

### Task 1: Revenue endpoint

**Files:**
- Modify: `app/Http/Controllers/Api/Mobile/FinancesController.php`
- Modify: `routes/api.php` (the `mobile.band:read:bookings` group, around line 258-262)
- Test: `tests/Feature/Api/Mobile/FinanceRevenueTest.php`

- [ ] **Step 1: Write the failing feature test**

Create `tests/Feature/Api/Mobile/FinanceRevenueTest.php`. Mirror the setup style of the existing mobile finance tests (look at a sibling file in `tests/Feature/Api/Mobile/` for how they create a band, a user with `read:bookings` ability, and authenticate). The four behaviors:

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\Bands;
use App\Models\Payments;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class FinanceRevenueTest extends TestCase
{
    use RefreshDatabase;

    private function actingMember(Bands $band): User
    {
        $user = User::factory()->create();
        // Attach as an owner/member with finance read access, matching how the
        // sibling mobile finance tests grant access. Copy that helper exactly.
        $band->owners()->create(['user_id' => $user->id]);
        Sanctum::actingAs($user, ['read:bookings']);
        return $user;
    }

    public function test_returns_revenue_grouped_by_year_in_cents(): void
    {
        $band = Bands::factory()->create();
        $this->actingMember($band);

        // amount is stored in cents (Price cast). 1500.00 -> 150000.
        Payments::factory()->for($band)->create(['amount' => 150000, 'date' => '2026-03-01']);
        Payments::factory()->for($band)->create(['amount' => 50000,  'date' => '2026-09-01']);
        Payments::factory()->for($band)->create(['amount' => 98000,  'date' => '2025-06-01']);

        $response = $this->getJson("/api/mobile/bands/{$band->id}/finances/revenue");

        $response->assertOk()->assertJson([
            'revenue' => [
                ['year' => 2026, 'total' => 200000],
                ['year' => 2025, 'total' => 98000],
            ],
        ]);
    }

    public function test_excludes_payments_with_null_date(): void
    {
        $band = Bands::factory()->create();
        $this->actingMember($band);

        Payments::factory()->for($band)->create(['amount' => 10000, 'date' => '2026-01-01']);
        Payments::factory()->for($band)->create(['amount' => 99999, 'date' => null]);

        $response = $this->getJson("/api/mobile/bands/{$band->id}/finances/revenue");

        $response->assertOk()->assertJson(['revenue' => [['year' => 2026, 'total' => 10000]]]);
        $response->assertJsonCount(1, 'revenue');
    }

    public function test_scopes_to_requested_band_only(): void
    {
        $band = Bands::factory()->create();
        $other = Bands::factory()->create();
        $this->actingMember($band);

        Payments::factory()->for($band)->create(['amount' => 10000, 'date' => '2026-01-01']);
        Payments::factory()->for($other)->create(['amount' => 77777, 'date' => '2026-01-01']);

        $response = $this->getJson("/api/mobile/bands/{$band->id}/finances/revenue");

        $response->assertOk()->assertJson(['revenue' => [['year' => 2026, 'total' => 10000]]]);
    }

    public function test_requires_band_access(): void
    {
        $band = Bands::factory()->create();
        $outsider = User::factory()->create();
        Sanctum::actingAs($outsider, ['read:bookings']);

        $this->getJson("/api/mobile/bands/{$band->id}/finances/revenue")
            ->assertForbidden();
    }
}
```

> Note: adjust `actingMember`, the factory access-granting, and the forbidden-status expectation to match exactly what the sibling tests in `tests/Feature/Api/Mobile/` do for the `paid`/`unpaid` endpoints. If a sibling test expects `403` vs `404` for no-access, match it. Read one sibling test first.

- [ ] **Step 2: Run the test to verify it fails**

Run: `docker compose exec app php artisan test --filter=FinanceRevenueTest`
Expected: FAIL — route `/api/mobile/bands/{band}/finances/revenue` not defined (404), so the JSON assertions fail.

- [ ] **Step 3: Add the route**

In `routes/api.php`, inside the existing `Route::middleware('mobile.band:read:bookings')->group(...)` block that already holds `mobile.finances.index/unpaid/paid`, add:

```php
            Route::get('/bands/{band}/finances/revenue', [App\Http\Controllers\Api\Mobile\FinancesController::class, 'revenue'])->name('mobile.finances.revenue');
```

- [ ] **Step 4: Add the controller method**

In `app/Http/Controllers/Api/Mobile/FinancesController.php`, add a `revenue` method. The band is resolved by middleware into `mobile_band` (same as the siblings). Use the band's `paymentsByYear()` relation but exclude null-dated payments and cast to ints:

```php
    /**
     * GET /api/mobile/bands/{band}/finances/revenue
     *
     * Returns total recorded revenue grouped by year (newest first), scoped to
     * the band. Amounts are in cents. Payments without a date (e.g. pending
     * invoices) are excluded.
     */
    public function revenue(\Illuminate\Http\Request $request): JsonResponse
    {
        $band = $request->input('mobile_band');

        $revenue = $band->paymentsByYear()
            ->whereNotNull('date')
            ->get()
            ->map(fn ($row) => [
                'year'  => (int) $row->year,
                'total' => (int) $row->total,
            ])
            ->values();

        return response()->json(['revenue' => $revenue]);
    }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `docker compose exec app php artisan test --filter=FinanceRevenueTest`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add app/Http/Controllers/Api/Mobile/FinancesController.php routes/api.php tests/Feature/Api/Mobile/FinanceRevenueTest.php
git commit -m "feat(mobile-api): add band finances revenue endpoint"
```

---

## Mobile Tasks (run in this worktree, branch `feat/finances-revenue-mobile`)

### Task 2: BandRevenue model + YoY helper

**Files:**
- Create: `lib/features/finances/data/models/band_revenue.dart`
- Test: `test/features/finances/band_revenue_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/finances/band_revenue_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/models/band_revenue.dart';

void main() {
  group('BandRevenue.fromJson', () {
    test('parses revenue rows', () {
      final r = BandRevenue.fromJson({
        'revenue': [
          {'year': 2026, 'total': 200000},
          {'year': 2025, 'total': 98000},
        ],
      });
      expect(r.years.length, 2);
      expect(r.years.first.year, 2026);
      expect(r.years.first.totalCents, 200000);
    });

    test('handles empty list', () {
      final r = BandRevenue.fromJson({'revenue': []});
      expect(r.years, isEmpty);
      expect(r.totalCents, 0);
      expect(r.yearsActive, 0);
      expect(r.currentYearCents, isNull);
    });
  });

  group('derived getters', () {
    final r = BandRevenue(years: const [
      RevenueYear(year: 2026, totalCents: 200000),
      RevenueYear(year: 2025, totalCents: 98000),
    ]);

    test('totalCents sums all years', () => expect(r.totalCents, 298000));
    test('yearsActive counts rows', () => expect(r.yearsActive, 2));
    test('currentYearCents finds current year', () {
      final cur = BandRevenue(years: [
        RevenueYear(year: DateTime.now().year, totalCents: 12345),
      ]);
      expect(cur.currentYearCents, 12345);
    });
    test('currentYearCents null when absent', () {
      final r2 = BandRevenue(years: const [RevenueYear(year: 2000, totalCents: 100)]);
      expect(r2.currentYearCents, isNull);
    });
  });

  group('yearOverYearChange', () {
    // years ordered newest -> oldest; index i compares against i+1 (older)
    final r = BandRevenue(years: const [
      RevenueYear(year: 2026, totalCents: 12000), // +20% over 2025
      RevenueYear(year: 2025, totalCents: 10000), // -50% under 2024
      RevenueYear(year: 2024, totalCents: 20000), // oldest -> null
    ]);

    test('positive change', () => expect(r.yearOverYearChange(0), closeTo(20.0, 0.001)));
    test('negative change', () => expect(r.yearOverYearChange(1), closeTo(-50.0, 0.001)));
    test('oldest row returns null', () => expect(r.yearOverYearChange(2), isNull));

    test('previous total zero returns null (avoid div-by-zero)', () {
      final z = BandRevenue(years: const [
        RevenueYear(year: 2026, totalCents: 5000),
        RevenueYear(year: 2025, totalCents: 0),
      ]);
      expect(z.yearOverYearChange(0), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/finances/band_revenue_test.dart`
Expected: FAIL — `band_revenue.dart` does not exist (compile error).

- [ ] **Step 3: Write the model**

Create `lib/features/finances/data/models/band_revenue.dart`:

```dart
import 'package:intl/intl.dart';

/// One year's total recorded revenue. [totalCents] is in cents (matches the
/// API payload, which mirrors the web's amount-in-cents storage).
class RevenueYear {
  const RevenueYear({required this.year, required this.totalCents});

  final int year;
  final int totalCents;

  factory RevenueYear.fromJson(Map<String, dynamic> json) {
    return RevenueYear(
      year: (json['year'] as num).toInt(),
      totalCents: (json['total'] as num).toInt(),
    );
  }

  /// Revenue in dollars (cents / 100).
  double get totalDollars => totalCents / 100.0;
}

/// A band's revenue broken down by year, newest first.
class BandRevenue {
  const BandRevenue({required this.years});

  /// Ordered newest year first (as returned by the API).
  final List<RevenueYear> years;

  factory BandRevenue.fromJson(Map<String, dynamic> json) {
    final raw = (json['revenue'] as List<dynamic>? ?? const []);
    return BandRevenue(
      years: raw
          .cast<Map<String, dynamic>>()
          .map(RevenueYear.fromJson)
          .toList(),
    );
  }

  /// All-time revenue in cents.
  int get totalCents => years.fold(0, (s, y) => s + y.totalCents);

  /// All-time revenue in dollars.
  double get totalDollars => totalCents / 100.0;

  /// Number of years with recorded revenue.
  int get yearsActive => years.length;

  /// Revenue for the current calendar year in cents, or null if no row exists.
  int? get currentYearCents {
    final now = DateTime.now().year;
    for (final y in years) {
      if (y.year == now) return y.totalCents;
    }
    return null;
  }

  /// Year-over-year change for the year at [index] (list is newest→oldest),
  /// as a signed percentage versus the next-older year. Returns null for the
  /// oldest row or when the previous year's total is zero.
  double? yearOverYearChange(int index) {
    if (index < 0 || index >= years.length - 1) return null;
    final current = years[index].totalCents;
    final previous = years[index + 1].totalCents;
    if (previous == 0) return null;
    return (current - previous) / previous * 100.0;
  }

  static final _currency = NumberFormat.currency(symbol: '\$');

  /// Formats a cents value as currency, e.g. 200000 -> "$2,000.00".
  static String formatCents(int cents) => _currency.format(cents / 100.0);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/finances/band_revenue_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/finances/data/models/band_revenue.dart test/features/finances/band_revenue_test.dart
git commit -m "feat(finances): add BandRevenue model with YoY helper"
```

---

### Task 3: Endpoint constant + repository method

**Files:**
- Modify: `lib/core/network/api_endpoints.dart` (near line 96-101, the `mobileBandFinances*` group)
- Modify: `lib/features/finances/data/finances_repository.dart`

- [ ] **Step 1: Add the endpoint constant**

In `lib/core/network/api_endpoints.dart`, directly after `mobileBandFinancesPaid`:

```dart
  static String mobileBandFinancesRevenue(int bandId) =>
      '/api/mobile/bands/$bandId/finances/revenue';
```

- [ ] **Step 2: Add the repository method**

In `lib/features/finances/data/finances_repository.dart`, add an import and a method. Add at the top with the other import:

```dart
import 'models/band_revenue.dart';
```

Add this method inside `FinancesRepository`, after `fetchPaid`:

```dart
  /// Fetches total recorded revenue grouped by year for [bandId], newest first.
  Future<BandRevenue> fetchRevenue(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandFinancesRevenue(bandId),
    );
    return BandRevenue.fromJson(response.data!);
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/features/finances/data/finances_repository.dart lib/core/network/api_endpoints.dart`
Expected: No errors (warnings about pre-existing issues are fine).

- [ ] **Step 4: Commit**

```bash
git add lib/core/network/api_endpoints.dart lib/features/finances/data/finances_repository.dart
git commit -m "feat(finances): add fetchRevenue repository method + endpoint"
```

---

### Task 4: revenueProvider

**Files:**
- Modify: `lib/features/finances/providers/finances_provider.dart`
- Test: `test/features/finances/revenue_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/finances/revenue_provider_test.dart`. It overrides `financesRepositoryProvider` with a fake. Match the fake-repo style used in the existing finances/bookings provider tests (read one first to copy the override pattern and any required constructor args):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/finances_repository.dart';
import 'package:tts_bandmate/features/finances/data/models/band_revenue.dart';
import 'package:tts_bandmate/features/finances/providers/finances_provider.dart';

class _FakeFinancesRepository implements FinancesRepository {
  _FakeFinancesRepository(this._revenue);
  BandRevenue _revenue;
  int fetchCount = 0;

  @override
  Future<BandRevenue> fetchRevenue(int bandId) async {
    fetchCount++;
    return _revenue;
  }

  // Unused by these tests.
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('revenueProvider loads revenue from the repository', () async {
    final fake = _FakeFinancesRepository(
      BandRevenue(years: const [RevenueYear(year: 2026, totalCents: 5000)]),
    );
    final container = ProviderContainer(overrides: [
      financesRepositoryProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(revenueProvider(1).future);
    expect(result.years.single.totalCents, 5000);
    expect(fake.fetchCount, 1);
  });

  test('refresh re-fetches', () async {
    final fake = _FakeFinancesRepository(
      BandRevenue(years: const [RevenueYear(year: 2026, totalCents: 5000)]),
    );
    final container = ProviderContainer(overrides: [
      financesRepositoryProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    await container.read(revenueProvider(1).future);
    await container.read(revenueProvider(1).notifier).refresh();
    expect(fake.fetchCount, 2);
  });
}
```

> If `FinancesRepository` has a non-trivial constructor or is not easily `implements`-able, copy whatever fake pattern the existing finances/bookings provider tests use instead of `noSuchMethod`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/finances/revenue_provider_test.dart`
Expected: FAIL — `revenueProvider` is undefined (compile error).

- [ ] **Step 3: Add the provider**

In `lib/features/finances/providers/finances_provider.dart`, add the import at the top:

```dart
import '../data/models/band_revenue.dart';
```

Then append, after `paidServicesProvider`:

```dart
class _RevenueNotifier extends AsyncNotifier<BandRevenue> {
  _RevenueNotifier(this._bandId);
  final int _bandId;

  @override
  Future<BandRevenue> build() async {
    return ref.watch(financesRepositoryProvider).fetchRevenue(_bandId);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(financesRepositoryProvider).fetchRevenue(_bandId));
  }
}

final revenueProvider =
    AsyncNotifierProvider.family<_RevenueNotifier, BandRevenue, int>(
  (arg) => _RevenueNotifier(arg),
);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/finances/revenue_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/finances/providers/finances_provider.dart test/features/finances/revenue_provider_test.dart
git commit -m "feat(finances): add revenueProvider"
```

---

### Task 5: Revenue bar chart widget

**Files:**
- Create: `lib/features/finances/screens/widgets/revenue_bar_chart.dart`

- [ ] **Step 1: Write the widget**

Single-series bar chart modeled on `lib/features/stats/screens/widgets/earnings_bar_chart.dart`. Bars are chronological (oldest→newest) for natural left-to-right reading, so it reverses the newest-first `years` list. Create `lib/features/finances/screens/widgets/revenue_bar_chart.dart`:

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/band_revenue.dart';

/// Vertical bar chart — one bar per year of recorded revenue (chronological,
/// oldest on the left). Mirrors the style of the stats EarningsBarChart.
class RevenueBarChart extends StatelessWidget {
  const RevenueBarChart({super.key, required this.revenue});

  final BandRevenue revenue;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final blue = CupertinoColors.systemBlue.resolveFrom(context);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);

    // API gives newest-first; chart reads left→right chronologically.
    final chrono = revenue.years.reversed.toList();

    final maxY = chrono
        .map((e) => e.totalDollars)
        .fold(0.0, (a, b) => a > b ? a : b);
    final chartMax = maxY * 1.1;

    final barGroups = chrono.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value.totalDollars,
            color: blue,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 220,
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: BarChart(
          BarChartData(
            maxY: chartMax > 0 ? chartMax : 100,
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
                    if (idx < 0 || idx >= chrono.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${chrono[idx].year}',
                          style: TextStyle(fontSize: 11, color: secondaryLabel)),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 60,
                  getTitlesWidget: (value, _) => Text(currency.format(value),
                      style: TextStyle(fontSize: 10, color: secondaryLabel)),
                ),
              ),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, __) {
                  final y = chrono[group.x.toInt()];
                  return BarTooltipItem(
                    '${y.year}\n${currency.format(y.totalDollars)}',
                    const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.white),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/finances/screens/widgets/revenue_bar_chart.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/finances/screens/widgets/revenue_bar_chart.dart
git commit -m "feat(finances): add revenue bar chart widget"
```

---

### Task 6: RevenueView (cards + chart + table)

**Files:**
- Create: `lib/features/finances/screens/widgets/revenue_view.dart`

- [ ] **Step 1: Write the view**

Create `lib/features/finances/screens/widgets/revenue_view.dart`. It returns a list of slivers (the parent `FinancesScreen` owns the `CustomScrollView`), watches `revenueProvider(bandId)`, and renders loading/error/empty/data. Uses `EmptyStateView` and `ErrorView` like the rest of the screen.

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../../data/models/band_revenue.dart';
import '../../providers/finances_provider.dart';
import 'revenue_bar_chart.dart';

/// Revenue tab body. Returns a sliver (the parent screen owns the scroll view).
class RevenueView extends ConsumerWidget {
  const RevenueView({super.key, required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revenueAsync = ref.watch(revenueProvider(bandId));

    return revenueAsync.when(
      loading: () => const SliverFillRemaining(
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => SliverFillRemaining(
        child: ErrorView(
          message: ErrorView.friendlyMessage(e),
          onRetry: () => ref.read(revenueProvider(bandId).notifier).refresh(),
        ),
      ),
      data: (revenue) {
        if (revenue.years.isEmpty) {
          return const SliverFillRemaining(
            child: EmptyStateView(
              icon: CupertinoIcons.chart_bar,
              title: 'No revenue yet',
              subtitle: 'Recorded payments will appear here.',
            ),
          );
        }
        return SliverList(
          delegate: SliverChildListDelegate([
            const SizedBox(height: 8),
            _SummaryCards(revenue: revenue),
            const SizedBox(height: 12),
            RevenueBarChart(revenue: revenue),
            const SizedBox(height: 12),
            _RevenueTable(revenue: revenue),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }
}

// ── Summary cards ─────────────────────────────────────────────────────────────

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.revenue});

  final BandRevenue revenue;

  @override
  Widget build(BuildContext context) {
    final currentYear = revenue.currentYearCents;
    final cards = <Widget>[
      _StatCard(
        label: 'Total Revenue',
        value: BandRevenue.formatCents(revenue.totalCents),
        icon: CupertinoIcons.money_dollar,
        tint: CupertinoColors.systemBlue.resolveFrom(context),
      ),
      if (currentYear != null)
        _StatCard(
          label: '${DateTime.now().year} Revenue',
          value: BandRevenue.formatCents(currentYear),
          icon: CupertinoIcons.calendar,
          tint: CupertinoColors.systemGreen.resolveFrom(context),
        ),
      _StatCard(
        label: 'Years Active',
        value: '${revenue.yearsActive}',
        icon: CupertinoIcons.chart_bar_alt_fill,
        tint: CupertinoColors.systemPurple.resolveFrom(context),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// ── Revenue-by-year table ─────────────────────────────────────────────────────

class _RevenueTable extends StatelessWidget {
  const _RevenueTable({required this.revenue});

  final BandRevenue revenue;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().year;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
            child: Row(
              children: [
                Expanded(flex: 3, child: _HeaderCell('Year')),
                Expanded(flex: 4, child: _HeaderCell('Revenue', alignRight: true)),
                Expanded(flex: 3, child: _HeaderCell('Change', alignRight: true)),
              ],
            ),
          ),
          for (var i = 0; i < revenue.years.length; i++)
            _RevenueRow(
              year: revenue.years[i].year,
              isCurrent: revenue.years[i].year == now,
              revenueText: BandRevenue.formatCents(revenue.years[i].totalCents),
              change: revenue.yearOverYearChange(i),
            ),
          // Total footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text('Total',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                Expanded(
                  flex: 7,
                  child: Text(
                    BandRevenue.formatCents(revenue.totalCents),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {this.alignRight = false});
  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
      ),
    );
  }
}

class _RevenueRow extends StatelessWidget {
  const _RevenueRow({
    required this.year,
    required this.isCurrent,
    required this.revenueText,
    required this.change,
  });

  final int year;
  final bool isCurrent;
  final String revenueText;
  final double? change;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text('$year',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                if (isCurrent) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGreen
                          .resolveFrom(context)
                          .withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Current',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.systemGreen.resolveFrom(context),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              revenueText,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(flex: 3, child: _ChangeCell(change: change)),
        ],
      ),
    );
  }
}

class _ChangeCell extends StatelessWidget {
  const _ChangeCell({required this.change});
  final double? change;

  @override
  Widget build(BuildContext context) {
    if (change == null) {
      return Text(
        'N/A',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.tertiaryLabel.resolveFrom(context),
        ),
      );
    }
    final up = change! > 0;
    final flat = change! == 0;
    final color = flat
        ? CupertinoColors.secondaryLabel.resolveFrom(context)
        : (up
            ? CupertinoColors.systemGreen.resolveFrom(context)
            : CupertinoColors.systemRed.resolveFrom(context));
    final pct = change!.abs().toStringAsFixed(1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!flat)
          Icon(up ? CupertinoIcons.arrow_up : CupertinoIcons.arrow_down,
              size: 11, color: color),
        const SizedBox(width: 2),
        Text(
          flat ? '—' : '$pct%',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/finances/screens/widgets/revenue_view.dart`
Expected: No errors. (If `EmptyStateView`/`ErrorView` constructor params differ, match their actual signatures — they are already used in `finances_screen.dart`.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/finances/screens/widgets/revenue_view.dart
git commit -m "feat(finances): add RevenueView with cards, chart and table"
```

---

### Task 7: Wire the Revenue tab into FinancesScreen

**Files:**
- Modify: `lib/features/finances/screens/finances_screen.dart`

- [ ] **Step 1: Add `revenue` to the tab enum**

In `finances_screen.dart`, change:

```dart
enum _FinancesTab { unpaid, paid }
```
to:
```dart
enum _FinancesTab { unpaid, paid, revenue }
```

- [ ] **Step 2: Add the segment + import**

Add the import near the other widget imports at the top:

```dart
import 'widgets/revenue_view.dart';
```

In the `CupertinoSegmentedControl<_FinancesTab>` `children` map (currently `unpaid` and `paid`), add a third entry and reduce horizontal padding so three fit comfortably. Replace the `children:` map with:

```dart
                children: const {
                  _FinancesTab.unpaid: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Unpaid'),
                  ),
                  _FinancesTab.paid: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Paid'),
                  ),
                  _FinancesTab.revenue: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Revenue'),
                  ),
                },
```

- [ ] **Step 3: Gate the Unpaid/Paid-only chrome and the bookings sliver**

The year stepper, name search, and status pills apply only to the Unpaid/Paid tabs. Wrap each of those three `SliverToBoxAdapter`s (year stepper, name search, status pills) so they only render when `widget.tab != _FinancesTab.revenue`. The simplest approach: build the list of slivers conditionally. Find the `slivers: [` list in `_FinancesBodyState.build` and:

1. Keep `CupertinoSliverRefreshControl` and `CupertinoSliverNavigationBar` and the segmented-control `SliverToBoxAdapter` unconditionally.
2. Update the refresh control's `onRefresh` to also handle the revenue tab:

```dart
          CupertinoSliverRefreshControl(
            onRefresh: () => switch (widget.tab) {
              _FinancesTab.unpaid =>
                ref.read(unpaidServicesProvider(_params).notifier).refresh(),
              _FinancesTab.paid =>
                ref.read(paidServicesProvider(_params).notifier).refresh(),
              _FinancesTab.revenue =>
                ref.read(revenueProvider(widget.bandId).notifier).refresh(),
            },
          ),
```

3. Wrap the year-stepper, name-search, and status-pills `SliverToBoxAdapter`s plus the `bookingsAsync.when(...)` sliver in `if (widget.tab != _FinancesTab.revenue) ...[ ... ]` and add the revenue branch:

```dart
          if (widget.tab != _FinancesTab.revenue) ...[
            // (existing year stepper SliverToBoxAdapter)
            // (existing name search SliverToBoxAdapter)
            // (existing status pills SliverToBoxAdapter)
            // (existing bookingsAsync.when(...) sliver)
          ] else
            RevenueView(bandId: widget.bandId),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
```

> Note: `bookingsAsync` is currently computed at the top of `build` via `ref.watch(... )`. Move that watch inside the `if (widget.tab != _FinancesTab.revenue)` path, or guard it so the Revenue tab doesn't watch the unpaid/paid providers. Simplest: keep computing it (cheap), but only use it inside the non-revenue branch. Leaving the watch in place is fine — it just keeps that provider warm; the revenue branch ignores it.

Add the import for `revenueProvider` if not already transitively available — it lives in `../providers/finances_provider.dart`, which is already imported.

- [ ] **Step 4: Verify it compiles and analyze passes**

Run: `flutter analyze lib/features/finances/`
Expected: No errors.

- [ ] **Step 5: Run the full finances test suite**

Run: `flutter test test/features/finances/`
Expected: PASS (model + provider tests green).

- [ ] **Step 6: Commit**

```bash
git add lib/features/finances/screens/finances_screen.dart
git commit -m "feat(finances): add Revenue tab to finances screen"
```

---

### Task 8: Manual verification + final analyze

- [ ] **Step 1: Static analysis across the whole app**

Run: `flutter analyze`
Expected: No new errors introduced by this feature.

- [ ] **Step 2: Run the app and verify the Revenue tab**

Run: `flutter run -d chrome --dart-define=BASE_URL=http://localhost:8715` (or a connected device), with the backend running so the new endpoint is live. Navigate to Finances → Revenue and confirm:
- Summary cards show Total, current-year (if any), Years Active.
- Bar chart renders one bar per year, oldest on the left, tap shows a tooltip.
- Table lists years newest-first with YoY arrows/percentages and a Total row.
- A band with no recorded payments shows the "No revenue yet" empty state.
- Pull-to-refresh on the Revenue tab refetches.

> This step requires the Task 1 backend endpoint to be deployed/running locally against the same `BASE_URL`. If the backend isn't available, verify the three non-Revenue tabs still behave and defer live Revenue verification.

- [ ] **Step 3: Open the PRs**

Backend (in `/home/eddie/github/TTS`, base `staging`):
```bash
gh pr create --base staging --title "feat(mobile-api): band finances revenue endpoint" --body "Adds GET /api/mobile/bands/{band}/finances/revenue for the mobile Revenue tab."
```

Mobile (in this worktree, base `main`):
```bash
gh pr create --base main --title "feat(finances): revenue tab on mobile (web parity, slice 1)" --body "Adds a Revenue tab to the Finances screen: summary cards, fl_chart bar chart, and a year-by-year table with YoY change. Backed by the new mobile revenue endpoint."
```

---

## Notes for the implementer

- **Two repos, sequence matters:** Do Task 1 (backend) first so the endpoint exists; the mobile model/repo can be built and unit-tested without it (tests use fakes), but live verification (Task 8) needs the endpoint running.
- **Backend repo rules:** never run PHP on the host — always `docker compose exec app …`. Backend PRs target `staging` (auto-deploys on merge).
- **Mobile repo rules:** PRs target `main`. Stay on branch `feat/finances-revenue-mobile`.
- **Cents everywhere:** the API returns cents; only divide by 100 at display time (`RevenueYear.totalDollars`, `BandRevenue.formatCents`). Don't double-divide.
- **Read a sibling first:** for the backend test (Task 1) and the provider test (Task 4), read an existing sibling test to copy the exact fake/auth/factory patterns rather than guessing.
```
