# Stats Upcoming Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show upcoming (booked-but-unplayed) earnings in the three stats views — stacked bar (Earnings by Year), paired lighter-hue donut slices (Earnings by Band), and a compact inline card line (Bookings by Year) — derived entirely client-side from the existing `bookings_by_year` payload.

**Architecture:** No backend / API changes. Two new client-side aggregations over `bookings_by_year` (which already contains every earned + upcoming booking row tagged with `band_id`, `band_name`, `is_upcoming`, `user_share`, including future-only years and upcoming-only bands): `byYearWithUpcoming` → `{year, earned, upcoming}` and `byBandWithUpcoming` → `{bandId, bandName, earned, upcoming}`. Mobile charts switch to these derived lists; web charts switch to Vue computed props derived the same way.

**Tech Stack:** Flutter / Dart + `fl_chart` (mobile, repo `TTS-App` at `/home/eddie/github/tts_bandmate`); Vue 3 Options API + Chart.js (web, repo `TTS` at `/home/eddie/github/TTS`).

**Branches:** mobile work on `feat/stats-upcoming-presentation` (already created, off `feat/stats-earned-vs-upcoming`). Web work: create `feat/stats-upcoming-presentation` in `/home/eddie/github/TTS` off `staging` (see Task 7).

---

## File Structure

**Mobile (`TTS-App`):**
- Modify `lib/features/stats/data/models/user_stats.dart` — add two breakdown value types (`YearBreakdown`, `BandBreakdown`) and two pure aggregation helpers on `PaymentStats` (`yearBreakdown`, `bandBreakdown`).
- Modify `lib/features/stats/screens/widgets/earnings_bar_chart.dart` — stacked earned+upcoming bar.
- Modify `lib/features/stats/screens/widgets/earnings_pie_chart.dart` — paired earned/upcoming slices per band.
- Modify `lib/features/stats/screens/widgets/bookings_by_year_section.dart` — compact inline card line, drop the standalone total.
- Modify `lib/features/stats/screens/user_stats_screen.dart` — pass the derived lists to the charts.
- Test `test/features/stats/stats_breakdown_test.dart` (new) — unit-test the two aggregation helpers.

**Web (`TTS`):**
- Modify `resources/js/Pages/UserStats/Index.vue` — computed `byYearWithUpcoming` / `byBandWithUpcoming`, stacked bar config, paired donut config, inline card header.

---

## Task 1: Mobile — aggregation helpers + value types

**Files:**
- Modify: `lib/features/stats/data/models/user_stats.dart` (add after the `PaymentStats` class, around line 70)
- Test: `test/features/stats/stats_breakdown_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/stats/stats_breakdown_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/stats/data/models/user_stats.dart';

PaymentStats _payments(List<Map<String, dynamic>> rows) {
  return PaymentStats.fromJson({
    'total_earnings': '0.00',
    'booking_count': 0,
    'upcoming_earnings': '0.00',
    'upcoming_booking_count': 0,
    'by_year': [],
    'by_band': [],
    'bookings_by_year': [
      {
        'year': null,
        'year_total': '0.00',
        'booking_count': 0,
        'upcoming_total': '0.00',
        'upcoming_booking_count': 0,
        'bookings': rows,
      },
    ],
  });
}

Map<String, dynamic> _row({
  required int bandId,
  required String bandName,
  required String date,
  required bool upcoming,
  required String share,
}) => {
      'id': bandId * 100,
      'booking_name': 'Gig',
      'band_name': bandName,
      'band_id': bandId,
      'venue_name': 'V',
      'venue_address': null,
      'date': date,
      'status': 'confirmed',
      'is_upcoming': upcoming,
      'total_price': '0.00',
      'user_share': share,
    };

void main() {
  group('yearBreakdown', () {
    test('splits earned and upcoming per year, including future-only years', () {
      final p = _payments([
        _row(bandId: 1, bandName: 'A', date: '2025-01-01', upcoming: false, share: '1000.00'),
        _row(bandId: 1, bandName: 'A', date: '2026-09-01', upcoming: true, share: '400.00'),
        _row(bandId: 1, bandName: 'A', date: '2027-01-01', upcoming: true, share: '250.00'),
      ]);

      final years = p.yearBreakdown;

      final y2025 = years.firstWhere((y) => y.year == 2025);
      expect(y2025.earned, 1000.0);
      expect(y2025.upcoming, 0.0);

      final y2027 = years.firstWhere((y) => y.year == 2027);
      expect(y2027.earned, 0.0); // future-only year still appears
      expect(y2027.upcoming, 250.0);
    });

    test('sorts years ascending', () {
      final p = _payments([
        _row(bandId: 1, bandName: 'A', date: '2027-01-01', upcoming: true, share: '1.00'),
        _row(bandId: 1, bandName: 'A', date: '2025-01-01', upcoming: false, share: '1.00'),
      ]);
      expect(p.yearBreakdown.map((y) => y.year).toList(), [2025, 2027]);
    });
  });

  group('bandBreakdown', () {
    test('groups earned and upcoming per band, including upcoming-only bands', () {
      final p = _payments([
        _row(bandId: 1, bandName: 'Rockers', date: '2025-01-01', upcoming: false, share: '1000.00'),
        _row(bandId: 1, bandName: 'Rockers', date: '2026-09-01', upcoming: true, share: '400.00'),
        _row(bandId: 2, bandName: 'Jazz', date: '2026-12-01', upcoming: true, share: '300.00'),
      ]);

      final bands = p.bandBreakdown;

      final rockers = bands.firstWhere((b) => b.bandId == 1);
      expect(rockers.earned, 1000.0);
      expect(rockers.upcoming, 400.0);

      final jazz = bands.firstWhere((b) => b.bandId == 2);
      expect(jazz.earned, 0.0); // upcoming-only band still appears
      expect(jazz.upcoming, 300.0);
    });

    test('sorts bands by total (earned + upcoming) descending', () {
      final p = _payments([
        _row(bandId: 1, bandName: 'Small', date: '2025-01-01', upcoming: false, share: '100.00'),
        _row(bandId: 2, bandName: 'Big', date: '2025-01-01', upcoming: false, share: '900.00'),
      ]);
      expect(p.bandBreakdown.map((b) => b.bandName).toList(), ['Big', 'Small']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/stats/stats_breakdown_test.dart`
Expected: FAIL — `yearBreakdown` / `bandBreakdown` / `YearBreakdown` / `BandBreakdown` not defined.

- [ ] **Step 3: Add the value types and helpers**

In `lib/features/stats/data/models/user_stats.dart`, immediately after the closing `}` of the `PaymentStats` class, add:

```dart
/// A year's earnings split into earned (played) and upcoming (booked) shares.
class YearBreakdown {
  const YearBreakdown({required this.year, required this.earned, required this.upcoming});

  final int year;
  final double earned;
  final double upcoming;

  double get total => earned + upcoming;
}

/// A band's earnings split into earned (played) and upcoming (booked) shares.
class BandBreakdown {
  const BandBreakdown({
    required this.bandId,
    required this.bandName,
    required this.earned,
    required this.upcoming,
  });

  final int bandId;
  final String bandName;
  final double earned;
  final double upcoming;

  double get total => earned + upcoming;
}
```

Then add two getters inside the `PaymentStats` class body (e.g. just before its closing `}`), deriving from `bookingsByYear`:

```dart
  /// Per-year earned vs upcoming, sorted ascending, derived from every booking
  /// row (so future-only years appear with earned == 0).
  List<YearBreakdown> get yearBreakdown {
    final earned = <int, double>{};
    final upcoming = <int, double>{};
    for (final yearGroup in bookingsByYear) {
      final y = yearGroup.year;
      if (y == null) continue; // undated bookings have no year bucket on a chart
      for (final b in yearGroup.bookings) {
        if (b.isUpcoming) {
          upcoming[y] = (upcoming[y] ?? 0) + b.userShare;
        } else {
          earned[y] = (earned[y] ?? 0) + b.userShare;
        }
      }
    }
    final years = {...earned.keys, ...upcoming.keys}.toList()..sort();
    return years
        .map((y) => YearBreakdown(
              year: y,
              earned: earned[y] ?? 0,
              upcoming: upcoming[y] ?? 0,
            ))
        .toList();
  }

  /// Per-band earned vs upcoming, sorted by total descending, derived from every
  /// booking row (so upcoming-only bands appear with earned == 0).
  List<BandBreakdown> get bandBreakdown {
    final earned = <int, double>{};
    final upcoming = <int, double>{};
    final names = <int, String>{};
    for (final yearGroup in bookingsByYear) {
      for (final b in yearGroup.bookings) {
        names[b.bandId] = b.bandName;
        if (b.isUpcoming) {
          upcoming[b.bandId] = (upcoming[b.bandId] ?? 0) + b.userShare;
        } else {
          earned[b.bandId] = (earned[b.bandId] ?? 0) + b.userShare;
        }
      }
    }
    final bands = {...earned.keys, ...upcoming.keys}
        .map((id) => BandBreakdown(
              bandId: id,
              bandName: names[id] ?? 'Unknown',
              earned: earned[id] ?? 0,
              upcoming: upcoming[id] ?? 0,
            ))
        .toList();
    bands.sort((a, b) => b.total.compareTo(a.total));
    return bands;
  }
```

**Required first:** `BookingRow` currently has `bandName` but NOT `bandId` (confirmed). Add it so `bandBreakdown` can group by a stable id:
- Add `final int bandId;` to `BookingRow` (next to `bandName`).
- Add `required this.bandId,` to the `BookingRow` constructor.
- In `BookingRow.fromJson`, add `bandId: (json['band_id'] as num?)?.toInt() ?? 0,`.

The backend already emits `'band_id' => $band->id` on every `bookings_by_year` row, so no payload change is needed. The Task 1 test fixture's `_row` helper already includes `'band_id': bandId`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/stats/stats_breakdown_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Run analyzer**

Run: `cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/stats test/features/stats`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/stats/data/models/user_stats.dart test/features/stats/stats_breakdown_test.dart
git commit -m "Add per-year/per-band earned-vs-upcoming aggregation helpers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Mobile — stacked Earnings by Year bar

**Files:**
- Modify: `lib/features/stats/screens/widgets/earnings_bar_chart.dart` (full rewrite of the rod-building + props)
- Modify: `lib/features/stats/screens/user_stats_screen.dart:71`

- [ ] **Step 1: Change the widget to accept `YearBreakdown` and stack two segments**

Replace the contents of `earnings_bar_chart.dart` with a version that:
1. Takes `final List<YearBreakdown> byYear;` instead of `List<YearEarnings>`.
2. Computes `maxY` from `e.total` (earned + upcoming).
3. Builds each rod with a single `BarChartRodData` whose `toY` is `total` and which uses `rodStackItems` to draw earned (green, 0→earned) then upcoming (gray, earned→total):

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/user_stats.dart';

/// Vertical stacked bar chart — one bar per year: earned (green) with the
/// upcoming (booked-but-unplayed) portion stacked on top in gray.
class EarningsBarChart extends StatelessWidget {
  const EarningsBarChart({super.key, required this.byYear});

  final List<YearBreakdown> byYear;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final gray = CupertinoColors.systemGrey.resolveFrom(context);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);

    final maxY = byYear.map((e) => e.total).fold(0.0, (a, b) => a > b ? a : b);
    final chartMax = maxY * 1.1;

    final barGroups = byYear.asMap().entries.map((entry) {
      final y = entry.value;
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: y.total,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            rodStackItems: [
              BarChartRodStackItem(0, y.earned, green),
              BarChartRodStackItem(y.earned, y.total, gray.withValues(alpha: 0.55)),
            ],
          ),
        ],
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 200,
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
                    if (idx < 0 || idx >= byYear.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${byYear[idx].year}',
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
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, __) {
                  final y = byYear[group.x.toInt()];
                  final upcomingLine =
                      y.upcoming > 0 ? '\n${currency.format(y.upcoming)} upcoming' : '';
                  return BarTooltipItem(
                    '${y.year}\n${currency.format(y.earned)} earned$upcomingLine',
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

- [ ] **Step 2: Update the call site**

In `user_stats_screen.dart`, change the guard and the prop. Find:
```dart
        if (stats.payments.byYear.isNotEmpty) ...[
```
and the `EarningsBarChart(byYear: stats.payments.byYear),` line. Replace both so the section shows when there is any breakdown and passes the derived list. Capture once above the widget list if convenient, else inline:
```dart
        if (stats.payments.yearBreakdown.isNotEmpty) ...[
          // ...existing heading widgets unchanged...
          EarningsBarChart(byYear: stats.payments.yearBreakdown),
```

- [ ] **Step 3: Analyze**

Run: `cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/stats`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/stats/screens/widgets/earnings_bar_chart.dart lib/features/stats/screens/user_stats_screen.dart
git commit -m "Stack upcoming earnings (gray) on the Earnings by Year bars

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Mobile — paired Earnings by Band donut

**Files:**
- Modify: `lib/features/stats/screens/widgets/earnings_pie_chart.dart`
- Modify: `lib/features/stats/screens/user_stats_screen.dart:79`

- [ ] **Step 1: Change the widget to accept `BandBreakdown` and emit paired slices**

Rewrite `earnings_pie_chart.dart` so it takes `final List<BandBreakdown> byBand;`, assigns each band a base color by its index, and emits up to two pie sections + two legend rows per band: earned (base color) and upcoming (`baseColor.withValues(alpha: 0.4)`, label `"<band> (upcoming)"`). Skip zero-value portions.

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/user_stats.dart';

/// Doughnut chart — each band contributes an earned slice (band color) and,
/// when it has booked-but-unplayed gigs, a lighter "upcoming" slice in the
/// same hue. Legend lists each portion separately.
class EarningsPieChart extends StatelessWidget {
  const EarningsPieChart({super.key, required this.byBand});

  final List<BandBreakdown> byBand;

  static const _palette = [
    Color(0xFF34C759),
    Color(0xFF007AFF),
    Color(0xFFFF9500),
    Color(0xFFAF52DE),
    Color(0xFFFF3B30),
    Color(0xFF5AC8FA),
  ];

  Color _colorFor(int index) => _palette[index % _palette.length];

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    // Build (label, value, color) entries: earned then upcoming per band.
    final entries = <({String label, double value, Color color})>[];
    for (var i = 0; i < byBand.length; i++) {
      final band = byBand[i];
      final base = _colorFor(i);
      if (band.earned > 0) {
        entries.add((label: band.bandName, value: band.earned, color: base));
      }
      if (band.upcoming > 0) {
        entries.add((
          label: '${band.bandName} (upcoming)',
          value: band.upcoming,
          color: base.withValues(alpha: 0.4),
        ));
      }
    }

    final sections = entries
        .map((e) => PieChartSectionData(
              value: e.value,
              color: e.color,
              showTitle: false,
              radius: 60,
            ))
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 50,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(e.label,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        currency.format(e.value),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Update the call site**

In `user_stats_screen.dart`, change:
```dart
        if (stats.payments.byBand.isNotEmpty) ...[
```
to `if (stats.payments.bandBreakdown.isNotEmpty) ...[` and
`EarningsPieChart(byBand: stats.payments.byBand),` to
`EarningsPieChart(byBand: stats.payments.bandBreakdown),`.

- [ ] **Step 3: Analyze**

Run: `cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/stats`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/stats/screens/widgets/earnings_pie_chart.dart lib/features/stats/screens/user_stats_screen.dart
git commit -m "Add lighter-hue upcoming slices per band to the donut

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Mobile — compact inline Bookings by Year card

**Files:**
- Modify: `lib/features/stats/screens/widgets/bookings_by_year_section.dart` (the `_YearGroup.build` header)

- [ ] **Step 1: Rework the year-header subtitle to the inline format and drop the standalone total**

In `_YearGroup.build` (in `bookings_by_year_section.dart`), the header currently shows `yearLabel` plus a subtitle `'$playedLabel  •  ${currency.format(year.yearTotal)}$upcomingSuffix'`. Replace the subtitle construction so it reads:

`<n> bookings · $<earned> earned · $<upcoming> upcoming`

Compute the total booking count as `year.bookingCount + year.upcomingBookingCount`. Replace the existing `playedLabel`/`upcomingSuffix`/`upcomingSpoken` block with:

```dart
    // Bookings with no events yet have no year — bucket them under "TBD".
    final yearLabel = year.year?.toString() ?? 'TBD';

    final totalBookings = year.bookingCount + year.upcomingBookingCount;
    final hasUpcoming = year.upcomingBookingCount > 0;

    // Compact inline line: "43 bookings · $1,000 earned · $400 upcoming".
    final inlineLine = StringBuffer(
      '$totalBookings booking${totalBookings == 1 ? '' : 's'}'
      ' · ${currency.format(year.yearTotal)} earned',
    );
    if (hasUpcoming) {
      inlineLine.write(' · ${currency.format(year.upcomingTotal)} upcoming');
    }

    // Spoken form spells out the separators for screen readers.
    final spoken = StringBuffer(
      '$yearLabel, $totalBookings booking${totalBookings == 1 ? '' : 's'},'
      ' ${currency.format(year.yearTotal)} earned',
    );
    if (hasUpcoming) {
      spoken.write(', ${currency.format(year.upcomingTotal)} upcoming');
    }
```

Then in the markup:
- Set the `Semantics` `label:` to `spoken.toString()`.
- Keep the `Text(yearLabel, ...)` heading.
- Replace the subtitle `Text(...)` content with `inlineLine.toString()`.
- **Remove** the right-side `Column`/`Text` block that renders the standalone `currency.format(year.yearTotal)` total (the `Expanded`/trailing total) — the inline line now carries the numbers. Keep the expand/collapse chevron.

Reference: `currency` is `NumberFormat.currency(symbol: '\$', decimalDigits: 0)` — confirm the existing one in this method already uses that; if it uses `decimalDigits: 2`, keep whatever is already there for consistency with the rest of the card.

- [ ] **Step 2: Analyze**

Run: `cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/stats`
Expected: No issues found.

- [ ] **Step 3: Run the full mobile stats suite**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/stats`
Expected: PASS (existing tests + Task 1's new tests). If any existing widget test asserted on the old "$total" header text, update it to the new inline string.

- [ ] **Step 4: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/stats/screens/widgets/bookings_by_year_section.dart
git commit -m "Show compact inline bookings/earned/upcoming line, drop standalone total

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Mobile — clean up now-unused earned-only chart inputs

**Files:**
- Modify: `lib/features/stats/data/models/user_stats.dart` (only if `YearEarnings`/`BandEarnings` are now unused)

- [ ] **Step 1: Check for remaining references**

Run: `cd /home/eddie/github/tts_bandmate && grep -rn "YearEarnings\|BandEarnings\|\.byYear\b\|\.byBand\b" lib/ test/`
- `PaymentStats.byYear` / `byBand` still parse from the payload and may be referenced elsewhere (e.g. nothing else). If the ONLY references are the now-replaced chart call sites, you may leave the parsed fields in place (harmless, keeps payload parsing total) — do NOT delete payload fields, just confirm no dangling references to removed widget props.

- [ ] **Step 2: Analyze the whole feature + run tests**

Run: `cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/stats test/features/stats && flutter test test/features/stats`
Expected: No issues; all tests pass.

- [ ] **Step 3: Commit (only if changes were made)**

```bash
cd /home/eddie/github/tts_bandmate
git add -A
git commit -m "Tidy unused earned-only chart inputs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Mobile — push branch and open PR

- [ ] **Step 1: Push**

```bash
cd /home/eddie/github/tts_bandmate
git push -u origin feat/stats-upcoming-presentation
```

- [ ] **Step 2: Open PR against `main`** (do NOT auto-merge)

```bash
gh pr create --repo eddimull/TTS-App --base main --head feat/stats-upcoming-presentation \
  --title "Present upcoming earnings in stats charts and cards" \
  --body "Stacked Earnings-by-Year bars (earned green + upcoming gray), paired lighter-hue upcoming donut slices per band, and a compact inline 'N bookings · \$earned · \$upcoming' Bookings-by-Year card (standalone total dropped). All derived client-side from bookings_by_year — no API change. See docs/superpowers/specs/2026-06-19-stats-upcoming-presentation-design.md."
```

- [ ] **Step 3: Request Copilot review**

```bash
gh api repos/eddimull/TTS-App/pulls/<N>/requested_reviewers -X POST -f "reviewers[]=copilot-pull-request-reviewer[bot]"
```

---

## Task 7: Web — mirror the three views in `Index.vue`

**Files:**
- Modify: `/home/eddie/github/TTS/resources/js/Pages/UserStats/Index.vue`

- [ ] **Step 1: Branch off staging**

```bash
cd /home/eddie/github/TTS
git fetch origin
git checkout -b feat/stats-upcoming-presentation origin/staging
```

- [ ] **Step 2: Add computed aggregations**

In the Vue component's `computed: { ... }` block, add (deriving from `this.stats.payments.bookings_by_year`, whose rows carry `band_id`, `band_name`, `is_upcoming`, `user_share`):

```js
    byYearWithUpcoming() {
      const earned = {}, upcoming = {}
      for (const yg of this.stats.payments.bookings_by_year) {
        if (yg.year == null) continue
        for (const b of yg.bookings) {
          const bucket = b.is_upcoming ? upcoming : earned
          bucket[yg.year] = (bucket[yg.year] || 0) + parseFloat(b.user_share)
        }
      }
      const years = [...new Set([...Object.keys(earned), ...Object.keys(upcoming)])]
        .map(Number).sort((a, b) => a - b)
      return years.map(y => ({ year: y, earned: earned[y] || 0, upcoming: upcoming[y] || 0 }))
    },
    byBandWithUpcoming() {
      const earned = {}, upcoming = {}, names = {}
      for (const yg of this.stats.payments.bookings_by_year) {
        for (const b of yg.bookings) {
          names[b.band_id] = b.band_name
          const bucket = b.is_upcoming ? upcoming : earned
          bucket[b.band_id] = (bucket[b.band_id] || 0) + parseFloat(b.user_share)
        }
      }
      return Object.keys(names)
        .map(id => ({
          bandId: Number(id),
          bandName: names[id],
          earned: earned[id] || 0,
          upcoming: upcoming[id] || 0,
        }))
        .sort((a, b) => (b.earned + b.upcoming) - (a.earned + a.upcoming))
    },
```

- [ ] **Step 3: Stacked Earnings-by-Year chart**

In `createCharts()`, replace the Earnings-by-Year chart block. Guard on `this.byYearWithUpcoming.length > 0`, use two stacked datasets:

```js
      if (this.$refs.earningsByYearChart && this.byYearWithUpcoming.length > 0) {
        const ctx = this.$refs.earningsByYearChart.getContext('2d')
        const rows = this.byYearWithUpcoming
        this.yearChart = new Chart(ctx, {
          type: 'bar',
          data: {
            labels: rows.map(r => r.year),
            datasets: [
              {
                label: 'Earned',
                data: rows.map(r => r.earned),
                backgroundColor: 'rgba(34, 197, 94, 0.6)',
                borderColor: 'rgba(34, 197, 94, 1)',
                borderWidth: 1,
              },
              {
                label: 'Upcoming',
                data: rows.map(r => r.upcoming),
                backgroundColor: 'rgba(156, 163, 175, 0.5)',
                borderColor: 'rgba(156, 163, 175, 1)',
                borderWidth: 1,
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: true,
            aspectRatio: 2,
            plugins: { legend: { display: true, position: 'bottom' } },
            scales: {
              x: { stacked: true },
              y: {
                stacked: true,
                beginAtZero: true,
                ticks: { callback: (v) => '$' + v.toLocaleString() },
              },
            },
          },
        })
      }
```

- [ ] **Step 4: Paired Earnings-by-Band donut**

Replace the Earnings-by-Band chart block. Build paired labels/data/colors from `byBandWithUpcoming` (earned in band base color, upcoming in the same hue at lower alpha):

```js
      if (this.$refs.earningsByBandChart && this.byBandWithUpcoming.length > 0) {
        const ctx = this.$refs.earningsByBandChart.getContext('2d')
        const base = [
          [34, 197, 94], [59, 130, 246], [168, 85, 247],
          [249, 115, 22], [236, 72, 153], [90, 200, 250],
        ]
        const labels = [], data = [], bg = [], border = []
        this.byBandWithUpcoming.forEach((band, i) => {
          const [r, g, b] = base[i % base.length]
          if (band.earned > 0) {
            labels.push(band.bandName)
            data.push(band.earned)
            bg.push(`rgba(${r}, ${g}, ${b}, 0.6)`)
            border.push(`rgba(${r}, ${g}, ${b}, 1)`)
          }
          if (band.upcoming > 0) {
            labels.push(`${band.bandName} (upcoming)`)
            data.push(band.upcoming)
            bg.push(`rgba(${r}, ${g}, ${b}, 0.25)`)
            border.push(`rgba(${r}, ${g}, ${b}, 0.6)`)
          }
        })
        this.bandChart = new Chart(ctx, {
          type: 'doughnut',
          data: { labels, datasets: [{ data, backgroundColor: bg, borderColor: border, borderWidth: 1 }] },
          options: {
            responsive: true,
            maintainAspectRatio: true,
            aspectRatio: 1.5,
            plugins: {
              legend: { position: 'bottom' },
              tooltip: {
                callbacks: {
                  label: (c) => c.label + ': $' + parseFloat(c.parsed).toLocaleString(),
                },
              },
            },
          },
        })
      }
```

- [ ] **Step 5: Compact inline Bookings-by-Year header + drop standalone total**

In the bookings breakdown template (the year header around lines 200-235), replace the subtitle span and remove the right-aligned `year_total` total. The header subtitle becomes:

```html
                    <span class="text-sm text-gray-500 dark:text-gray-400">
                      {{ yearData.booking_count + yearData.upcoming_booking_count }}
                      {{ (yearData.booking_count + yearData.upcoming_booking_count) === 1 ? 'booking' : 'bookings' }}
                      · ${{ formatNumber(yearData.year_total) }} earned<template v-if="yearData.upcoming_booking_count > 0"> · ${{ formatNumber(yearData.upcoming_total) }} upcoming</template>
                    </span>
```

Delete the sibling `<div class="text-right">…{{ formatNumber(yearData.year_total) }}…</div>` block (and its `upcoming_total` sub-line if present) that rendered the standalone total on the right. Keep the expand chevron and the expandable `DataTable` of booking rows unchanged.

- [ ] **Step 6: Build**

Run: `cd /home/eddie/github/TTS && npm run build`
Expected: `✓ built` with no errors.

- [ ] **Step 7: Commit, push, PR against `master`, request Copilot**

```bash
cd /home/eddie/github/TTS
git add resources/js/Pages/UserStats/Index.vue
git commit -m "Present upcoming earnings in /stats charts and bookings card

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push -u origin feat/stats-upcoming-presentation
gh pr create --repo eddimull/TTS --base master --head feat/stats-upcoming-presentation \
  --title "Present upcoming earnings in /stats charts and bookings card" \
  --body "Web mirror of the mobile change: stacked Earnings-by-Year (earned green + upcoming gray), paired lighter-hue upcoming donut slices, compact inline Bookings-by-Year line with the standalone total dropped. Derived client-side from bookings_by_year — no backend change."
gh api repos/eddimull/TTS/pulls/<N>/requested_reviewers -X POST -f "reviewers[]=copilot-pull-request-reviewer[bot]"
```

Note: if `staging` already carries the earlier earned-vs-upcoming commit and `master` does not, confirm the diff is only this change before opening the PR (`git diff origin/master...feat/stats-upcoming-presentation --stat`). If `staging`→`master` is the intended promotion path used earlier, base the PR on `staging` instead and confirm with the user.

---

## Self-Review notes

- **Spec coverage:** Earnings-by-Year stacked (Task 2/web Step 3) ✓; Earnings-by-Band paired hue (Task 3/web Step 4) ✓; Bookings-by-Year inline + drop total (Task 4/web Step 5) ✓; no backend change (all tasks derive from `bookings_by_year`) ✓; future-only years + upcoming-only bands (Task 1 tests assert both) ✓.
- **Type consistency:** `YearBreakdown`/`BandBreakdown` defined in Task 1 and consumed in Tasks 2–3; `byYearWithUpcoming`/`byBandWithUpcoming` defined in web Step 2 and consumed in Steps 3–4. `BookingRow.bandId` dependency flagged in Task 1 Step 3.
- **Open risk:** mobile `BookingRow` may lack `bandId` today — Task 1 Step 3 adds it if missing (web payload already sends `band_id` per row).
