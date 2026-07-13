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
  });
}
