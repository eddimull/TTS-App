import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/contacts/contact_detail_screen.dart';
import 'package:tts_bandmate/features/search/data/models/search_models.dart';
import 'package:tts_bandmate/features/search/providers/search_provider.dart';
import 'package:tts_bandmate/features/search/screens/search_screen.dart';

// SearchScreen is hosted inside a GoRouter ShellRoute in production. Tapping a
// contact row should push the shared ContactDetailScreen onto the nested
// navigator (not show a placeholder dialog). This reproduces that topology to
// guard the navigation wiring.
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
    'tapping a contact opens the shared ContactDetailScreen '
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

      await tester.tap(find.text('Claire Hoyt'));
      await tester.pumpAndSettle();

      // The contact detail screen is pushed, showing the contact's info.
      expect(find.byType(ContactDetailScreen), findsOneWidget);
      expect(find.text('clairevhoyt@yahoo.com'), findsOneWidget);

      // Navigating back returns to the search results.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Claire Hoyt'), findsOneWidget);
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
