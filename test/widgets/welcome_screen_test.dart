import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/auth/screens/welcome_screen.dart';

// A minimal router so the welcome screen's Log In / Create Account buttons have
// somewhere to push. The real routes are stubbed to bare markers we can find.
GoRouter _router() => GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(
          path: '/welcome',
          builder: (_, __) => const WelcomeScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const CupertinoPageScaffold(
            child: Center(child: Text('LOGIN_STUB')),
          ),
        ),
        GoRoute(
          path: '/signup',
          builder: (_, __) => const CupertinoPageScaffold(
            child: Center(child: Text('SIGNUP_STUB')),
          ),
        ),
      ],
    );

Future<void> _pumpWelcome(WidgetTester tester) async {
  await tester.pumpWidget(CupertinoApp.router(routerConfig: _router()));
  await tester.pumpAndSettle();
}

void main() {
  group('WelcomeScreen', () {
    testWidgets('renders the first showcase panel with no auth required',
        (tester) async {
      await _pumpWelcome(tester);

      // Branding plus the first demo panel's copy and mock content are visible
      // immediately — a logged-out user sees real app features, not a login wall.
      expect(find.text('Bandmate'), findsOneWidget);
      expect(find.text('Your whole season at a glance'), findsOneWidget);
      expect(find.text('Riverfront Wedding'), findsWidgets);
    });

    testWidgets('offers Log In and Create Account actions', (tester) async {
      await _pumpWelcome(tester);

      expect(find.text('Log In'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
    });

    testWidgets('Log In navigates to the login screen', (tester) async {
      await _pumpWelcome(tester);

      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_STUB'), findsOneWidget);
    });

    testWidgets('Create Account navigates to the signup screen',
        (tester) async {
      await _pumpWelcome(tester);

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('SIGNUP_STUB'), findsOneWidget);
    });

    testWidgets('swiping the carousel reveals later feature panels',
        (tester) async {
      await _pumpWelcome(tester);

      expect(find.text('Manage every booking'), findsNothing);

      await tester.fling(
        find.byType(PageView),
        const Offset(-400, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text('Manage every booking'), findsOneWidget);
    });
  });
}
