# Mobile Notifications — Flutter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the web bell in the app — a bell with an unseen badge on the Dashboard nav bar, a `/notifications` feed that deep-links into the right screens, live refresh from the user channel, and routing for the new `type: notification` pushes.

**Architecture:** A `NotificationRepository` over the new `/api/mobile/notifications*` endpoints feeds an `AsyncNotifier` with cursor pagination plus a small unseen-count provider; the existing `userRealtimeProvider` gains a `notification` model case that invalidates both; the feed screen marks seen on open and read on tap, then `context.go(deeplink)`. Push routing is one extra `type` in the existing pure mappers.

**Tech Stack:** Flutter (Cupertino), Riverpod v2 (`AsyncNotifier`/`Notifier`), GoRouter, Dio with the repo's `StubAdapter` test harness, `timeago`, `intl`, `flutter_local_notifications`, `firebase_messaging`.

**Spec:** `/home/eddie/github/TTS/docs/superpowers/specs/2026-10-05-mobile-notifications-design.md` (§6–§7 are the mobile sections; the backend half is TTS PR `feat/mobile-notifications-api`).

## Global Constraints

- Branch `feat/notifications-feed` (off `origin/main`); PR targets **main**. Never stage the pre-existing modified files under `test/screenshots/` or `.claude/agent-memory/` — add files explicitly.
- Wire contract from the backend (frozen): `GET /api/mobile/notifications?cursor=&limit=` → `{ notifications: [{ id: string(uuid), kind, text, deeplink, web_url, read_at, seen_at, created_at }], next_cursor: string|null, unseen_count: int }`; `GET …/unseen-count` → `{ count }`; `POST …/{id}/read`, `POST …/read-all`, `POST …/seen` → 204. Push: `{ type: 'notification', notificationId, kind, title, body, deeplink }`.
- `kind` ∈ `booking | event | rehearsal | conversation | band | questionnaire | dashboard`; unknown kinds render the generic icon; a missing/unknown `deeplink` falls back to `/dashboard`.
- Deep links use `context.go(deeplink)` (all resolver outputs are extra-less routes). The `/notifications` route is a pushed, non-shell screen opened with `context.push('/notifications')`.
- Realtime: only `userRealtimeProvider` subscribes to the user channel; the `notification` case invalidates `notificationFeedProvider` and `unseenNotificationsCountProvider`.
- Dark mode via existing conventions (`CupertinoColors.*.resolveFrom(context)`, `context.secondaryText`). Widget tests pump at `Size(320, 568)`.
- `flutter analyze` clean (3 known pre-existing issues only) and `flutter test` green after every task. Commit after each task with:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_012ZDh9GpWe1T87HGLYpc8oQ
  ```
- Version bump: per project convention the pubspec bump lands in the feature PR once Eddie names the version — leave `version:` untouched unless told the number (Task 6 flags it).

---

## File structure

**Create**
- `lib/features/notifications/data/models/notification_item.dart`
- `lib/features/notifications/data/notification_repository.dart`
- `lib/features/notifications/providers/notification_feed_provider.dart`
- `lib/features/notifications/screens/notifications_screen.dart`
- `lib/features/notifications/widgets/notification_row.dart`
- `lib/shared/widgets/unread_badge.dart`
- `test/features/notifications/notification_item_test.dart`
- `test/features/notifications/notification_repository_test.dart`
- `test/features/notifications/notification_feed_provider_test.dart`
- `test/features/notifications/notifications_screen_test.dart`
- `test/features/notifications/dashboard_bell_test.dart`

**Modify**
- `lib/core/network/api_endpoints.dart`
- `lib/shared/providers/user_realtime_provider.dart`
- `lib/features/notifications/data/push_payload.dart`, `push_route.dart`
- `lib/features/notifications/services/push_service.dart` (`isForegroundRenderable`)
- `lib/shared/widgets/app_scaffold.dart` (use `UnreadBadge`)
- `lib/features/dashboard/screens/dashboard_screen.dart` (bell)
- `lib/core/config/router.dart` (route + restore prefix)
- `test/notifications/push_route_test.dart`, `test/notifications/push_payload_test.dart`

---

### Task 1: Model, endpoints, repository

**Files:**
- Create: `lib/features/notifications/data/models/notification_item.dart`
- Create: `lib/features/notifications/data/notification_repository.dart`
- Modify: `lib/core/network/api_endpoints.dart`
- Create: `test/features/notifications/notification_item_test.dart`, `test/features/notifications/notification_repository_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class NotificationItem { final String id; final String kind; final String text; final String deeplink; final DateTime? readAt; final DateTime? seenAt; final DateTime createdAt; bool get isUnread; factory NotificationItem.fromJson(Map<String, dynamic>); NotificationItem copyWith({DateTime? readAt, DateTime? seenAt}); }
  class NotificationPage { final List<NotificationItem> items; final String? nextCursor; final int unseenCount; }
  class NotificationRepository { NotificationRepository(Dio dio); Future<NotificationPage> list({String? cursor, int limit = 30}); Future<int> unseenCount(); Future<void> markRead(String id); Future<void> markAllRead(); Future<void> markSeen(); }
  final notificationRepositoryProvider = Provider<NotificationRepository>(…);
  ```
  Endpoints: `ApiEndpoints.mobileNotifications`, `mobileNotificationsUnseen`, `mobileNotificationsReadAll`, `mobileNotificationsSeen`, `mobileNotificationRead(String id)`.

- [ ] **Step 1: Write the failing tests**

`test/features/notifications/notification_item_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/models/notification_item.dart';

void main() {
  test('parses a presented row', () {
    final n = NotificationItem.fromJson({
      'id': 'a1b2',
      'kind': 'booking',
      'text': 'Payment received',
      'deeplink': '/bookings/1/42',
      'web_url': '/bands/1/booking/42',
      'read_at': null,
      'seen_at': '2026-10-05T10:00:00+00:00',
      'created_at': '2026-10-05T09:00:00+00:00',
    });
    expect(n.id, 'a1b2');
    expect(n.kind, 'booking');
    expect(n.deeplink, '/bookings/1/42');
    expect(n.isUnread, isTrue);
    expect(n.seenAt, isNotNull);
    expect(n.createdAt.toUtc().hour, 9);
  });

  test('tolerates missing fields with safe defaults', () {
    final n = NotificationItem.fromJson({'id': 'x', 'created_at': '2026-10-05T09:00:00+00:00'});
    expect(n.kind, 'dashboard');
    expect(n.text, 'New notification');
    expect(n.deeplink, '/dashboard');
    expect(n.readAt, isNull);
  });

  test('copyWith marks read', () {
    final n = NotificationItem.fromJson({'id': 'x', 'created_at': '2026-10-05T09:00:00+00:00'});
    expect(n.copyWith(readAt: DateTime(2026, 10, 5)).isUnread, isFalse);
  });
}
```

`test/features/notifications/notification_repository_test.dart`:
```dart
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
        return json(body is int ? body : 200, body is int ? null : body);
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
```
Check `test/helpers/test_harness.dart` for the exact `json(status, body)` helper signature (it exists: `StubAdapter` + `json`); adapt the 204 case to whatever it accepts for an empty body (e.g. `json(204, null)` or `empty(204)`).

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/notifications/notification_item_test.dart test/features/notifications/notification_repository_test.dart`
Expected: FAIL — imports not found.

- [ ] **Step 3: Endpoints**

Append to `lib/core/network/api_endpoints.dart` (near the chat block):
```dart
  // In-app notification feed (the web "bell").
  static const String mobileNotifications = '/api/mobile/notifications';
  static const String mobileNotificationsUnseen = '/api/mobile/notifications/unseen-count';
  static const String mobileNotificationsReadAll = '/api/mobile/notifications/read-all';
  static const String mobileNotificationsSeen = '/api/mobile/notifications/seen';
  static String mobileNotificationRead(String id) => '/api/mobile/notifications/$id/read';
```

- [ ] **Step 4: Model**

`lib/features/notifications/data/models/notification_item.dart`:
```dart
/// One row of the in-app feed, exactly as the backend presents it: the
/// server resolves `kind` and a mobile `deeplink`, so the client never
/// interprets stored payloads.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.kind,
    required this.text,
    required this.deeplink,
    required this.createdAt,
    this.readAt,
    this.seenAt,
  });

  final String id;
  final String kind;
  final String text;
  final String deeplink;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? seenAt;

  bool get isUnread => readAt == null;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    DateTime? date(Object? v) => v == null ? null : DateTime.tryParse(v.toString());
    final deeplink = (json['deeplink'] ?? '').toString();
    return NotificationItem(
      id: (json['id'] ?? '').toString(),
      kind: (json['kind'] ?? 'dashboard').toString(),
      text: (json['text'] ?? 'New notification').toString(),
      deeplink: deeplink.startsWith('/') ? deeplink : '/dashboard',
      createdAt: date(json['created_at']) ?? DateTime.now(),
      readAt: date(json['read_at']),
      seenAt: date(json['seen_at']),
    );
  }

  NotificationItem copyWith({DateTime? readAt, DateTime? seenAt}) => NotificationItem(
        id: id,
        kind: kind,
        text: text,
        deeplink: deeplink,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
        seenAt: seenAt ?? this.seenAt,
      );
}

class NotificationPage {
  const NotificationPage({required this.items, required this.nextCursor, required this.unseenCount});
  final List<NotificationItem> items;
  final String? nextCursor;
  final int unseenCount;
}
```

- [ ] **Step 5: Repository**

`lib/features/notifications/data/notification_repository.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/notification_item.dart';

class NotificationRepository {
  NotificationRepository(this._dio);
  final Dio _dio;

  Future<NotificationPage> list({String? cursor, int limit = 30}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileNotifications,
      queryParameters: {if (cursor != null) 'cursor': cursor, 'limit': limit},
    );
    final data = res.data ?? const {};
    return NotificationPage(
      items: (data['notifications'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(NotificationItem.fromJson)
          .toList(),
      nextCursor: data['next_cursor']?.toString(),
      unseenCount: (data['unseen_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<int> unseenCount() async {
    final res = await _dio.get<Map<String, dynamic>>(ApiEndpoints.mobileNotificationsUnseen);
    return (res.data?['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String id) => _dio.post<void>(ApiEndpoints.mobileNotificationRead(id));
  Future<void> markAllRead() => _dio.post<void>(ApiEndpoints.mobileNotificationsReadAll);
  Future<void> markSeen() => _dio.post<void>(ApiEndpoints.mobileNotificationsSeen);
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(apiClientProvider).dio);
});
```
Match how `chatRepositoryProvider` obtains its Dio (open `lib/features/chat/data/chat_repository.dart` bottom) and copy that exact expression if it differs from `ref.watch(apiClientProvider).dio`.

- [ ] **Step 6: Run the tests**

Run: `flutter test test/features/notifications/notification_item_test.dart test/features/notifications/notification_repository_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/features/notifications/data/models/notification_item.dart lib/features/notifications/data/notification_repository.dart lib/core/network/api_endpoints.dart test/features/notifications/notification_item_test.dart test/features/notifications/notification_repository_test.dart
git commit -m "feat(notifications): NotificationItem model and repository over the mobile feed API"
```

---

### Task 2: Feed + unseen providers, realtime and resume refresh

**Files:**
- Create: `lib/features/notifications/providers/notification_feed_provider.dart`
- Modify: `lib/shared/providers/user_realtime_provider.dart`
- Create: `test/features/notifications/notification_feed_provider_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class NotificationFeedState { final List<NotificationItem> items; final String? nextCursor; final bool loadingMore; final bool hasMore; }
  class NotificationFeedNotifier extends AsyncNotifier<NotificationFeedState> { Future<void> refresh(); Future<void> loadMore(); Future<void> markRead(String id); Future<void> markAllRead(); Future<void> markSeen(); }
  final notificationFeedProvider = AsyncNotifierProvider<NotificationFeedNotifier, NotificationFeedState>(…);
  final unseenNotificationsCountProvider = FutureProvider<int>(…);
  ```
- `userRealtimeProvider`: `model == 'notification'` → invalidates both providers (debounced like `message`).

- [ ] **Step 1: Write the failing tests**

`test/features/notifications/notification_feed_provider_test.dart`:
```dart
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
  late List<RequestOptions> requests;

  ProviderContainer container(Object Function(RequestOptions) handler) {
    requests = [];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((req) async {
        requests.add(req);
        final body = handler(req);
        return json(body is int ? body : 200, body is int ? null : body);
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
```

Realtime case — append to `test/shared/providers/user_realtime_provider_test.dart` if it exists (`ls test/shared/providers/ | grep user_realtime`), mirroring its existing "message signal invalidates chatConversationsProvider" test:
```dart
  test('notification signal invalidates the feed and the unseen count', () async {
    // Same harness as the message-signal test above: capture the bound
    // onEvent, then fire a user.data-changed with model 'notification'.
    // Assert the invalidator was called with notificationFeedProvider and
    // unseenNotificationsCountProvider (after the debounce).
  });
```
Write the real body by copying the message test and swapping the model + expected providers (the invalidator in that test is a recording override of `providerInvalidatorProvider`).

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/notifications/notification_feed_provider_test.dart test/shared/providers/user_realtime_provider_test.dart`
Expected: FAIL — provider not found / new test fails.

- [ ] **Step 3: Providers**

`lib/features/notifications/providers/notification_feed_provider.dart`:
```dart
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/notification_item.dart';
import '../data/notification_repository.dart';

class NotificationFeedState {
  const NotificationFeedState({
    this.items = const [],
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<NotificationItem> items;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  NotificationFeedState copyWith({
    List<NotificationItem>? items,
    Object? nextCursor = _unset,
    bool? loadingMore,
  }) =>
      NotificationFeedState(
        items: items ?? this.items,
        nextCursor: nextCursor == _unset ? this.nextCursor : nextCursor as String?,
        loadingMore: loadingMore ?? this.loadingMore,
      );

  static const _unset = Object();
}

/// Unseen count for the Dashboard bell. Invalidated by the user-channel
/// 'notification' signal, by markSeen(), and on resume.
final unseenNotificationsCountProvider = FutureProvider<int>((ref) {
  return ref.watch(notificationRepositoryProvider).unseenCount();
});

/// The feed itself: first page on build, cursor pagination, optimistic reads.
/// Refetches on app resume (Pusher has no replay while backgrounded).
class NotificationFeedNotifier extends AsyncNotifier<NotificationFeedState> {
  AppLifecycleListener? _lifecycle;

  @override
  Future<NotificationFeedState> build() async {
    ref.onDispose(() {
      _lifecycle?.dispose();
      _lifecycle = null;
    });
    _lifecycle ??= AppLifecycleListener(onResume: () {
      ref.invalidateSelf();
      ref.invalidate(unseenNotificationsCountProvider);
    });
    final page = await ref.watch(notificationRepositoryProvider).list();
    return NotificationFeedState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(notificationRepositoryProvider).list(cursor: current.nextCursor);
      final seen = current.items.map((i) => i.id).toSet();
      state = AsyncData(current.copyWith(
        items: [...current.items, ...page.items.where((i) => !seen.contains(i.id))],
        nextCursor: page.nextCursor,
        loadingMore: false,
      ));
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }

  Future<void> markRead(String id) async {
    final current = state.value;
    if (current == null) return;
    final now = DateTime.now();
    state = AsyncData(current.copyWith(
      items: [for (final i in current.items) i.id == id && i.isUnread ? i.copyWith(readAt: now) : i],
    ));
    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
    } catch (_) {
      // best-effort; the next refresh reconciles
    }
  }

  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null) return;
    final now = DateTime.now();
    state = AsyncData(current.copyWith(
      items: [for (final i in current.items) i.isUnread ? i.copyWith(readAt: now) : i],
    ));
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
    } catch (_) {}
  }

  Future<void> markSeen() async {
    try {
      await ref.read(notificationRepositoryProvider).markSeen();
    } catch (_) {
      return;
    }
    ref.invalidate(unseenNotificationsCountProvider);
  }
}

final notificationFeedProvider =
    AsyncNotifierProvider<NotificationFeedNotifier, NotificationFeedState>(
  NotificationFeedNotifier.new,
);
```

- [ ] **Step 4: Realtime case**

In `lib/shared/providers/user_realtime_provider.dart`:
- import `'../../features/notifications/providers/notification_feed_provider.dart';`
- track pending models: replace `bool _pending = false;` with `final Set<String> _pending = {};`
- `_onSignal`: 
```dart
  void _onSignal(String eventName, Map<String, dynamic> data) {
    if (eventName != userDataChangedEvent) return;
    final model = data['model']?.toString();
    if (model != 'message' && model != 'notification') return;
    _pending.add(model!);
    _flushTimer ??= Timer(ref.read(bandRealtimeDebounceProvider), _flush);
  }
```
- `_flush`:
```dart
  void _flush() {
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final invalidate = ref.read(providerInvalidatorProvider);
    if (_pending.contains('message')) invalidate(chatConversationsProvider);
    if (_pending.contains('notification')) {
      invalidate(notificationFeedProvider);
      invalidate(unseenNotificationsCountProvider);
    }
    _pending.clear();
  }
```
Update the class doc comment ("currently only DM 'message' signals" → "DM 'message' and bell 'notification' signals").

- [ ] **Step 5: Run the tests + analyze**

Run: `flutter test test/features/notifications test/shared/providers && flutter analyze`
Expected: PASS; analyze shows only the 3 known pre-existing issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/notifications/providers/notification_feed_provider.dart lib/shared/providers/user_realtime_provider.dart test/features/notifications/notification_feed_provider_test.dart test/shared/providers/user_realtime_provider_test.dart
git commit -m "feat(notifications): feed and unseen-count providers with realtime and resume refresh"
```

---

### Task 3: Push routing for `type: notification`

**Files:**
- Modify: `lib/features/notifications/data/push_payload.dart`, `lib/features/notifications/data/push_route.dart`, `lib/features/notifications/services/push_service.dart`
- Modify: `test/notifications/push_route_test.dart`, `test/notifications/push_payload_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to `test/notifications/push_route_test.dart`:
```dart
  test('notification pushes route to their deeplink', () {
    expect(
      routeForPushData({'type': 'notification', 'notificationId': 'abc', 'deeplink': '/bookings/1/42'}),
      '/bookings/1/42',
    );
  });

  test('notification pushes without a usable deeplink go to the dashboard', () {
    expect(routeForPushData({'type': 'notification', 'notificationId': 'abc'}), '/dashboard');
    expect(routeForPushData({'type': 'notification', 'deeplink': 'javascript:alert(1)'}), '/dashboard');
  });
```
Append to `test/notifications/push_payload_test.dart` (inside `main`, outside the existing group or in a new group):
```dart
  group('notification type', () {
    test('parses notificationId, kind and deeplink', () {
      final p = PushPayload.fromData({
        'type': 'notification', 'notificationId': 'abc', 'kind': 'booking',
        'title': 'TTS', 'body': 'Payment received', 'deeplink': '/bookings/1/42',
      });
      expect(p.type, PushType.notification);
      expect(p.notificationId, 'abc');
      expect(p.kind, 'booking');
      expect(p.deeplink, '/bookings/1/42');
    });

    test('renders in the background on the band-updates channel with its route', () {
      final spec = buildBackgroundNotification({
        'type': 'notification', 'notificationId': 'abc', 'title': 'TTS', 'body': 'hi', 'deeplink': '/events/k',
      });
      expect(spec, isNotNull);
      expect(spec!.route, '/events/k');
      expect(spec.channelId, BandUpdatesChannel.id);
    });

    test('two notification pushes get distinct local ids', () {
      final a = PushPayload.fromData({'type': 'notification', 'notificationId': 'a'});
      final b = PushPayload.fromData({'type': 'notification', 'notificationId': 'b'});
      expect(a.notificationId, isNot(b.notificationId));
      expect(a.notificationId, isNot(0));
    });
  });
```
(`BandUpdatesChannel` import: `package:tts_bandmate/features/notifications/data/notification_channels.dart`.) Note the existing `int get notificationId` getter name collides with the new string field — rename the getter to `localNotificationId` in this task (see Step 3) and update its two call sites (`push_service.dart`, `buildBackgroundNotification`).

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/notifications/push_route_test.dart test/notifications/push_payload_test.dart`
Expected: FAIL (compile errors / wrong routes).

- [ ] **Step 3: Implement**

`push_payload.dart`:
- `enum PushType { …, questionnaireSubmitted, notification, unknown }` and `case 'notification': return PushType.notification;` in `_typeFromString`.
- Add fields `final String? notificationId; final String? kind; final String? deeplink;` to `PushPayload` (constructor + `fromData`: `notificationId: str('notificationId'), kind: str('kind'), deeplink: str('deeplink')`).
- Rename the existing `int get notificationId` getter to `int get localNotificationId` and add the bell case so each notification gets its own slot:
```dart
  int get localNotificationId {
    if (type == PushType.departure) return departureNotificationId(eventKey);
    if (type == PushType.notification && notificationId != null) {
      return Object.hash(notificationId, type).toUnsigned(31);
    }
    final entity = eventKey.isNotEmpty ? eventKey : (conversationId ?? rehearsalId ?? instanceId ?? '');
    return Object.hash(entity, type).toUnsigned(31);
  }
```
- `buildBackgroundNotification`: `rendersInBackground` also true for `PushType.notification`; `id: payload.localNotificationId`.

`push_route.dart` — add at the top of `routeForPushData`:
```dart
  if (type == 'notification') {
    final deeplink = data['deeplink']?.toString() ?? '';
    return deeplink.startsWith('/') ? deeplink : '/dashboard';
  }
```

`push_service.dart`:
- `isForegroundRenderable` → also `payload.type == PushType.notification`.
- `localNotificationId(payload, …)` (the service helper) and any `payload.notificationId` int usages → `payload.localNotificationId`. Grep: `grep -rn "\.notificationId" lib/features/notifications` and fix every int-context use.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/notifications && flutter analyze`
Expected: PASS; analyze clean (known issues only).

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/data/push_payload.dart lib/features/notifications/data/push_route.dart lib/features/notifications/services/push_service.dart test/notifications/push_route_test.dart test/notifications/push_payload_test.dart
git commit -m "feat(notifications): route type=notification pushes to their server-resolved deeplink"
```

---

### Task 4: `UnreadBadge`, Dashboard bell, `NotificationsScreen`, route

**Files:**
- Create: `lib/shared/widgets/unread_badge.dart`
- Modify: `lib/shared/widgets/app_scaffold.dart` (`_tabIcon` uses `UnreadBadge`)
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`
- Create: `lib/features/notifications/widgets/notification_row.dart`, `lib/features/notifications/screens/notifications_screen.dart`
- Modify: `lib/core/config/router.dart`
- Create: `test/features/notifications/notifications_screen_test.dart`, `test/features/notifications/dashboard_bell_test.dart`

**Interfaces:**
- `UnreadBadge({required Widget child, required int count})` — wraps `child` in the existing red pill at `top: -4, right: -10`, hidden when `count <= 0`, `99+` cap.
- `NotificationRow({required NotificationItem item, required VoidCallback onTap})`.
- `NotificationsScreen` (ConsumerStatefulWidget) at route `/notifications`.
- `kindIcon(String kind) → IconData` (in `notification_row.dart`): booking → `CupertinoIcons.briefcase`, event → `calendar`, rehearsal → `music_note`, conversation → `chat_bubble`, band → `person_2`, questionnaire → `doc_text`, else `bell`.

- [ ] **Step 1: Write the failing tests**

`test/features/notifications/notifications_screen_test.dart`:
```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/models/notification_item.dart';
import 'package:tts_bandmate/features/notifications/data/notification_repository.dart';
import 'package:tts_bandmate/features/notifications/screens/notifications_screen.dart';

class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository(this.items, {this.fail = false});
  final List<NotificationItem> items;
  final bool fail;
  final List<String> calls = [];

  @override
  Future<NotificationPage> list({String? cursor, int limit = 30}) async {
    calls.add('list');
    if (fail) throw Exception('boom');
    return NotificationPage(items: items, nextCursor: null, unseenCount: items.where((i) => i.seenAt == null).length);
  }

  @override
  Future<int> unseenCount() async => items.where((i) => i.seenAt == null).length;
  @override
  Future<void> markRead(String id) async => calls.add('read:$id');
  @override
  Future<void> markAllRead() async => calls.add('read-all');
  @override
  Future<void> markSeen() async => calls.add('seen');
}

NotificationItem item(String id, {bool unread = true, String kind = 'event'}) => NotificationItem(
      id: id, kind: kind, text: 'Notification $id', deeplink: '/events/$id',
      createdAt: DateTime(2026, 10, 5, 9), readAt: unread ? null : DateTime(2026, 10, 5, 10),
    );

Future<FakeNotificationRepository> pump(WidgetTester tester, List<NotificationItem> items, {bool fail = false}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = FakeNotificationRepository(items, fail: fail);
  await tester.pumpWidget(ProviderScope(
    overrides: [notificationRepositoryProvider.overrideWithValue(repo)],
    child: const CupertinoApp(home: NotificationsScreen()),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('renders rows, marks seen on open, shows unread dots', (tester) async {
    final repo = await pump(tester, [item('a'), item('b', unread: false)]);
    expect(find.text('Notification a'), findsOneWidget);
    expect(find.text('Notification b'), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-dot-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-dot-b')), findsNothing);
    expect(repo.calls, contains('seen'));
  });

  testWidgets('tapping a row marks it read', (tester) async {
    final repo = await pump(tester, [item('a')]);
    await tester.tap(find.text('Notification a'));
    await tester.pump();
    expect(repo.calls, contains('read:a'));
    expect(find.byKey(const ValueKey('unread-dot-a')), findsNothing);
  });

  testWidgets('mark all read clears every dot', (tester) async {
    final repo = await pump(tester, [item('a'), item('b')]);
    await tester.tap(find.text('Mark all read'));
    await tester.pump();
    expect(repo.calls, contains('read-all'));
    expect(find.byKey(const ValueKey('unread-dot-a')), findsNothing);
  });

  testWidgets('empty and error states', (tester) async {
    await pump(tester, []);
    expect(find.textContaining("caught up"), findsOneWidget);

    await pump(tester, [], fail: true);
    expect(find.textContaining('Retry'), findsOneWidget);
  });
}
```
Navigation on tap uses `context.go`, which needs a router; in the test there is none, so the screen must call `onOpen` through a small injectable: give `NotificationsScreen` an optional `void Function(BuildContext, String deeplink)? navigate` parameter defaulting to `(ctx, link) => ctx.go(link)`, and pass a no-op in the test (`home: NotificationsScreen(navigate: (_, __) {})`).

`test/features/notifications/dashboard_bell_test.dart` — test `UnreadBadge` directly (the Dashboard has heavy provider dependencies):
```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/shared/widgets/unread_badge.dart';

void main() {
  testWidgets('UnreadBadge hides at zero and caps at 99+', (tester) async {
    await tester.pumpWidget(const CupertinoApp(home: UnreadBadge(count: 0, child: Icon(CupertinoIcons.bell))));
    expect(find.text('0'), findsNothing);

    await tester.pumpWidget(const CupertinoApp(home: UnreadBadge(count: 5, child: Icon(CupertinoIcons.bell))));
    expect(find.text('5'), findsOneWidget);

    await tester.pumpWidget(const CupertinoApp(home: UnreadBadge(count: 150, child: Icon(CupertinoIcons.bell))));
    expect(find.text('99+'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/notifications/notifications_screen_test.dart test/features/notifications/dashboard_bell_test.dart`
Expected: FAIL — imports not found.

- [ ] **Step 3: `UnreadBadge` and AppScaffold**

`lib/shared/widgets/unread_badge.dart`:
```dart
import 'package:flutter/cupertino.dart';

/// The red count pill used on the Messages tab and the Dashboard bell.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.child, required this.count});

  final Widget child;
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          right: -10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 16),
            height: 16,
            decoration: BoxDecoration(
              color: CupertinoColors.systemRed.resolveFrom(context),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```
In `app_scaffold.dart`, replace the body of `_tabIcon` with:
```dart
    final icon = Icon(selected ? d.activeIcon : d.icon);
    if (d.route != '/messages') return icon;
    return UnreadBadge(count: unread, child: icon);
```
(+ import). Existing AppScaffold badge tests must still pass unchanged.

- [ ] **Step 4: Dashboard bell**

In `dashboard_screen.dart`, inside the nav bar `trailing` `Row`, insert BEFORE the `+` `CupertinoButton`:
```dart
                    Consumer(builder: (context, ref, _) {
                      final unseen = ref.watch(unseenNotificationsCountProvider).value ?? 0;
                      return Semantics(
                        label: unseen > 0 ? 'Notifications, $unseen unseen' : 'Notifications',
                        button: true,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => context.push('/notifications'),
                          child: UnreadBadge(
                            count: unseen,
                            child: Icon(unseen > 0 ? CupertinoIcons.bell_fill : CupertinoIcons.bell),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(width: 4),
```
(imports: `unread_badge.dart`, `notification_feed_provider.dart`; `Consumer` from flutter_riverpod — if the Dashboard widget is already a `ConsumerWidget`/`ConsumerState` with `ref` in scope, use `ref.watch` directly and drop the `Consumer`.)

- [ ] **Step 5: Row + screen**

`lib/features/notifications/widgets/notification_row.dart`:
```dart
import 'package:flutter/cupertino.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../shared/theme/app_text_colors.dart'; // adjust to where context.secondaryText lives
import '../data/models/notification_item.dart';

IconData kindIcon(String kind) {
  switch (kind) {
    case 'booking':
      return CupertinoIcons.briefcase;
    case 'event':
      return CupertinoIcons.calendar;
    case 'rehearsal':
      return CupertinoIcons.music_note;
    case 'conversation':
      return CupertinoIcons.chat_bubble;
    case 'band':
      return CupertinoIcons.person_2;
    case 'questionnaire':
      return CupertinoIcons.doc_text;
    default:
      return CupertinoIcons.bell;
  }
}

class NotificationRow extends StatelessWidget {
  const NotificationRow({super.key, required this.item, required this.onTap});

  final NotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = context.secondaryText;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onPressed: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemFill.resolveFrom(context),
              shape: BoxShape.circle,
            ),
            child: Icon(kindIcon(item.kind), size: 18, color: secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: item.isUnread ? FontWeight.w600 : FontWeight.w400,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(timeago.format(item.createdAt), style: TextStyle(fontSize: 12, color: secondary)),
              ],
            ),
          ),
          if (item.isUnread)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 6),
              child: Container(
                key: ValueKey('unread-dot-${item.id}'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: CupertinoColors.activeBlue.resolveFrom(context),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```
Find the real location of the `context.secondaryText` extension (`grep -rn "secondaryText" lib/shared lib/core | head -2`) and import that.

`lib/features/notifications/screens/notifications_screen.dart`:
```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../chat/utils/message_time.dart' show dateSeparatorLabel;
import '../data/models/notification_item.dart';
import '../providers/notification_feed_provider.dart';
import '../widgets/notification_row.dart';

typedef NotificationNavigate = void Function(BuildContext context, String deeplink);

/// The in-app feed (the web "bell"). Opening it marks everything seen (badge
/// clears); tapping a row marks it read and follows its deeplink.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key, this.navigate});

  final NotificationNavigate? navigate;

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationFeedProvider.notifier).markSeen();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      ref.read(notificationFeedProvider.notifier).loadMore();
    }
  }

  void _open(NotificationItem item) {
    ref.read(notificationFeedProvider.notifier).markRead(item.id);
    (widget.navigate ?? (ctx, link) => ctx.go(link))(context, item.deeplink);
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(notificationFeedProvider);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Notifications'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => ref.read(notificationFeedProvider.notifier).markAllRead(),
          child: const Text('Mark all read', style: TextStyle(fontSize: 14)),
        ),
      ),
      child: SafeArea(
        child: feed.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load notifications'),
                CupertinoButton(
                  onPressed: () => ref.read(notificationFeedProvider.notifier).refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (state) {
            if (state.items.isEmpty) {
              return const Center(child: Text("You're all caught up"));
            }
            final now = DateTime.now();
            return CustomScrollView(
              controller: _scroll,
              slivers: [
                CupertinoSliverRefreshControl(
                  onRefresh: () => ref.read(notificationFeedProvider.notifier).refresh(),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = state.items[index];
                      final prev = index == 0 ? null : state.items[index - 1];
                      final showHeader = prev == null || !_sameDay(prev.createdAt, item.createdAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showHeader)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(
                                _dayLabel(item.createdAt, now),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                              ),
                            ),
                          NotificationRow(item: item, onTap: () => _open(item)),
                        ],
                      );
                    },
                    childCount: state.items.length,
                  ),
                ),
                if (state.loadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(padding: EdgeInsets.all(16), child: CupertinoActivityIndicator()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final la = a.toLocal(), lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  /// "Today" / "Yesterday" / weekday / date — the chat helper includes a clock,
  /// which a day header doesn't want, so strip the trailing time.
  static String _dayLabel(DateTime at, DateTime now) {
    final full = dateSeparatorLabel(at, now: now);
    final i = full.lastIndexOf(' ');
    return i > 0 ? full.substring(0, i).replaceFirst(RegExp(r' \d{1,2}:\d{2}$'), '') : full;
  }
}
```
(If stripping the clock from `dateSeparatorLabel` is awkward, write a 6-line `_dayLabel` with `DateFormat.EEEE()`/`yMMMd()` directly — same output as the chat labels minus the time.) Use `CupertinoColors.secondaryLabel.resolveFrom(context)` rather than the raw colour, per the dark-mode convention.

- [ ] **Step 6: Route**

In `lib/core/config/router.dart`: add `'/notifications'` to `_kShellPrefixes`, and a route next to `/conversations/:id`:
```dart
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
```
(+ import). It is outside the shell like `/conversations/:id`, so it gets a back chevron.

- [ ] **Step 7: Run tests + analyze**

Run: `flutter test test/features/notifications test/shared && flutter analyze`
Expected: PASS; analyze clean (known issues only). Also run the whole suite once: `flutter test`.

- [ ] **Step 8: Commit**

```bash
git add lib/shared/widgets/unread_badge.dart lib/shared/widgets/app_scaffold.dart lib/features/dashboard/screens/dashboard_screen.dart lib/features/notifications/widgets/notification_row.dart lib/features/notifications/screens/notifications_screen.dart lib/core/config/router.dart test/features/notifications/notifications_screen_test.dart test/features/notifications/dashboard_bell_test.dart
git commit -m "feat(notifications): Dashboard bell with unseen badge and the /notifications feed screen"
```

---

### Task 5: On-device verification + PR

- [ ] **Step 1:** `flutter analyze` and `flutter test` green.
- [ ] **Step 2:** Use the `run-on-device` skill against the local backend running the `feat/mobile-notifications-api` branch (TTS PR must be merged to staging or checked out locally). Script: (1) from the web, change a booking status for band 1 → the Dashboard bell shows a badge within a second; (2) tap the bell → feed lists the row, badge clears; (3) tap the row → booking detail opens; (4) Back → feed; "Mark all read" clears the dot; (5) set `PUSH_NOTIFICATIONS_FEED=true` locally, restart the queue worker, change another booking status → a push arrives on the phone; tap → booking detail; (6) send a DM from the web → existing chat push still arrives (not doubled); (7) dark mode (phone setting) → feed, row, bell legible. Screenshots into the scratchpad.
- [ ] **Step 3:** PR to `main`:
```bash
git push -u origin feat/notifications-feed
gh pr create --base main --title "feat(notifications): in-app notification feed, Dashboard bell badge, and bell-push routing" --body-file - <<'EOF'
## Summary
Mobile half of bringing the web bell to the app (backend: TTS `feat/mobile-notifications-api`). Spec: TTS `docs/superpowers/specs/2026-10-05-mobile-notifications-design.md`.

- `NotificationRepository` + `NotificationItem` over `/api/mobile/notifications*` (server-resolved `kind` + `deeplink`).
- `notificationFeedProvider` (cursor pagination, optimistic read/read-all, seen-on-open, resume refresh) and `unseenNotificationsCountProvider`; `userRealtimeProvider` now also reacts to `model: notification`.
- Dashboard nav-bar bell with the shared `UnreadBadge` pill (extracted from the Messages tab badge).
- `/notifications` feed screen: day headers, kind icons, unread dots, mark-all-read, infinite scroll, pull-to-refresh, empty/error states.
- `type: notification` pushes route to their `deeplink` (background + foreground rendering on the band-updates channel).

## Rollout
Backend first (flag off), then this release; flip `PUSH_NOTIFICATIONS_FEED` once the store build is live.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_012ZDh9GpWe1T87HGLYpc8oQ
EOF
```
- [ ] **Step 4:** Wait for Copilot, address comments. Flag to Eddie: this is a new release train — the pubspec bump (currently `1.28.0+47`) goes in this PR once he names the version.

---

## Self-review notes

- **Spec coverage:** §6 data/providers/realtime/resume (T1–T2), push (T3), §7 bell/feed/deep-link safety (T4), error handling (feed error+retry, best-effort acks, unknown kind/deeplink fallbacks in T1/T3/T4), testing + on-device + rollout (T5).
- **Type consistency:** `NotificationItem` fields match the backend keys; `NotificationPage.nextCursor` ↔ `list(cursor:)`; provider names used by `user_realtime_provider.dart` and `dashboard_screen.dart` match `notification_feed_provider.dart`; `PushPayload.localNotificationId` rename is applied at both int call sites; `kindIcon` kinds match the backend set.
- **Known edges:** the Dashboard test covers `UnreadBadge` rather than the full Dashboard (heavy deps); the `_dayLabel` clock-strip is a convenience over the chat helper and may be replaced by a direct `DateFormat` if fiddly.
