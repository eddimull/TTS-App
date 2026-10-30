import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/network/geocoding.dart';
import 'package:tts_bandmate/features/account/data/models/account_profile.dart';
import 'package:tts_bandmate/features/account/providers/account_provider.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/events/data/leave_plan.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/features/events/providers/leave_plan_provider.dart';
import 'package:tts_bandmate/features/notifications/data/routes_client.dart';
import 'package:tts_bandmate/features/notifications/providers/notifications_provider.dart';
import 'package:tts_bandmate/features/notifications/services/location_service.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

const _key = 'evt';

EventDetail _event({List<Map<String, dynamic>> lodgings = const []}) =>
    EventDetail.fromJson({
      'id': 1,
      'key': _key,
      'title': 'Gig',
      'date': '2026-11-07',
      'time': '16:30',
      'venue_name': 'Il Mercato',
      'venue_address': '1911 Magazine St, New Orleans',
      'can_write': true,
      'members': <dynamic>[],
      'lodgings': lodgings,
      'timeline': [
        {'title': 'Load in', 'time': '2026-11-07 14:30'},
      ],
    });

class _FakeDetail extends EventDetailNotifier {
  _FakeDetail(this._value) : super(_key);
  final EventDetail _value;
  @override
  Future<EventDetail> build() async => _value;
}

class _FakeBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.bandAddress);
  final String? bandAddress;
  @override
  Future<AuthState> build() async => AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'E', email: 'e@x.com'),
        bands: [
          BandSummary(
            id: 1,
            name: 'Band',
            isOwner: true,
            address: bandAddress,
            city: 'Metairie',
          ),
        ],
      );
}

class _FakeAccount extends AccountNotifier {
  _FakeAccount(this.address1);
  final String? address1;
  @override
  Future<AccountState> build() async => AccountState(
        profile: AccountProfile(
          id: 1,
          name: 'E',
          email: 'e@x.com',
          address1: address1,
          city: 'New Orleans',
          stateId: '19',
          zip: '70115',
          emailNotifications: true,
        ),
        states: const [
          StateOption(id: '19', name: 'Louisiana', countryId: '1'),
        ],
        countries: const [],
      );
}

class _Call {
  _Call(this.origin, this.destination, this.via, this.departure);
  final RoutePlace origin;
  final RoutePlace destination;
  final List<RoutePlace> via;
  final DateTime? departure;
}

class _FakeRoutes extends RoutesClient {
  final calls = <_Call>[];
  Duration? result = const Duration(minutes: 33);

  @override
  Future<Duration?> routeDuration({
    required RoutePlace origin,
    required RoutePlace destination,
    List<RoutePlace> intermediates = const [],
    DateTime? departureTime,
  }) async {
    calls.add(_Call(origin, destination, intermediates, departureTime));
    return result;
  }
}

class _FakeLocation implements LocationService {
  _FakeLocation(this.point);
  final GeoPoint? point;
  @override
  Future<LocationGrant> ensurePermission() async =>
      point == null ? LocationGrant.denied : LocationGrant.whileInUse;
  @override
  Future<GeoPoint?> current() async => point;
  @override
  double distanceMeters(GeoPoint a, GeoPoint b) => 0;
}

Future<(ProviderContainer, _FakeRoutes)> _container({
  EventDetail? event,
  String? home = '742 Evergreen Ter',
  String? band = '1 Band Way',
  GeoPoint? here,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final routes = _FakeRoutes();
  final c = ProviderContainer(overrides: [
    eventDetailProvider(_key)
        .overrideWith(() => _FakeDetail(event ?? _event())),
    selectedBandProvider.overrideWith(_FakeBand.new),
    authProvider.overrideWith(() => _FakeAuth(band)),
    accountProvider.overrideWith(() => _FakeAccount(home)),
    routesClientProvider.overrideWithValue(routes),
    locationServiceProvider.overrideWithValue(_FakeLocation(here)),
    leaveTimesEnabledProvider.overrideWithValue(true),
  ]);
  addTearDown(c.dispose);
  await c.read(authProvider.future);
  await c.read(selectedBandProvider.future);
  return (c, routes);
}

Future<LeavePlan?> _read(ProviderContainer c) {
  final sub = c.listen(leavePlanProvider(_key), (_, __) {});
  addTearDown(sub.close);
  return c.read(leavePlanProvider(_key).future);
}

final _before = DateTime(2026, 11, 1, 9);

void main() {
  test('defaults to home with typical traffic at about leave time', () async {
    await withClock(Clock.fixed(_before), () async {
      final (c, routes) = await _container();
      final plan = (await _read(c))!;

      expect(plan.start, LeaveStart.home);
      expect(plan.live, isFalse);
      expect(plan.drive, const Duration(minutes: 35));
      expect(plan.leaveAt, DateTime(2026, 11, 7, 13, 45));
      final call = routes.calls.single;
      expect(call.origin.address,
          '742 Evergreen Ter, New Orleans, Louisiana, 70115');
      expect(call.destination.address, '1911 Magazine St, New Orleans');
      expect(call.via, isEmpty);
      // 2:30 load-in − 10 min early − 40 min guess.
      expect(call.departure, DateTime(2026, 11, 7, 13, 40));
    });
  });

  test('a second open the same day uses the cached drive', () async {
    await withClock(Clock.fixed(_before), () async {
      final (c, routes) = await _container();
      await _read(c);
      c.invalidate(leavePlanProvider(_key));
      final plan = (await _read(c))!;
      expect(routes.calls, hasLength(1));
      expect(plan.drive, const Duration(minutes: 35));
    });
  });

  test('gear pickup adds the band as a stop on the way from home', () async {
    await withClock(Clock.fixed(_before), () async {
      final (c, routes) =
          await _container(prefs: {leaveStartKey: 'gearPickup'});
      final plan = (await _read(c))!;
      expect(plan.start, LeaveStart.gearPickup);
      final call = routes.calls.single;
      expect(call.origin.address, startsWith('742 Evergreen Ter'));
      expect(call.via.single.address, '1 Band Way, Metairie');
    });
  });

  test('gear pickup with no home address starts at the band', () async {
    await withClock(Clock.fixed(_before), () async {
      final (c, routes) =
          await _container(home: null, prefs: {leaveStartKey: 'gearPickup'});
      await _read(c);
      final call = routes.calls.single;
      expect(call.origin.address, '1 Band Way, Metairie');
      expect(call.via, isEmpty);
    });
  });

  test('hotel is offered only with lodging and starts there', () async {
    await withClock(Clock.fixed(_before), () async {
      final (c, routes) = await _container(
        event: _event(lodgings: [
          {
            'id': 3,
            'name': 'Hotel Saint Vincent',
            'address': '1507 Magazine St',
            'check_in_at': '',
            'check_out_at': '',
          }
        ]),
        prefs: {leaveStartKey: 'hotel'},
      );
      final plan = (await _read(c))!;
      expect(plan.available, contains(LeaveStart.hotel));
      expect(plan.startLabel(LeaveStart.hotel), 'Hotel Saint Vincent');
      expect(routes.calls.single.origin.address, '1507 Magazine St');
    });
  });

  test('no home and nothing picked asks for a start point', () async {
    await withClock(Clock.fixed(_before), () async {
      final (c, routes) = await _container(home: null);
      final plan = (await _read(c))!;
      expect(plan.start, isNull);
      expect(plan.available.contains(LeaveStart.home), isFalse);
      expect(routes.calls, isEmpty);
    });
  });

  test('gig day uses the phone location and live traffic', () async {
    await withClock(Clock.fixed(DateTime(2026, 11, 7, 12)), () async {
      final (c, routes) = await _container(here: const GeoPoint(29.9, -90.1));
      final plan = (await _read(c))!;
      expect(plan.live, isTrue);
      expect(plan.fromHere, isTrue);
      final call = routes.calls.single;
      expect(call.origin.point, const GeoPoint(29.9, -90.1));
      expect(call.departure, isNull);
    });
  });

  test('gig day without location falls back to home, live traffic', () async {
    await withClock(Clock.fixed(DateTime(2026, 11, 7, 12)), () async {
      final (c, routes) = await _container();
      final plan = (await _read(c))!;
      expect(plan.live, isTrue);
      expect(plan.fromHere, isFalse);
      final call = routes.calls.single;
      expect(call.origin.address, startsWith('742 Evergreen Ter'));
      expect(call.departure, isNull);
    });
  });

  test('null for a past event', () async {
    await withClock(Clock.fixed(DateTime(2026, 11, 9)), () async {
      final (c, routes) = await _container();
      expect(await _read(c), isNull);
      expect(routes.calls, isEmpty);
    });
  });

  test('settings persist on the phone', () async {
    final (c, _) = await _container();
    await c.read(leaveSettingsProvider.future);
    await c.read(leaveSettingsProvider.notifier).setStart(LeaveStart.here);
    await c
        .read(leaveSettingsProvider.notifier)
        .setEarlyBy(const Duration(minutes: 20));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(leaveStartKey), 'here');
    expect(prefs.getInt(leaveEarlyByKey), 20);
    final s = c.read(leaveSettingsProvider).value!;
    expect(s.start, LeaveStart.here);
    expect(s.earlyBy, const Duration(minutes: 20));
  });

  group('LeaveDriveCache', () {
    test('misses when the route changed and drops earlier days', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = LeaveDriveCache(prefs);
      final day1 = DateTime(2026, 11, 1);
      await cache.put(
          'e', LeaveStart.home, day1, 'a>b', const Duration(minutes: 30));
      expect(cache.get('e', LeaveStart.home, day1, 'a>b'),
          const Duration(minutes: 30));
      expect(cache.get('e', LeaveStart.home, day1, 'c>b'), isNull);

      final day2 = DateTime(2026, 11, 2);
      await cache.put(
          'e', LeaveStart.home, day2, 'a>b', const Duration(minutes: 31));
      expect(cache.get('e', LeaveStart.home, day1, 'a>b'), isNull);
      expect(prefs.getKeys().where((k) => k.startsWith('leave_drive:')),
          hasLength(1));
    });
  });
}
