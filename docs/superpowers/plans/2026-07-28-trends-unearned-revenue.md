# Trends Unearned Revenue Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Unearned" stat card to the Trends tab showing total deposits held for not-yet-executed bookings (all years, as of today), backed by one new field in the trends API payload.

**Architecture:** The Laravel mobile trends endpoint gains a top-level `"unearned"` integer (cents), computed from the same unfiltered booking collection already loaded for `available_years`. The Flutter `FinanceTrends` model parses it (defaulting to 0), and `_SummaryCards` renders one new `_StatCard` next to Forecast. No new endpoints, providers, or repository methods.

**Tech Stack:** Laravel (TTS repo, PHPUnit via docker), Flutter/Dart (tts_bandmate repo, Riverpod v2, Cupertino widgets).

**Spec:** `docs/superpowers/specs/2026-07-28-trends-unearned-revenue-design.md`

## Global Constraints

- TTS repo (`/home/eddie/github/TTS`): PRs target `staging`, never `master`. Merging to staging auto-deploys.
- TTS repo: NEVER run `php`/`artisan`/`composer` on the host — always `docker compose exec app …`.
- tts_bandmate repo (`/home/eddie/github/tts_bandmate`): PRs target `main`. Work happens on the existing branch `feat/trends-unearned-revenue`.
- No hardcoded time-bomb dates in tests — compute all dates relative to `now()`.
- Definition (exact): `unearned` = sum of `amount_paid` over non-cancelled bookings with `start_date` **strictly after today**, across all years, in cents. Unaffected by `year`, `snapshot_date`, `compare_with_current`.
- Flutter UI: never use raw `CupertinoColors.secondaryLabel` for text color — use `context.secondaryText` (already imported in `trends_view.dart`).
- After `gh pr create`, wait for Copilot's auto-review and address its comments before calling a PR done.

---

### Task 1: Backend — `unearned` field in trends payload (TTS repo)

**Files:**
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/FinancesController.php:115-185`
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/FinanceTrendsTest.php`

**Interfaces:**
- Consumes: `FinanceServices::getPaidUnpaid([$band], null)` (existing) — returns bands with `paidBookings`/`unpaidBookings` collections; bookings expose `status`, `start_date`, `amount_paid` (dollars).
- Produces: trends JSON payload gains top-level `"unearned"` (int, cents). Task 2 parses exactly this key.

- [ ] **Step 1: Create the TTS feature branch**

```bash
cd /home/eddie/github/TTS
git fetch origin && git checkout -b feat/trends-unearned-revenue origin/staging
```

- [ ] **Step 2: Write the failing tests**

Add these two methods to `tests/Feature/Api/Mobile/FinanceTrendsTest.php` (before the closing brace; the existing `booking()` helper and `headers()` are reused as-is):

```php
public function test_unearned_sums_payments_on_strictly_future_bookings(): void
{
    $future = now()->addMonths(2)->format('Y-m-d');
    $nextYear = now()->addYear()->format('Y-m-d');
    $today = now()->format('Y-m-d');
    $past = now()->subMonths(2)->format('Y-m-d');

    // Partial deposit on a future booking → contributes amount_paid only.
    $this->booking($this->band, 2000, $future, paidDollars: 500);
    // Fully-paid booking in a future YEAR → contributes in full (all-years scope).
    $this->booking($this->band, 1000, $nextYear, paidDollars: 1000);
    // Event today counts as executed → excluded (strictly-after rule).
    $this->booking($this->band, 800, $today, paidDollars: 800);
    // Past booking → excluded even though fully paid.
    $this->booking($this->band, 3000, $past, paidDollars: 3000);
    // Cancelled future booking → excluded.
    $this->booking($this->band, 4000, $future, paidDollars: 4000, status: 'cancelled');

    $res = $this->withHeaders($this->headers($this->memberToken))
        ->getJson("/api/mobile/bands/{$this->band->id}/finances/trends?year=" . now()->year);

    $res->assertOk();
    // $500 + $1000 → 150000 cents.
    $res->assertJsonPath('unearned', 150000);
}

public function test_unearned_ignores_year_and_snapshot_params(): void
{
    $future = now()->addMonths(3)->format('Y-m-d');
    $this->booking(
        $this->band,
        1000,
        $future,
        paidDollars: 250,
        createdAt: now()->format('Y-m-d H:i:s'),
    );

    // Snapshot far in the past excludes the booking from the months series, and
    // the queried year has no bookings — unearned must be unaffected by both.
    $snapshot = now()->subYears(2)->format('Y-m-d');
    $lastYear = now()->subYear()->year;
    $res = $this->withHeaders($this->headers($this->memberToken))
        ->getJson("/api/mobile/bands/{$this->band->id}/finances/trends?year={$lastYear}&snapshot_date={$snapshot}");

    $res->assertOk();
    $res->assertJsonPath('unearned', 25000);
    // Sanity: the snapshot did filter the months series.
    $res->assertJsonPath('months.0.count', 0);
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd /home/eddie/github/TTS
docker compose exec app php artisan test --filter=FinanceTrendsTest
```

Expected: the two new tests FAIL (`unearned` key missing → assertJsonPath fails); all pre-existing tests still pass.

- [ ] **Step 4: Implement**

In `app/Http/Controllers/Api/Mobile/FinancesController.php`:

4a. In `trends()`, load the unfiltered booking collection once and feed it to both `available_years` and the new `unearned` field. Replace the `$payload` block:

```php
$months = $this->bucketByMonth($band, $year, $snapshotDate);
$allBookings = $this->allBookings($band);

$payload = [
    'year' => $year,
    'snapshot_date' => $snapshotDate,
    'available_years' => $this->availableYears($allBookings),
    'unearned' => $this->unearnedCents($allBookings),
    'months' => $months,
];
```

4b. Replace the existing `availableYears($band)` helper with a collection-based version plus the two new helpers (this removes availableYears' own duplicate `getPaidUnpaid` load — behavior is identical):

```php
/** All non-snapshot-filtered paid+unpaid bookings for the band. */
private function allBookings($band): \Illuminate\Support\Collection
{
    $bands = $this->financeServices->getPaidUnpaid([$band], null);
    $b = $bands->first();

    return collect($b->paidBookings)->concat(collect($b->unpaidBookings));
}

private function availableYears($bookings): array
{
    return $bookings
        ->filter(fn ($bk) => ($bk->status ?? null) !== 'cancelled' && !empty($bk->start_date))
        ->map(fn ($bk) => (int) \Carbon\Carbon::parse($bk->start_date)->year)
        ->unique()->sortDesc()->values()->all();
}

/**
 * Deposits held for performances that haven't happened yet: amount_paid on
 * non-cancelled bookings dated strictly after today, all years, in cents.
 */
private function unearnedCents($bookings): int
{
    $today = \Carbon\Carbon::today();

    $total = $bookings
        ->filter(fn ($bk) => ($bk->status ?? null) !== 'cancelled'
            && !empty($bk->start_date)
            && \Carbon\Carbon::parse($bk->start_date)->startOfDay()->gt($today))
        ->sum(fn ($bk) => (float) $bk->amount_paid);

    return (int) round($total * 100);
}
```

Also update the `trends()` docblock's last line to mention the new field:

```php
 * additionally returns the current (unfiltered) series as current_months.
 * Always includes `unearned`: cents collected on not-yet-executed bookings
 * (all years, as of today), independent of year/snapshot params.
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
docker compose exec app php artisan test --filter=FinanceTrendsTest
```

Expected: ALL tests pass (the two new ones plus all six pre-existing).

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Http/Controllers/Api/Mobile/FinancesController.php tests/Feature/Api/Mobile/FinanceTrendsTest.php
git commit -m "feat(mobile): add unearned deposits total to finances trends payload

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Flutter model — parse `unearned` (tts_bandmate repo)

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/finances/data/models/finance_trends.dart`
- Test: `/home/eddie/github/tts_bandmate/test/features/finances/finance_trends_test.dart`

**Interfaces:**
- Consumes: JSON key `"unearned"` (int cents, may be absent on older backends) from Task 1.
- Produces: `FinanceTrends.unearnedCents` — `final int`, defaults to 0. Task 3 reads exactly this getter.

- [ ] **Step 1: Write the failing tests**

Add to the `FinanceTrends.fromJson` group in `test/features/finances/finance_trends_test.dart` (the `_month` helper already exists at the top of the file):

```dart
test('parses unearned cents', () {
  final t = FinanceTrends.fromJson({
    'year': 2026,
    'available_years': [2026],
    'months': [_month(1)],
    'unearned': 150000,
  });
  expect(t.unearnedCents, 150000);
});

test('unearned defaults to 0 when the field is missing', () {
  final t = FinanceTrends.fromJson({
    'year': 2026,
    'available_years': [2026],
    'months': [_month(1)],
  });
  expect(t.unearnedCents, 0);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/eddie/github/tts_bandmate
flutter test test/features/finances/finance_trends_test.dart
```

Expected: compile error — `unearnedCents` isn't defined on `FinanceTrends`.

- [ ] **Step 3: Implement**

In `lib/features/finances/data/models/finance_trends.dart`, three edits to the `FinanceTrends` class:

Constructor — add after `required this.currentMonths,`:

```dart
    required this.unearnedCents,
```

Fields — add after `final List<TrendMonth>? currentMonths;`:

```dart
  /// Deposits held for not-yet-executed bookings (all years, as of today).
  final int unearnedCents;
```

`fromJson` — add after `currentMonths: current is List ? parse(current) : null,`:

```dart
      unearnedCents: (json['unearned'] as num?)?.toInt() ?? 0,
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/features/finances/finance_trends_test.dart
```

Expected: PASS (all groups — pre-existing tests construct via `fromJson`, so no other call sites break).

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/finances/data/models/finance_trends.dart test/features/finances/finance_trends_test.dart
git commit -m "feat(finances): parse unearned deposits total in FinanceTrends

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Flutter UI — Unearned stat card (tts_bandmate repo)

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/finances/screens/widgets/trends_view.dart` (`_SummaryCards` ~line 416, `_StatCard` ~line 482)
- Create: `/home/eddie/github/tts_bandmate/test/features/finances/trends_view_unearned_test.dart`

**Interfaces:**
- Consumes: `FinanceTrends.unearnedCents` (Task 2); existing `_fmtCents`, `_StatCard`, `financesRepositoryProvider`.
- Produces: user-visible card labeled `Unearned` with caption `as of today, all years`. No API for later tasks.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/finances/trends_view_unearned_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/finances_repository.dart';
import 'package:tts_bandmate/features/finances/data/models/band_revenue.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_booking.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_trends.dart';
import 'package:tts_bandmate/features/finances/providers/finances_provider.dart';
import 'package:tts_bandmate/features/finances/screens/widgets/trends_view.dart';

class _FakeRepo implements FinancesRepository {
  @override
  Future<FinanceTrends> fetchTrends(int bandId,
      {required int year,
      String? snapshotDate,
      bool compareWithCurrent = false}) async {
    return FinanceTrends.fromJson({
      'year': year,
      'available_years': [year],
      'unearned': 123456,
      'months': [
        {
          'month': 1,
          'paid': 100000,
          'unpaid': 0,
          'forecast': 100000,
          'net': 20000,
          'count': 1,
        }
      ],
    });
  }

  @override
  Future<List<FinanceBooking>> fetchUnpaid(int bandId, {int? year}) =>
      throw UnimplementedError();
  @override
  Future<List<FinanceBooking>> fetchPaid(int bandId, {int? year}) =>
      throw UnimplementedError();
  @override
  Future<BandRevenue> fetchRevenue(int bandId) => throw UnimplementedError();
}

void main() {
  testWidgets('renders Unearned card with as-of-today caption at 320pt',
      (tester) async {
    // User's phone is narrow (~320pt) — verify no overflow at that width.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financesRepositoryProvider.overrideWithValue(_FakeRepo()),
        ],
        child: const CupertinoApp(
          home: CustomScrollView(slivers: [TrendsView(bandId: 1)]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The summary cards sit below the chart — scroll them into view.
    await tester.scrollUntilVisible(find.text('UNEARNED'), 200);
    expect(find.text('UNEARNED'), findsOneWidget);
    expect(find.text('\$1,234.56'), findsOneWidget);
    expect(find.text('as of today, all years'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/eddie/github/tts_bandmate
flutter test test/features/finances/trends_view_unearned_test.dart
```

Expected: FAIL — `find.text('UNEARNED')` finds nothing (card not implemented yet). If the FinancesRepository interface has drifted from the fake above, mirror the overrides used in `test/features/finances/trends_provider_test.dart`.

- [ ] **Step 3: Implement the card**

In `lib/features/finances/screens/widgets/trends_view.dart`:

3a. `_StatCard` — add an optional caption. Constructor gains `this.caption,`; fields gain:

```dart
  final String? caption;
```

In `build`, after the value `Text(...)` (before the `if (delta != null ...)` block), add:

```dart
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!,
                style: TextStyle(fontSize: 9, color: context.secondaryText)),
          ],
```

3b. `_SummaryCards` — the last row currently holds a lone full-width Forecast card. Replace that final `Row` so Unearned joins it:

```dart
          Row(children: [
            Expanded(
              child: _StatCard(
                label: 'Forecast',
                value: _fmtCents(trends.totalForecastCents),
                tint: CupertinoColors.systemGreen.resolveFrom(context),
                deltaCents: trends.deltaForecastCents,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Unearned',
                value: _fmtCents(trends.unearnedCents),
                tint: CupertinoColors.systemTeal.resolveFrom(context),
                caption: 'as of today, all years',
              ),
            ),
          ]),
```

Note: no `deltaCents` on the Unearned card — it is snapshot-independent by design.

- [ ] **Step 4: Run the test and analyzer to verify they pass**

```bash
flutter test test/features/finances/trends_view_unearned_test.dart
flutter analyze
```

Expected: test PASSES (including at 320pt width — no overflow errors); analyzer clean.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/finances/screens/widgets/trends_view.dart test/features/finances/trends_view_unearned_test.dart
git commit -m "feat(finances): show unearned deposits card in trends summary

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Full suites, PRs, and verification

**Files:**
- No new code. Both repos' branches: `feat/trends-unearned-revenue`.

**Interfaces:**
- Consumes: Tasks 1–3 committed on their branches.
- Produces: two open PRs (TTS → staging, tts_bandmate → main), Copilot feedback addressed, on-device screenshot evidence.

- [ ] **Step 1: Run the full Flutter suite**

```bash
cd /home/eddie/github/tts_bandmate
flutter analyze && flutter test
```

Expected: analyzer clean, all tests pass.

- [ ] **Step 2: Run the backend finance tests**

```bash
cd /home/eddie/github/TTS
docker compose exec app php artisan test --filter=FinanceTrendsTest
docker compose exec app php artisan test --filter=FinancesControllerTest
```

Expected: all pass. (Known flaky files elsewhere in the suite re-run sequentially if touched — not expected here.)

- [ ] **Step 3: Push branches and open PRs**

```bash
cd /home/eddie/github/TTS
git push -u origin feat/trends-unearned-revenue
gh pr create --base staging \
  --title "feat(mobile): unearned deposits total in finances trends" \
  --body "Adds a top-level \`unearned\` field (cents) to GET /api/mobile/bands/{band}/finances/trends: amount_paid summed over non-cancelled bookings dated strictly after today, all years, independent of year/snapshot params. Backs the new Unearned card in the app's Trends tab.

Spec: tts_bandmate docs/superpowers/specs/2026-07-28-trends-unearned-revenue-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)"

cd /home/eddie/github/tts_bandmate
git push -u origin feat/trends-unearned-revenue
gh pr create --base main \
  --title "feat(finances): unearned deposits card in trends" \
  --body "Shows how much of the bank balance is deposits on not-yet-executed performances: new Unearned stat card in the Trends summary (as of today, all years, snapshot-independent). Parses the new \`unearned\` payload field, defaulting to 0 against older backends.

Backend pair: TTS PR feat/trends-unearned-revenue → staging.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 4: Wait for Copilot review on both PRs and address comments**

Check `gh pr view --comments` on each PR after a few minutes; fix anything substantive, push, and re-check.

- [ ] **Step 5: On-device verification**

Use the `run-on-device` skill (app on the physical Android phone against the local Laravel backend, which must have the TTS branch checked out and running): log in, open Finances → Trends, and screenshot the summary cards showing the Unearned card with a plausible value. Confirm no overflow on the narrow display.

- [ ] **Step 6: Report**

Summarize PR links, test results, and the on-device screenshot to the user. Merging is the user's call (TTS merge auto-deploys staging).

---

# Revision 2: year separation + tap breakdown (tasks 5-8)

Per the approved Revision 2 in the spec. Backend context that changed since
Task 1: PR TTS#553 merged to staging with the v1 scalar `unearned`; the
Copilot-fix commit 4aeaa722 sits on the re-pushed `feat/trends-unearned-revenue`
branch with no open PR. Tasks 5's work joins that commit in a follow-up PR
(Task 8). App PR #130 is open and absorbs tasks 6-7.

### Task 5: Backend — `unearned_by_year` in trends payload (TTS repo)

**Files:**
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/FinancesController.php` (trends() payload, unearnedCents helper)
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/FinanceTrendsTest.php`

**Interfaces:**
- Consumes: existing `allBookings(Bands $band): Collection` and the unearned filter predicate from `unearnedCents(Collection $bookings): int`.
- Produces: payload gains `"unearned_by_year"`: ascending-year list of `{"year": int, "amount": int}` (cents, only nonzero years); `"unearned"` (total) unchanged in value. Task 6 parses `unearned_by_year` exactly.

- [ ] **Step 1: Write the failing tests**

In `tests/Feature/Api/Mobile/FinanceTrendsTest.php`, extend `test_unearned_sums_payments_on_strictly_future_bookings` by appending these assertions after the existing `$res->assertJsonPath('unearned', 150000);` line (the test already creates: $500 paid on a future booking ~2 months out, $1000 fully-paid next year, and excluded today/past/cancelled bookings):

```php
        // Per-year breakdown: ascending years, only nonzero years, cents.
        $futureYear = (int) now()->addMonths(2)->year;
        $nextYear = (int) now()->addYear()->year;
        if ($futureYear === $nextYear) {
            // Rare window (Nov/Dec): both bookings share a year bucket.
            $this->assertSame(
                [['year' => $futureYear, 'amount' => 150000]],
                $res->json('unearned_by_year'),
            );
        } else {
            $this->assertSame(
                [
                    ['year' => $futureYear, 'amount' => 50000],
                    ['year' => $nextYear, 'amount' => 100000],
                ],
                $res->json('unearned_by_year'),
            );
        }
```

And in `test_unearned_ignores_year_and_snapshot_params`, after each existing `assertJsonPath('unearned', 25000)` assertion (both Request A and Request B), add:

```php
        $this->assertSame(
            [['year' => (int) now()->addMonths(3)->year, 'amount' => 25000]],
            $res->json('unearned_by_year'),
        );
```

(Variable is `$res` for Request A and whatever the test names Request B's response — match the actual variable names in the current test.)

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/eddie/github/TTS
docker compose exec app php artisan test --filter=FinanceTrendsTest
```

Expected: the two amended tests FAIL (`unearned_by_year` is null); the other six still pass.

- [ ] **Step 3: Implement**

In `FinancesController.php`:

3a. Replace the `unearnedCents(Collection $bookings): int` helper with a by-year version (same filter predicate, same per-booking cent rounding):

```php
    /**
     * Deposits held for performances that haven't happened yet, bucketed by the
     * booking's event-date year: amount_paid on non-cancelled bookings dated
     * strictly after today, in cents. Ascending years, nonzero amounts only.
     * Per-booking rounding ensures exact cent-level precision.
     */
    private function unearnedByYearCents(Collection $bookings): array
    {
        $today = \Carbon\Carbon::today();

        return $bookings
            ->filter(fn ($bk) => ($bk->status ?? null) !== 'cancelled'
                && !empty($bk->start_date)
                && \Carbon\Carbon::parse($bk->start_date)->startOfDay()->gt($today))
            ->groupBy(fn ($bk) => (int) \Carbon\Carbon::parse($bk->start_date)->year)
            ->map(fn ($group, $year) => [
                'year' => (int) $year,
                'amount' => (int) $group->sum(fn ($bk) => (int) round(((float) $bk->amount_paid) * 100)),
            ])
            ->filter(fn ($row) => $row['amount'] > 0)
            ->sortBy('year')
            ->values()
            ->all();
    }
```

3b. In `trends()`, derive both fields from one pass — replace the `'unearned' => $this->unearnedCents($allBookings),` payload line with:

```php
        $unearnedByYear = $this->unearnedByYearCents($allBookings);

        $payload = [
            'year' => $year,
            'snapshot_date' => $snapshotDate,
            'available_years' => $this->availableYears($allBookings),
            'unearned' => array_sum(array_column($unearnedByYear, 'amount')),
            'unearned_by_year' => $unearnedByYear,
            'months' => $months,
        ];
```

(The `$unearnedByYear` line goes right before the `$payload` array; the old standalone `unearnedCents` method is deleted.)

3c. Extend the `trends()` docblock's `unearned` sentence:

```php
 * Always includes `unearned` (cents collected on not-yet-executed bookings,
 * all years, as of today) and `unearned_by_year` (the same figure bucketed by
 * event-date year, ascending, nonzero years only) — both independent of
 * year/snapshot params.
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
docker compose exec app php artisan test --filter=FinanceTrendsTest
```

Expected: all 8 pass.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Http/Controllers/Api/Mobile/FinancesController.php tests/Feature/Api/Mobile/FinanceTrendsTest.php
git commit -m "feat(mobile): bucket unearned deposits by event year in trends payload

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Flutter model — parse `unearned_by_year` (tts_bandmate repo)

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/finances/data/models/finance_trends.dart`
- Test: `/home/eddie/github/tts_bandmate/test/features/finances/finance_trends_test.dart`

**Interfaces:**
- Consumes: JSON `"unearned_by_year"` list of `{"year": int, "amount": int}` (may be absent on older backends).
- Produces: `FinanceTrends.unearnedByYearCents` — `final Map<int, int>`, empty when absent; `int unearnedForYear(int year)` returning 0 for absent years. Task 7 uses both plus the existing `unearnedCents`.

- [ ] **Step 1: Write the failing tests**

Add to the `FinanceTrends.fromJson` group in `test/features/finances/finance_trends_test.dart`:

```dart
    test('parses unearned_by_year into a year map', () {
      final t = FinanceTrends.fromJson({
        'year': 2026,
        'available_years': [2026],
        'months': [_month(1)],
        'unearned': 150000,
        'unearned_by_year': [
          {'year': 2026, 'amount': 50000},
          {'year': 2027, 'amount': 100000},
        ],
      });
      expect(t.unearnedByYearCents, {2026: 50000, 2027: 100000});
      expect(t.unearnedForYear(2026), 50000);
      expect(t.unearnedForYear(2027), 100000);
      expect(t.unearnedForYear(2030), 0);
    });

    test('unearned_by_year defaults to empty when missing', () {
      final t = FinanceTrends.fromJson({
        'year': 2026,
        'available_years': [2026],
        'months': [_month(1)],
      });
      expect(t.unearnedByYearCents, isEmpty);
      expect(t.unearnedForYear(2026), 0);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/eddie/github/tts_bandmate
flutter test test/features/finances/finance_trends_test.dart
```

Expected: compile error — `unearnedByYearCents` undefined.

- [ ] **Step 3: Implement**

In `lib/features/finances/data/models/finance_trends.dart`, in `FinanceTrends`:

Constructor — after `required this.unearnedCents,`:

```dart
    required this.unearnedByYearCents,
```

Fields — after the `unearnedCents` field:

```dart
  /// Unearned deposits bucketed by event-date year (cents). Empty when the
  /// backend doesn't send the field.
  final Map<int, int> unearnedByYearCents;
```

Getter — next to the other derived getters:

```dart
  int unearnedForYear(int year) => unearnedByYearCents[year] ?? 0;
```

`fromJson` — after the `unearnedCents:` line:

```dart
      unearnedByYearCents: {
        for (final e in (json['unearned_by_year'] as List<dynamic>? ?? const []))
          ((e as Map<String, dynamic>)['year'] as num).toInt():
              (e['amount'] as num?)?.toInt() ?? 0,
      },
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/features/finances/finance_trends_test.dart
```

Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/finances/data/models/finance_trends.dart test/features/finances/finance_trends_test.dart
git commit -m "feat(finances): parse per-year unearned deposits in FinanceTrends

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Flutter UI — year-scoped card + breakdown sheet (tts_bandmate repo)

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/finances/screens/widgets/trends_view.dart` (`_SummaryCards`, new `_UnearnedBreakdownSheet`)
- Modify: `/home/eddie/github/tts_bandmate/test/features/finances/trends_view_unearned_test.dart`

**Interfaces:**
- Consumes: `FinanceTrends.unearnedForYear(int)`, `.unearnedByYearCents`, `.unearnedCents` (Task 6); existing `_fmtCents`, `_StatCard` (with its `caption` param), `context.secondaryText`.
- Produces: user-visible year-scoped Unearned card; tap opens the breakdown sheet. No API for later tasks.

- [ ] **Step 1: Rewrite the widget test (failing first)**

Replace the body of `test/features/finances/trends_view_unearned_test.dart`'s `main()` (keep the existing `_FakeRepo` class but update its `fetchTrends` payload) so the fake returns year-relative data and the test drives the tap:

```dart
  // In _FakeRepo.fetchTrends, replace the returned FinanceTrends.fromJson map with:
    final thisYear = DateTime.now().year;
    return FinanceTrends.fromJson({
      'year': year,
      'available_years': [year],
      'unearned': 123456,
      'unearned_by_year': [
        {'year': thisYear, 'amount': 50000},
        {'year': thisYear + 1, 'amount': 73456},
      ],
      'months': [
        {
          'month': 1,
          'paid': 100000,
          'unpaid': 0,
          'forecast': 100000,
          'net': 20000,
          'count': 1,
        }
      ],
    });
```

```dart
void main() {
  Future<void> pumpTrends(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financesRepositoryProvider.overrideWithValue(_FakeRepo()),
        ],
        child: const CupertinoApp(
          home: CustomScrollView(slivers: [TrendsView(bandId: 1)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('UNEARNED'), 200);
  }

  testWidgets('Unearned card is year-scoped with tap affordance at 320pt',
      (tester) async {
    await pumpTrends(tester);

    expect(find.text('UNEARNED'), findsOneWidget);
    // Selected year defaults to the current year → that year's bucket only.
    expect(find.text('\$500.00'), findsOneWidget);
    expect(find.text('tap for all years'), findsOneWidget);
    // The all-years total is NOT on the card.
    expect(find.text('\$1,234.56'), findsNothing);
  });

  testWidgets('tapping the Unearned card opens the per-year breakdown sheet',
      (tester) async {
    await pumpTrends(tester);

    await tester.tap(find.text('UNEARNED'));
    await tester.pumpAndSettle();

    final thisYear = DateTime.now().year;
    expect(find.text('Unearned deposits'), findsOneWidget);
    expect(find.text('$thisYear'), findsWidgets); // year row (year picker may also show it)
    expect(find.text('${thisYear + 1}'), findsOneWidget);
    expect(find.text('\$500.00'), findsWidgets); // card + sheet row
    expect(find.text('\$734.56'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('\$1,234.56'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/eddie/github/tts_bandmate
flutter test test/features/finances/trends_view_unearned_test.dart
```

Expected: FAIL — card still shows the all-years total and old caption; no sheet.

- [ ] **Step 3: Implement**

In `lib/features/finances/screens/widgets/trends_view.dart`:

3a. `_SummaryCards` gains the selected year and the tap handler. Change the class header:

```dart
class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.trends, required this.year});
  final FinanceTrends trends;
  final int year;
```

and update the call site in `_TrendsViewState.build`:

```dart
          _SummaryCards(trends: trends, year: _year),
```

3b. Replace the Unearned `_StatCard` in the last row with a tappable, year-scoped one:

```dart
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showCupertinoModalPopup<void>(
                  context: context,
                  builder: (_) => _UnearnedBreakdownSheet(trends: trends),
                ),
                child: _StatCard(
                  label: 'Unearned',
                  value: _fmtCents(trends.unearnedForYear(year)),
                  tint: CupertinoColors.systemTeal.resolveFrom(context),
                  caption: 'tap for all years',
                ),
              ),
            ),
```

3c. Add the sheet widget (place it after `_StatCard`/`_DeltaBadge`, before `_EmptyBody`):

```dart
// ── Unearned breakdown ────────────────────────────────────────────────────────

/// Bottom sheet listing unearned deposits per event year with the all-years
/// total. Opened by tapping the Unearned stat card.
class _UnearnedBreakdownSheet extends StatelessWidget {
  const _UnearnedBreakdownSheet({required this.trends});
  final FinanceTrends trends;

  @override
  Widget build(BuildContext context) {
    final years = trends.unearnedByYearCents.keys.toList()..sort();

    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                      color: CupertinoColors.label.resolveFrom(context))),
              Text(value,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                      color: CupertinoColors.label.resolveFrom(context))),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
              child: Text('Unearned deposits',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.label.resolveFrom(context))),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Deposits held for future performances · as of today',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12, color: context.secondaryText)),
            ),
            for (final y in years)
              row('$y', _fmtCents(trends.unearnedByYearCents[y]!)),
            Container(
              height: 0.5,
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              color: CupertinoColors.separator.resolveFrom(context),
            ),
            row('Total', _fmtCents(trends.unearnedCents), bold: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests and analyzer**

```bash
flutter test test/features/finances/trends_view_unearned_test.dart
flutter analyze
```

Expected: both widget tests pass at 320pt; analyzer shows only the 4 pre-existing issues.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/finances/screens/widgets/trends_view.dart test/features/finances/trends_view_unearned_test.dart
git commit -m "feat(finances): year-scoped unearned card with per-year breakdown sheet

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Revision wrap-up — suites, PRs, verification

- [ ] Full suites: `flutter analyze && flutter test` (app repo); `docker compose exec app php artisan test --filter=FinanceTrendsTest` and `--filter=FinancesControllerTest` (TTS repo).
- [ ] Push app branch (updates open PR #130); update PR #130's body to describe the year-scoped card + breakdown sheet.
- [ ] Push TTS branch and open a NEW PR → staging titled "feat(mobile): per-year unearned deposits in finances trends" whose body notes it follows up merged #553 (contains the Copilot fixes 4aeaa722 + the by-year field).
- [ ] Wait for Copilot on both, address comments.
- [ ] On-device verify: Finances → Trends shows the year-scoped card; tapping opens the sheet with per-year rows + total; screenshot to user.
