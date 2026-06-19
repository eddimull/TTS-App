import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/stats/data/stats_repository.dart';

class _FakeDio extends Fake implements Dio {
  _FakeDio(this._responses);

  final Map<String, dynamic> _responses;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    if (!_responses.containsKey(path)) {
      throw DioException(requestOptions: RequestOptions(path: path));
    }
    return Response<T>(
      data: _responses[path] as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  const path = '/api/mobile/me/stats';

  Map<String, dynamic> payload() => {
        path: {
          'stats': {
            'payments': {
              'total_earnings': '1532.50',
              'booking_count': 3,
              'by_year': [
                {'year': 2024, 'total': '1000.00'},
                {'year': 2023, 'total': '532.50'},
              ],
              'by_band': [
                {'band_id': 1, 'band_name': 'The Rockers', 'total': '1532.50', 'booking_count': 3},
              ],
              'bookings_by_year': [
                {
                  'year': 2024,
                  'year_total': '1000.00',
                  'booking_count': 1,
                  'bookings': [
                    {
                      'id': 5,
                      'booking_name': 'Summer Wedding',
                      'band_name': 'The Rockers',
                      'band_id': 1,
                      'venue_name': 'Grand Ballroom',
                      'venue_address': '123 Main St',
                      'date': '2024-06-15',
                      'status': 'confirmed',
                      'total_price': '2000.00',
                      'user_share': '1000.00',
                    },
                  ],
                },
              ],
            },
            'travel': {
              'total_miles': 1250.5,
              'total_minutes': 600,
              'total_hours': 10.0,
              'event_count': 3,
              'by_year': [
                {
                  'year': 2024,
                  'total_miles': 1000.0,
                  'total_hours': 8.0,
                  'event_count': 2,
                  'events': [
                    {
                      'date': '2024-06-15',
                      'title': 'Summer Wedding',
                      'band_name': 'The Rockers',
                      'venue_name': 'Grand Ballroom',
                      'venue_address': '123 Main St',
                      'miles': 45.2,
                      'hours': 0.9,
                    },
                    {
                      'date': '2024-07-01',
                      'title': 'No Distance Gig',
                      'band_name': 'The Rockers',
                      'venue_name': 'TBD',
                      'venue_address': null,
                      'miles': null,
                      'hours': null,
                    },
                  ],
                },
              ],
            },
            'locations': [
              {
                'title': 'Summer Wedding',
                'venue_name': 'Grand Ballroom',
                'venue_address': '123 Main St',
                'date': '2024-06-15',
                'full_address': 'Grand Ballroom, 123 Main St',
                'lat': 29.95,
                'lng': -90.07,
              },
              {
                'title': 'Uncached Gig',
                'venue_name': 'Mystery Hall',
                'venue_address': '999 Nowhere Rd',
                'date': '2024-07-01',
                'full_address': 'Mystery Hall, 999 Nowhere Rd',
                'lat': null,
                'lng': null,
              },
            ],
          },
        },
      };

  group('StatsRepository', () {
    test('parses the full stats payload', () async {
      final repo = StatsRepository(_FakeDio(payload()));
      final stats = await repo.getStats();

      expect(stats.payments.totalEarnings, 1532.50);
      expect(stats.payments.bookingCount, 3);
      expect(stats.payments.byYear.length, 2);
      expect(stats.payments.byBand.single.bandName, 'The Rockers');
      expect(stats.payments.bookingsByYear.single.bookings.single.userShare, 1000.00);

      expect(stats.travel.totalMiles, 1250.5);
      expect(stats.travel.eventCount, 3);
      expect(stats.travel.byYear.single.events.length, 2);

      expect(stats.locations.length, 2);
    });

    test('handles null miles/hours and missing coordinates', () async {
      final repo = StatsRepository(_FakeDio(payload()));
      final stats = await repo.getStats();

      final noDistance = stats.travel.byYear.single.events
          .firstWhere((e) => e.title == 'No Distance Gig');
      expect(noDistance.miles, isNull);
      expect(noDistance.hours, isNull);

      final cached = stats.locations.firstWhere((l) => l.title == 'Summer Wedding');
      final uncached = stats.locations.firstWhere((l) => l.title == 'Uncached Gig');
      expect(cached.hasCoordinates, isTrue);
      expect(uncached.hasCoordinates, isFalse);
    });

    test('isEmpty is true when no bookings and no events', () async {
      final empty = {
        path: {
          'stats': {
            'payments': {'total_earnings': '0.00', 'booking_count': 0, 'by_year': [], 'by_band': [], 'bookings_by_year': []},
            'travel': {'total_miles': 0, 'total_minutes': 0, 'total_hours': 0, 'event_count': 0, 'by_year': []},
            'locations': [],
          },
        },
      };
      final repo = StatsRepository(_FakeDio(empty));
      final stats = await repo.getStats();
      expect(stats.isEmpty, isTrue);
    });

    test('parses an upcoming booking with no gig date (null year/date)', () async {
      // Bookings with no events yet are reported as upcoming and grouped under a
      // null year with a null date — must parse without crashing.
      final withUndated = {
        path: {
          'stats': {
            'payments': {
              'total_earnings': '0.00',
              'booking_count': 0,
              'upcoming_earnings': '1500.00',
              'upcoming_booking_count': 1,
              'by_year': [],
              'by_band': [],
              'bookings_by_year': [
                {
                  'year': null,
                  'year_total': '0.00',
                  'booking_count': 0,
                  'upcoming_total': '1500.00',
                  'upcoming_booking_count': 1,
                  'bookings': [
                    {
                      'id': 1,
                      'booking_name': 'Future Gig',
                      'band_name': 'The Rockers',
                      'venue_name': 'TBD',
                      'venue_address': null,
                      'date': null,
                      'status': 'confirmed',
                      'is_upcoming': true,
                      'total_price': '3000.00',
                      'user_share': '1500.00',
                    },
                  ],
                },
              ],
            },
            'travel': {'total_miles': 0, 'total_minutes': 0, 'total_hours': 0, 'event_count': 0, 'by_year': []},
            'locations': [],
          },
        },
      };
      final repo = StatsRepository(_FakeDio(withUndated));
      final stats = await repo.getStats();

      final group = stats.payments.bookingsByYear.single;
      expect(group.year, isNull);
      expect(group.upcomingTotal, 1500.00);
      final row = group.bookings.single;
      expect(row.isUpcoming, isTrue);
      expect(row.date, ''); // null date decodes to empty string -> rendered as "TBD"
      expect(stats.payments.upcomingEarnings, 1500.00);
    });
  });
}
