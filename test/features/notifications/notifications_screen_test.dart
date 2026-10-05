import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

NotificationItem item(String id, {bool unread = true, String kind = 'event', String? deeplink}) => NotificationItem(
      id: id, kind: kind, text: 'Notification $id', deeplink: deeplink ?? '/events/$id',
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
    child: CupertinoApp(home: NotificationsScreen(navigate: (_, __) {})),
  ));
  await tester.pumpAndSettle();
  return repo;
}

// Hosts NotificationsScreen behind a real GoRouter with a destination route,
// using the default `navigate` (no injected override) so the real
// go-vs-push branching in NotificationsScreen._open is exercised end to end.
Future<GoRouter> pumpWithRouter(WidgetTester tester, NotificationItem openedItem) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = FakeNotificationRepository([openedItem]);
  final router = GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: openedItem.deeplink, builder: (_, __) => const Placeholder()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [notificationRepositoryProvider.overrideWithValue(repo)],
    child: CupertinoApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
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

  testWidgets('tapping a non-dashboard row pushes the deeplink, keeping the feed on the stack', (tester) async {
    final booking = item('a', deeplink: '/bookings/1/695');
    final router = await pumpWithRouter(tester, booking);

    await tester.tap(find.text('Notification a'));
    await tester.pumpAndSettle();

    final config = router.routerDelegate.currentConfiguration;
    // push leaves the base location alone and appends a match on top of it —
    // unlike go, routeInformationProvider/currentConfiguration.uri.path do
    // NOT move for a push, so the pushed destination must be read from the
    // match stack itself (the same pattern app_scaffold_route_saving_test
    // uses for its own pushed-route assertions).
    expect(config.last.matchedLocation, '/bookings/1/695');
    // The feed route is still underneath (2 matches), so Back returns to it
    // instead of exiting the app.
    expect(config.matches.length, 2);
    expect(config.matches.first.matchedLocation, '/notifications');
  });

  testWidgets('tapping a dashboard-fallback row uses go, replacing the stack', (tester) async {
    final fallback = item('a', deeplink: '/dashboard');
    final router = await pumpWithRouter(tester, fallback);

    await tester.tap(find.text('Notification a'));
    await tester.pumpAndSettle();

    final config = router.routerDelegate.currentConfiguration;
    // go replaces the whole stack, so both the resolved uri and the single
    // remaining match land on the dashboard fallback.
    expect(config.uri.path, '/dashboard');
    expect(config.matches.length, 1);
    expect(config.last.matchedLocation, '/dashboard');
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
