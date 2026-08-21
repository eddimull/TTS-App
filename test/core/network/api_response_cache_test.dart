import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/network/api_response_cache.dart';

RequestOptions _get(String path, {Map<String, dynamic>? query}) =>
    RequestOptions(
      path: path,
      method: 'GET',
      baseUrl: 'https://example.test',
      queryParameters: query ?? const {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('round-trips a decoded JSON body', () {
    final cache = ApiResponseCache(prefs);
    final key = ApiResponseCache.keyFor(_get('/api/mobile/dashboard'));

    cache.write(key, statusCode: 200, body: {
      'events': [
        {'id': 1, 'name': 'Gig'},
      ],
    });

    final cached = cache.read(key);
    expect(cached, isNotNull);
    expect(cached!.statusCode, 200);
    final body = cached.body as Map<String, dynamic>;
    expect((body['events'] as List).single, {'id': 1, 'name': 'Gig'});
  });

  test('keys separate bands, paths and query strings', () {
    final cache = ApiResponseCache(prefs);

    final bandOne = ApiResponseCache.keyFor(_get('/x'), bandId: '1');
    final bandTwo = ApiResponseCache.keyFor(_get('/x'), bandId: '2');
    final otherPath = ApiResponseCache.keyFor(_get('/y'), bandId: '1');
    final withQuery = ApiResponseCache.keyFor(
      _get('/x', query: {'to': '2026-01-01'}),
      bandId: '1',
    );

    expect({bandOne, bandTwo, otherPath, withQuery}, hasLength(4));

    cache.write(bandOne, statusCode: 200, body: {'band': 1});
    expect(cache.read(bandTwo), isNull,
        reason: 'a band switch must never be served the other band’s data');
  });

  test('evicts the least recently written entry past the cap', () {
    final cache = ApiResponseCache(prefs, maxEntries: 2);

    cache.write('a', statusCode: 200, body: {'n': 1});
    cache.write('b', statusCode: 200, body: {'n': 2});
    cache.write('c', statusCode: 200, body: {'n': 3});

    expect(cache.entryCount, 2);
    expect(cache.read('a'), isNull);
    expect(cache.read('b'), isNotNull);
    expect(cache.read('c'), isNotNull);
  });

  test('skips bodies over the per-entry size cap', () {
    final cache = ApiResponseCache(prefs, maxEntryBytes: 32);

    cache.write('big', statusCode: 200, body: {'blob': 'x' * 1000});

    expect(cache.read('big'), isNull);
    expect(cache.entryCount, 0);
  });

  test('drops a malformed entry instead of failing every read', () {
    final cache = ApiResponseCache(prefs);
    cache.write('k', statusCode: 200, body: {'n': 1});
    prefs.setString('api_cache:k', 'not json');

    expect(cache.read('k'), isNull);
    expect(cache.entryCount, 0);
  });

  test('clear() empties the store', () {
    final cache = ApiResponseCache(prefs);
    cache.write('a', statusCode: 200, body: {'n': 1});
    cache.write('b', statusCode: 200, body: {'n': 2});

    cache.clear();

    expect(cache.entryCount, 0);
    expect(cache.read('a'), isNull);
    expect(cache.read('b'), isNull);
  });
}
