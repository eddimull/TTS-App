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
