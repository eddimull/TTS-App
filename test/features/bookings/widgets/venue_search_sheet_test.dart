import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/venue_search_service.dart';
import 'package:tts_bandmate/features/bookings/widgets/venue_picker.dart';

// ── Counting fake service ────────────────────────────────────────────────────
//
// Records every query passed to search() so tests can assert how many times
// (and with what text) the debounced search actually fired.

class _CountingVenueSearchService implements VenueSearchService {
  final List<String> queries = [];

  @override
  Future<List<VenuePrediction>> search(String query) async {
    queries.add(query);
    return [];
  }
}

/// Debounce window inside VenueSearchSheet — searches fire 350ms after the
/// last text change. Tests pump past this to let the timer flush.
const _pastDebounce = Duration(milliseconds: 400);

Widget _wrap(Widget child) =>
    CupertinoApp(home: CupertinoPageScaffold(child: child));

void main() {
  testWidgets('does not search on construction when initialText is empty',
      (tester) async {
    final service = _CountingVenueSearchService();
    await tester.pumpWidget(_wrap(
      VenueSearchSheet(initialText: '', service: service),
    ));
    await tester.pump(_pastDebounce);

    expect(service.queries, isEmpty);
  });

  testWidgets('runs one seed search when initialText is non-empty',
      (tester) async {
    final service = _CountingVenueSearchService();
    await tester.pumpWidget(_wrap(
      VenueSearchSheet(initialText: 'The Blue Note', service: service),
    ));
    await tester.pumpAndSettle();

    expect(service.queries, ['The Blue Note']);
  });

  testWidgets('debounces rapid typing into a single search', (tester) async {
    final service = _CountingVenueSearchService();
    await tester.pumpWidget(_wrap(
      VenueSearchSheet(initialText: '', service: service),
    ));

    // Simulate fast typing — each enterText resets the debounce timer.
    await tester.enterText(find.byType(CupertinoSearchTextField), 'O');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(CupertinoSearchTextField), 'OM');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(CupertinoSearchTextField), 'OMa');
    await tester.pump(_pastDebounce);

    // Only the final query should have reached the service.
    expect(service.queries, ["OMa"]);
  });

  testWidgets('a no-text-change notification does not trigger a new search',
      (tester) async {
    final service = _CountingVenueSearchService();
    await tester.pumpWidget(_wrap(
      VenueSearchSheet(initialText: '', service: service),
    ));

    await tester.enterText(find.byType(CupertinoSearchTextField), "O'Malley's");
    await tester.pump(_pastDebounce);
    expect(service.queries, ["O'Malley's"]);

    // Re-set the controller to the SAME text — mimics a cursor/selection
    // change, which fires the controller listener without an edit. The
    // _lastSearchedText guard must suppress a redundant search.
    final field = tester.widget<CupertinoSearchTextField>(
      find.byType(CupertinoSearchTextField),
    );
    field.controller!.value = field.controller!.value.copyWith(
      selection: const TextSelection.collapsed(offset: 0),
    );
    await tester.pump(_pastDebounce);

    // Still exactly one search — the cursor move did not add another.
    expect(service.queries, ["O'Malley's"]);
  });
}
