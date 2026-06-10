import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/search/data/models/search_models.dart';
import 'package:tts_bandmate/features/search/providers/search_provider.dart';
import 'package:tts_bandmate/features/search/screens/search_screen.dart';

// Reproduces the production navigator topology: SearchScreen is hosted inside a
// GoRouter ShellRoute, so its widgets live under a *nested* navigator while
// showCupertinoDialog (useRootNavigator: true by default) pushes the dialog
// onto the *root* navigator. If the dialog's OK button pops the row's outer
// context, it pops the wrong navigator and the dialog can't be dismissed.
GoRouter _routerWithSearchInShell() {
  return GoRouter(
    initialLocation: '/search',
    routes: [
      ShellRoute(
        builder: (context, state, child) => child,
        routes: [
          GoRoute(
            path: '/search',
            builder: (_, __) => const SearchScreen(),
          ),
        ],
      ),
    ],
  );
}

SearchState _stateWithContact() {
  return const SearchState(
    query: 'hoyt',
    isLoading: false,
    results: SearchResults(
      songs: [],
      charts: [],
      bookings: [],
      contacts: [
        ContactResult(
          id: 1,
          bandId: 1,
          name: 'Claire Hoyt',
          email: 'clairevhoyt@yahoo.com',
          phone: '',
        ),
      ],
    ),
  );
}

void main() {
  testWidgets(
    'tapping a contact then OK dismisses the Coming Soon dialog '
    '(when search is hosted in a ShellRoute)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchProvider.overrideWith(
              () => _FakeSearchNotifier(_stateWithContact()),
            ),
          ],
          child: CupertinoApp.router(
            routerConfig: _routerWithSearchInShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the dialog by tapping the contact row.
      await tester.tap(find.text('Claire Hoyt'));
      await tester.pumpAndSettle();
      expect(find.text('Coming Soon'), findsOneWidget);

      // Tap OK — this must dismiss the dialog, not pop the underlying screen.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Coming Soon'), findsNothing,
          reason: 'OK should dismiss the dialog');
      // The search screen must still be present (we must NOT have popped it).
      expect(find.text('Claire Hoyt'), findsOneWidget,
          reason: 'OK should not pop the underlying search screen');
    },
  );
}

class _FakeSearchNotifier extends SearchNotifier {
  _FakeSearchNotifier(this._initial);

  final SearchState _initial;

  @override
  SearchState build() => _initial;

  @override
  void search(String query) {}
}
