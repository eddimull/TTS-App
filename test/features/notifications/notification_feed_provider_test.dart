import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/notification_repository.dart';
import 'package:tts_bandmate/features/notifications/providers/notification_feed_provider.dart';

import '../../helpers/test_harness.dart';

Map<String, dynamic> row(String id, {bool read = false}) => {
      'id': id, 'kind': 'event', 'text': 'n $id', 'deeplink': '/events/$id',
      'read_at': read ? '2026-10-05T09:00:00+00:00' : null, 'seen_at': null,
      'created_at': '2026-10-05T09:00:00+00:00',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<RequestOptions> requests;

  ProviderContainer container(Object Function(RequestOptions) handler) {
    requests = [];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((req) async {
        requests.add(req);
        final body = handler(req);
        return json(body is int ? body : 200, body is int ? const {} : body);
      });
    final c = ProviderContainer(overrides: [
      notificationRepositoryProvider.overrideWithValue(NotificationRepository(dio)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('loads the first page and exposes hasMore', () async {
    final c = container((req) => req.path.endsWith('unseen-count')
        ? {'count': 2}
        : {'notifications': [row('a'), row('b')], 'next_cursor': 'c1', 'unseen_count': 2});

    final s = await c.read(notificationFeedProvider.future);
    expect(s.items.map((i) => i.id), ['a', 'b']);
    expect(s.hasMore, isTrue);
    expect(await c.read(unseenNotificationsCountProvider.future), 2);
  });

  test('loadMore appends the next page using the cursor and stops at the end', () async {
    var call = 0;
    final c = container((req) {
      if (req.path.endsWith('unseen-count')) return {'count': 0};
      call++;
      return call == 1
          ? {'notifications': [row('a')], 'next_cursor': 'c1', 'unseen_count': 0}
          : {'notifications': [row('b')], 'next_cursor': null, 'unseen_count': 0};
    });
    await c.read(notificationFeedProvider.future);
    await c.read(notificationFeedProvider.notifier).loadMore();

    final s = c.read(notificationFeedProvider).value!;
    expect(s.items.map((i) => i.id), ['a', 'b']);
    expect(s.hasMore, isFalse);
    expect(requests.where((r) => r.path == '/api/mobile/notifications').last.queryParameters['cursor'], 'c1');

    await c.read(notificationFeedProvider.notifier).loadMore(); // no-op at the end
    expect(requests.where((r) => r.path == '/api/mobile/notifications').length, 2);
  });

  test('markRead is optimistic and posts; markAllRead clears every row', () async {
    final c = container((req) => req.path.endsWith('unseen-count')
        ? {'count': 1}
        : req.method == 'POST'
            ? 204
            : {'notifications': [row('a'), row('b')], 'next_cursor': null, 'unseen_count': 1});
    await c.read(notificationFeedProvider.future);

    await c.read(notificationFeedProvider.notifier).markRead('a');
    expect(c.read(notificationFeedProvider).value!.items.first.isUnread, isFalse);
    expect(requests.any((r) => r.path == '/api/mobile/notifications/a/read'), isTrue);

    await c.read(notificationFeedProvider.notifier).markAllRead();
    expect(c.read(notificationFeedProvider).value!.items.every((i) => !i.isUnread), isTrue);
  });

  test('markSeen posts and invalidates the unseen count', () async {
    var unseen = 3;
    final c = container((req) {
      if (req.path.endsWith('unseen-count')) return {'count': unseen};
      if (req.path.endsWith('/seen')) { unseen = 0; return 204; }
      return {'notifications': [row('a')], 'next_cursor': null, 'unseen_count': unseen};
    });
    await c.read(notificationFeedProvider.future);
    expect(await c.read(unseenNotificationsCountProvider.future), 3);

    await c.read(notificationFeedProvider.notifier).markSeen();
    expect(await c.read(unseenNotificationsCountProvider.future), 0);
  });
}
