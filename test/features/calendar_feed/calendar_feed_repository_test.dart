import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/calendar_feed/data/calendar_feed_repository.dart';

// Minimal Dio fake — returns canned GET/POST data keyed by path.
class _FakeDio extends Fake implements Dio {
  _FakeDio(this._responses);

  final Map<String, dynamic> _responses;
  bool postCalled = false;
  String? lastPostPath;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    return Response<T>(
      data: _responses[path] as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) async {
    postCalled = true;
    lastPostPath = path;
    return Response<T>(
      data: _responses[path] as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  const feedPath = '/api/mobile/me/calendar-feed';
  const resetPath = '/api/mobile/me/calendar-feed/reset';

  Map<String, dynamic> payload() => {
        feedPath: {
          'url': 'https://tts.band/calendar/abc.ics',
          'webcal_url': 'webcal://tts.band/calendar/abc.ics',
          'google_subscribe_url':
              'https://calendar.google.com/calendar/r?cid=webcal',
        },
        resetPath: {
          'url': 'https://tts.band/calendar/xyz.ics',
          'webcal_url': 'webcal://tts.band/calendar/xyz.ics',
          'google_subscribe_url':
              'https://calendar.google.com/calendar/r?cid=webcal-new',
        },
      };

  group('CalendarFeedRepository', () {
    test('getCalendarFeed parses the subscription URLs', () async {
      final repo = CalendarFeedRepository(_FakeDio(payload()));
      final feed = await repo.getCalendarFeed();

      expect(feed.url, 'https://tts.band/calendar/abc.ics');
      expect(feed.webcalUrl, 'webcal://tts.band/calendar/abc.ics');
      expect(feed.googleSubscribeUrl,
          'https://calendar.google.com/calendar/r?cid=webcal');
    });

    test('resetCalendarFeed POSTs and returns rotated URLs', () async {
      final dio = _FakeDio(payload());
      final repo = CalendarFeedRepository(dio);

      final feed = await repo.resetCalendarFeed();

      expect(dio.postCalled, isTrue);
      expect(dio.lastPostPath, resetPath);
      expect(feed.url, 'https://tts.band/calendar/xyz.ics');
    });
  });
}
