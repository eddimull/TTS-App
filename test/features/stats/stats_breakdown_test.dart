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

    test('keeps rows with a missing band_id (sentinel 0) so no money is dropped', () {
      // The real API always sends band_id; if one were ever missing (decoded as
      // 0), the row's earnings must still appear — bucketed under its own name —
      // rather than silently vanishing from the chart.
      final p = _payments([
        _row(bandId: 1, bandName: 'Rockers', date: '2025-01-01', upcoming: false, share: '500.00'),
        _row(bandId: 0, bandName: 'Orphan', date: '2025-01-01', upcoming: true, share: '999.00'),
      ]);

      final bands = p.bandBreakdown;
      expect(bands.length, 2);
      final orphan = bands.firstWhere((b) => b.bandId == 0);
      expect(orphan.bandName, 'Orphan');
      expect(orphan.upcoming, 999.0); // upcoming money preserved, not dropped
    });

    test('keeps the first non-empty band name even if a later row has none', () {
      final p = _payments([
        _row(bandId: 1, bandName: 'Rockers', date: '2025-01-01', upcoming: false, share: '500.00'),
        _row(bandId: 1, bandName: '', date: '2026-09-01', upcoming: true, share: '200.00'),
      ]);

      final band = p.bandBreakdown.single;
      expect(band.bandName, 'Rockers'); // not overwritten to 'Unknown'
      expect(band.earned, 500.0);
      expect(band.upcoming, 200.0);
    });
  });

  group('value type totals', () {
    test('sums earned and upcoming within a single year and band', () {
      final p = _payments([
        _row(bandId: 1, bandName: 'A', date: '2025-01-01', upcoming: false, share: '100.00'),
        _row(bandId: 1, bandName: 'A', date: '2025-06-01', upcoming: false, share: '50.00'),
        _row(bandId: 1, bandName: 'A', date: '2026-01-01', upcoming: true, share: '25.00'),
      ]);

      final y2025 = p.yearBreakdown.firstWhere((y) => y.year == 2025);
      expect(y2025.earned, 150.0); // two past gigs accumulate
      expect(y2025.total, 150.0);

      final band = p.bandBreakdown.single;
      expect(band.earned, 150.0);
      expect(band.upcoming, 25.0);
      expect(band.total, 175.0);
    });
  });
}
