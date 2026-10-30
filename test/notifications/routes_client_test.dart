import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/geocoding.dart';
import 'package:tts_bandmate/features/notifications/data/routes_client.dart';

void main() {
  group('parseRoutesDuration', () {
    test('parses seconds string like "2705s"', () {
      final d = parseRoutesDuration({
        'routes': [
          {'duration': '2705s'}
        ]
      });
      expect(d, const Duration(seconds: 2705));
    });

    test('parses integer seconds', () {
      final d = parseRoutesDuration({
        'routes': [
          {'duration': 600}
        ]
      });
      expect(d, const Duration(seconds: 600));
    });

    test('null when no routes', () {
      expect(parseRoutesDuration({'routes': <dynamic>[]}), isNull);
      expect(parseRoutesDuration({}), isNull);
    });

    test('null when duration missing/garbage', () {
      expect(
          parseRoutesDuration({
            'routes': [{}]
          }),
          isNull);
      expect(
          parseRoutesDuration({
            'routes': [
              {'duration': 'abc'}
            ]
          }),
          isNull);
    });
  });

  group('buildRoutesRequest', () {
    test('addresses and coordinates, live traffic by default', () {
      final body = buildRoutesRequest(
        origin: const RoutePlace.point(GeoPoint(29.9, -90.1)),
        destination: const RoutePlace.address('1911 Magazine St'),
      );
      expect(body['origin'], {
        'location': {
          'latLng': {'latitude': 29.9, 'longitude': -90.1}
        }
      });
      expect(body['destination'], {'address': '1911 Magazine St'});
      expect(body['routingPreference'], 'TRAFFIC_AWARE');
      expect(body.containsKey('departureTime'), isFalse);
      expect(body.containsKey('intermediates'), isFalse);
    });

    test('departure time is sent in UTC and stops in order', () {
      final body = buildRoutesRequest(
        origin: const RoutePlace.address('Home'),
        destination: const RoutePlace.address('Venue'),
        intermediates: const [RoutePlace.address('Band')],
        departureTime: DateTime.utc(2026, 11, 7, 19, 40),
      );
      expect(body['departureTime'], '2026-11-07T19:40:00.000Z');
      expect(body['intermediates'], [
        {'address': 'Band'}
      ]);
    });
  });
}
