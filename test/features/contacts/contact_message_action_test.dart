import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/contacts/contact_detail_screen.dart';
import 'package:tts_bandmate/features/contacts/contact_ref.dart';

import '../../helpers/test_harness.dart';

void main() {
  group('ContactDetailScreen Message in Bandmate', () {
    testWidgets(
      'renders "Message in Bandmate" row when contact has userId',
      (tester) async {
        final captured = <RequestOptions>[];
        final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
          ..httpClientAdapter = StubAdapter((options) async {
            captured.add(options);
            return json(200, {
              'conversation': {'id': 7, 'type': 'dm', 'title': 'JoBu'},
            });
          });

        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/contact',
              builder: (context, state) => const ContactDetailScreen(
                contact: ContactRef(
                  name: 'JoBu Dunn',
                  phone: '555-123-4567',
                  userId: 8,
                ),
              ),
            ),
            GoRoute(
              path: '/conversations/:id',
              builder: (context, state) {
                return const CupertinoPageScaffold(
                  child: Center(child: Text('Chat Stub')),
                );
              },
            ),
          ],
          initialLocation: '/contact',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
            ],
            child: CupertinoApp.router(
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The row should be present.
        expect(find.text('Message in Bandmate'), findsOneWidget);

        // The SMS row should still be present.
        expect(find.text('Send Message'), findsOneWidget);
      },
    );

    testWidgets(
      'does not render "Message in Bandmate" when userId is null',
      (tester) async {
        final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
          ..httpClientAdapter = StubAdapter((_) async => json(200, {}));

        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/contact',
              builder: (context, state) => const ContactDetailScreen(
                contact: ContactRef(
                  name: 'JoBu Dunn',
                  phone: '555-123-4567',
                  userId: null,
                ),
              ),
            ),
          ],
          initialLocation: '/contact',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
            ],
            child: CupertinoApp.router(
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The row should not be present.
        expect(find.text('Message in Bandmate'), findsNothing);
      },
    );

    testWidgets(
      'taps the Message in Bandmate row and navigates to the conversation',
      (tester) async {
        final captured = <RequestOptions>[];
        final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
          ..httpClientAdapter = StubAdapter((options) async {
            captured.add(options);
            return json(200, {
              'conversation': {'id': 7, 'type': 'dm', 'title': 'JoBu'},
            });
          });

        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/contact',
              builder: (context, state) => const ContactDetailScreen(
                contact: ContactRef(
                  name: 'JoBu Dunn',
                  phone: '555-123-4567',
                  userId: 8,
                ),
              ),
            ),
            GoRoute(
              path: '/conversations/:id',
              builder: (context, state) {
                return const CupertinoPageScaffold(
                  child: Center(child: Text('Chat Stub')),
                );
              },
            ),
          ],
          initialLocation: '/contact',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
            ],
            child: CupertinoApp.router(
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the Message in Bandmate row.
        await tester.tap(find.text('Message in Bandmate'));
        await tester.pumpAndSettle();

        // Should have posted to /api/mobile/conversations/dm
        final dmRequest = captured.firstWhere(
          (o) => o.path.contains('conversations/dm'),
          orElse: () => throw Exception('No DM request found'),
        );
        expect(dmRequest.method, 'POST');
        expect(dmRequest.data, {'user_id': 8});

        // Should be on the chat screen.
        expect(find.text('Chat Stub'), findsOneWidget);
      },
    );

    testWidgets(
      'double-tap while openDm is in flight issues exactly one request',
      (tester) async {
        var requestCount = 0;
        final gate = Completer<void>();
        final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
          ..httpClientAdapter = StubAdapter((options) async {
            requestCount++;
            // Hold the first response until the test releases the gate, so
            // the second tap lands while the row is still busy.
            await gate.future;
            return json(200, {
              'conversation': {'id': 7, 'type': 'dm', 'title': 'JoBu'},
            });
          });

        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/contact',
              builder: (context, state) => const ContactDetailScreen(
                contact: ContactRef(
                  name: 'JoBu Dunn',
                  phone: '555-123-4567',
                  userId: 8,
                ),
              ),
            ),
            GoRoute(
              path: '/conversations/:id',
              builder: (context, state) {
                return const CupertinoPageScaffold(
                  child: Center(child: Text('Chat Stub')),
                );
              },
            ),
          ],
          initialLocation: '/contact',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
            ],
            child: CupertinoApp.router(
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // First tap: request goes in flight and is held by the gate.
        await tester.tap(find.text('Message in Bandmate'));
        await tester.pump();

        // Second tap while busy: the guard must swallow it.
        await tester.tap(find.text('Message in Bandmate'));
        await tester.pump();

        // Let Dio's interceptor chain deliver the (gated) request to the
        // adapter before counting.
        await tester.pump(const Duration(milliseconds: 50));

        expect(requestCount, 1);

        // Release the response; exactly one navigation should follow.
        gate.complete();
        await tester.pumpAndSettle();

        expect(requestCount, 1);
        expect(find.text('Chat Stub'), findsOneWidget);
      },
    );

    testWidgets(
      'shows an error dialog and stays put when openDm fails',
      (tester) async {
        final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
          ..httpClientAdapter = StubAdapter(
            (_) async => json(500, {'message': 'server error'}),
          );

        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/contact',
              builder: (context, state) => const ContactDetailScreen(
                contact: ContactRef(
                  name: 'JoBu Dunn',
                  phone: '555-123-4567',
                  userId: 8,
                ),
              ),
            ),
            GoRoute(
              path: '/conversations/:id',
              builder: (context, state) {
                return const CupertinoPageScaffold(
                  child: Center(child: Text('Chat Stub')),
                );
              },
            ),
          ],
          initialLocation: '/contact',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
            ],
            child: CupertinoApp.router(
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Message in Bandmate'));
        await tester.pumpAndSettle();

        // Error dialog is shown.
        expect(find.byType(CupertinoAlertDialog), findsOneWidget);
        expect(find.text('Couldn\'t open chat'), findsOneWidget);

        // No navigation happened — still on the contact route.
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/contact',
        );
        expect(find.text('Chat Stub'), findsNothing);

        // Dismiss the dialog; the row is usable again (guard reset).
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoAlertDialog), findsNothing);
      },
    );
  });
}
