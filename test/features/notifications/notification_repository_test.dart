import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/notification_repository.dart';

import '../../helpers/test_harness.dart';

void main() {
  late List<RequestOptions> seen;

  Dio dio(Object Function(RequestOptions) handler) {
    seen = [];
    return Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((req) async {
        seen.add(req);
        final body = handler(req);
        return json(body is int ? body : 200, body is int ? const {} : body);
      });
  }

  test('list() parses the page and forwards cursor + limit', () async {
    final repo = NotificationRepository(dio((req) => {
          'notifications': [
            {'id': 'n1', 'kind': 'event', 'text': 't', 'deeplink': '/events/k', 'read_at': null, 'seen_at': null, 'created_at': '2026-10-05T09:00:00+00:00'},
          ],
          'next_cursor': '2026-10-05 09:00:00|n1',
          'unseen_count': 4,
        }));

    final page = await repo.list(cursor: 'abc|def', limit: 10);

    expect(seen.single.path, '/api/mobile/notifications');
    expect(seen.single.queryParameters, {'cursor': 'abc|def', 'limit': 10});
    expect(page.items.single.id, 'n1');
    expect(page.nextCursor, '2026-10-05 09:00:00|n1');
    expect(page.unseenCount, 4);
  });

  test('list() omits cursor when null', () async {
    final repo = NotificationRepository(dio((_) => {'notifications': [], 'next_cursor': null, 'unseen_count': 0}));
    await repo.list();
    expect(seen.single.queryParameters, {'limit': 30});
  });

  test('unseenCount() reads count', () async {
    final repo = NotificationRepository(dio((_) => {'count': 7}));
    expect(await repo.unseenCount(), 7);
    expect(seen.single.path, '/api/mobile/notifications/unseen-count');
  });

  test('markRead / markAllRead / markSeen hit the right endpoints', () async {
    final repo = NotificationRepository(dio((_) => 204));
    await repo.markRead('abc');
    await repo.markAllRead();
    await repo.markSeen();
    expect(seen.map((r) => '${r.method} ${r.path}'), [
      'POST /api/mobile/notifications/abc/read',
      'POST /api/mobile/notifications/read-all',
      'POST /api/mobile/notifications/seen',
    ]);
  });
}
