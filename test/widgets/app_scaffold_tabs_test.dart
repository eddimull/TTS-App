import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/widgets/app_scaffold.dart';

Widget _app(int unread) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (_, __, child) => AppScaffold(child: child),
        routes: [
          for (final p in ['/dashboard', '/search', '/messages', '/library', '/settings'])
            GoRoute(path: p, builder: (_, __) => const SizedBox()),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      chatUnreadTotalProvider.overrideWithValue(unread),
      connectivityProvider.overrideWithValue(const AsyncValue.data(true)),
    ],
    child: CupertinoApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('tab bar shows Messages and Settings, no Bookings/More',
      (tester) async {
    await tester.pumpWidget(_app(0));
    await tester.pumpAndSettle();
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Bookings'), findsNothing);
    expect(find.text('More'), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('unread badge shows count and hides at zero', (tester) async {
    await tester.pumpWidget(_app(3));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(_app(0));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsNothing);
  });
}
