import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RouteStorage', () {
    Future<RouteStorage> build() async {
      final prefs = await SharedPreferences.getInstance();
      return RouteStorage(prefs);
    }

    test('readLastRoute returns null when nothing stored', () async {
      final storage = await build();
      expect(storage.readLastRoute(), isNull);
    });

    test('readLastRouteTimestamp returns null when nothing stored', () async {
      final storage = await build();
      expect(storage.readLastRouteTimestamp(), isNull);
    });

    test('writeLastRoute persists path and timestamp', () async {
      final storage = await build();
      storage.writeLastRoute('/bookings/42');
      expect(storage.readLastRoute(), '/bookings/42');
      expect(storage.readLastRouteTimestamp(), isNotNull);
    });

    test('writeLastRoute overwrites previous value', () async {
      final storage = await build();
      storage.writeLastRoute('/dashboard');
      storage.writeLastRoute('/library/7');
      expect(storage.readLastRoute(), '/library/7');
    });

    test('clearLastRoute removes path and timestamp', () async {
      final storage = await build();
      storage.writeLastRoute('/bookings/42');
      storage.clearLastRoute();
      expect(storage.readLastRoute(), isNull);
      expect(storage.readLastRouteTimestamp(), isNull);
    });

    test('timestamp is within a few seconds of now', () async {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final storage = await build();
      storage.writeLastRoute('/search');
      final ts = storage.readLastRouteTimestamp()!;
      final after = DateTime.now().add(const Duration(seconds: 1));
      expect(ts.isAfter(before), isTrue);
      expect(ts.isBefore(after), isTrue);
    });
  });
}
