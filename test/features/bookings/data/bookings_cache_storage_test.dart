import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_cache_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<BookingsCacheStorage> build() async {
    final prefs = await SharedPreferences.getInstance();
    return BookingsCacheStorage(prefs);
  }

  test('read returns null when nothing stored', () async {
    final storage = await build();
    expect(storage.read(), isNull);
  });

  test('write then read round-trips the cache', () async {
    final storage = await build();
    final cache = BookingsWindowCache(
      from: DateTime(2026, 2, 1),
      to: DateTime(2027, 2, 28),
      cachedAt: DateTime(2026, 5, 15, 9),
      rawBookings: [
        {'id': 1, 'name': 'Gala', 'date': '2026-06-01'},
      ],
    );
    storage.write(cache);

    final read = storage.read()!;
    expect(read.from, DateTime(2026, 2, 1));
    expect(read.to, DateTime(2027, 2, 28));
    expect(read.cachedAt, DateTime(2026, 5, 15, 9));
    expect(read.rawBookings, hasLength(1));
    expect(read.rawBookings.first['id'], 1);
    expect(read.rawBookings.first['name'], 'Gala');
  });

  test('read returns null and clears key on malformed JSON', () async {
    SharedPreferences.setMockInitialValues({
      'bookings_window_cache': 'not json{{',
    });
    final storage = await build();
    expect(storage.read(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bookings_window_cache'), isNull);
  });

  test('clear removes the cache', () async {
    final storage = await build();
    storage.write(BookingsWindowCache(
      from: DateTime(2026, 2, 1),
      to: DateTime(2027, 2, 28),
      cachedAt: DateTime(2026, 5, 15),
      rawBookings: const [],
    ));
    storage.clear();
    expect(storage.read(), isNull);
  });
}
