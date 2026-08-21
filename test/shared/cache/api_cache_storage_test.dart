import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiCacheStorage storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
  });

  test('read returns null when nothing cached', () {
    expect(storage.read('7:dashboard'), isNull);
  });

  test('write/read round-trips payload and stamps savedAt', () {
    final before = DateTime.now();
    storage.write('7:dashboard', {'events': [{'id': 1}], 'upcoming_charts': []});
    final entry = storage.read('7:dashboard');
    expect(entry, isNotNull);
    expect(entry!.payload['events'], [{'id': 1}]);
    expect(entry.savedAt.isBefore(before.subtract(const Duration(seconds: 5))), isFalse);
  });

  test('malformed blob is cleared and returns null', () async {
    SharedPreferences.setMockInitialValues({'api_cache_v1:7:dashboard': 'not json'});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    expect(storage.read('7:dashboard'), isNull);
    expect(storage.read('7:dashboard'), isNull); // stays null, no throw
  });

  test('remove drops one entry, clearAll drops every api_cache entry only', () async {
    SharedPreferences.setMockInitialValues({'unrelated_key': 'keep'});
    final prefs = await SharedPreferences.getInstance();
    storage = ApiCacheStorage(prefs);
    storage.write('7:dashboard', {'a': 1});
    storage.write('7:event:abc', {'b': 2});
    storage.write('9:dashboard', {'c': 3});

    storage.remove('7:event:abc');
    expect(storage.read('7:event:abc'), isNull);
    expect(storage.read('7:dashboard'), isNotNull);

    storage.clearAll();
    expect(storage.read('7:dashboard'), isNull);
    expect(storage.read('9:dashboard'), isNull);
    expect(prefs.getString('unrelated_key'), 'keep');
  });
}
