import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_draft.dart';
import 'package:tts_bandmate/features/bookings/data/venue_search_service.dart';
import 'package:tts_bandmate/features/bookings/widgets/event_sub_form_card.dart';

// ── Fake VenueSearchService that always returns [] ──────────────────────────
//
// EventSubFormCard is now a ConsumerStatefulWidget and reads
// venueSearchServiceProvider via ref.  Tests must wrap the widget in a
// ProviderScope that overrides the provider so no real network calls occur.

class _FakeVenueSearchService implements VenueSearchService {
  @override
  Future<List<VenuePrediction>> search(String query) async => [];
}

/// Wraps [child] in a [ProviderScope] with the venue service overridden to the
/// no-op fake, then places it inside a [CupertinoApp] for widget tests.
Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      venueSearchServiceProvider.overrideWithValue(_FakeVenueSearchService()),
    ],
    child: CupertinoApp(
      home: Center(child: child),
    ),
  );
}

void main() {
  testWidgets('renders inline error when saveError non-null', (tester) async {
    await tester.pumpWidget(_wrap(
      EventSubFormCard(
        bandId: 1,
        draft: const EventDraft(title: 'X', date: '2026-06-13'),
        canDelete: true,
        saveError: 'Server error',
        onChange: (_) {},
        onDelete: () {},
      ),
    ));
    expect(find.text('Save failed — tap to retry'), findsOneWidget);
  });

  testWidgets('does not render error when saveError null', (tester) async {
    await tester.pumpWidget(_wrap(
      EventSubFormCard(
        bandId: 1,
        draft: const EventDraft(title: 'X', date: '2026-06-13'),
        canDelete: true,
        onChange: (_) {},
        onDelete: () {},
      ),
    ));
    expect(find.text('Save failed — tap to retry'), findsNothing);
  });

  testWidgets('delete button disabled when canDelete is false',
      (tester) async {
    var deleteCalled = false;
    await tester.pumpWidget(_wrap(
      EventSubFormCard(
        bandId: 1,
        draft: const EventDraft(title: 'X', date: '2026-06-13'),
        canDelete: false,
        onChange: (_) {},
        onDelete: () => deleteCalled = true,
      ),
    ));
    final btn = find.byIcon(CupertinoIcons.trash);
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    await tester.pump();
    expect(deleteCalled, isFalse);
  });

  testWidgets('onRetryRow fires when tapping the inline error',
      (tester) async {
    var retryCalled = false;
    await tester.pumpWidget(_wrap(
      EventSubFormCard(
        bandId: 1,
        draft: const EventDraft(title: 'X', date: '2026-06-13'),
        canDelete: true,
        saveError: 'Server error',
        onChange: (_) {},
        onDelete: () {},
        onRetryRow: () => retryCalled = true,
      ),
    ));
    await tester.tap(find.text('Save failed — tap to retry'));
    await tester.pump();
    expect(retryCalled, isTrue);
  });

  testWidgets('title field keeps the cursor at the end after a parent rebuild',
      (tester) async {
    // Reproduces the iOS bug: each keystroke triggered a parent setState
    // that rebuilt the card. The card built a fresh TextEditingController
    // inline, whose cursor defaults to offset 0 — so the next keystroke
    // inserted at the front, turning "abcdef" into "fedcba".
    EventDraft draft = const EventDraft(title: '', date: '2026-06-13');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          venueSearchServiceProvider
              .overrideWithValue(_FakeVenueSearchService()),
        ],
        child: StatefulBuilder(
          builder: (context, setState) => CupertinoApp(
            home: Center(
              child: EventSubFormCard(
        bandId: 1,
                draft: draft,
                canDelete: true,
                onChange: (newDraft) => setState(() => draft = newDraft),
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final titleField = find.byType(CupertinoTextField).first;

    // Type a character; the parent rebuilds the card via setState.
    await tester.enterText(titleField, 'abc');
    await tester.pump();

    // After the rebuild the field's controller must still hold the text
    // with the cursor at the end. A freshly-constructed controller would
    // reset selection to offset 0, which is the bug.
    final controller = tester.widget<CupertinoTextField>(titleField).controller!;
    expect(controller.text, 'abc');
    expect(controller.selection.baseOffset, 3,
        reason: 'cursor must stay at the end of the text after a rebuild');
  });

  testWidgets('shows Search venue row when no venue set', (tester) async {
    await tester.pumpWidget(_wrap(
      EventSubFormCard(
        bandId: 1,
        draft: const EventDraft(title: 'X', date: '2026-06-13'),
        canDelete: true,
        onChange: (_) {},
        onDelete: () {},
      ),
    ));
    expect(find.text('Search venue'), findsOneWidget);
  });

  testWidgets('shows venue name when venueName is set', (tester) async {
    await tester.pumpWidget(_wrap(
      EventSubFormCard(
        bandId: 1,
        draft: const EventDraft(
          title: 'X',
          date: '2026-06-13',
          venueName: 'The Blue Note',
          venueAddress: '131 W 3rd St',
        ),
        canDelete: true,
        onChange: (_) {},
        onDelete: () {},
      ),
    ));
    expect(find.text('The Blue Note'), findsOneWidget);
    expect(find.text('131 W 3rd St'), findsOneWidget);
    // Search row must not be visible when venue is set.
    expect(find.text('Search venue'), findsNothing);
  });

  testWidgets('shows address in the name slot when only an address is set',
      (tester) async {
    // An event created via the API can carry an address with no name. The
    // card must surface it (not show the empty "Search venue" row) by
    // displaying the address where the name normally goes.
    await tester.pumpWidget(_wrap(
      EventSubFormCard(
        bandId: 1,
        draft: const EventDraft(
          title: 'X',
          date: '2026-06-13',
          venueAddress: '131 W 3rd St',
        ),
        canDelete: true,
        onChange: (_) {},
        onDelete: () {},
      ),
    ));
    // Address is shown and the empty-state search row is not.
    expect(find.text('131 W 3rd St'), findsOneWidget);
    expect(find.text('Search venue'), findsNothing);
  });

  testWidgets('clear venue resets venueName via onChange', (tester) async {
    EventDraft draft = const EventDraft(
      title: 'X',
      date: '2026-06-13',
      venueName: 'The Blue Note',
      venueAddress: '131 W 3rd St',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          venueSearchServiceProvider
              .overrideWithValue(_FakeVenueSearchService()),
        ],
        child: StatefulBuilder(
          builder: (context, setState) => CupertinoApp(
            home: SingleChildScrollView(
              child: EventSubFormCard(
        bandId: 1,
                draft: draft,
                canDelete: true,
                onChange: (d) => setState(() => draft = d),
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );

    // Venue name should be visible.
    expect(find.text('The Blue Note'), findsOneWidget);

    // Tap the Clear venue button (xmark_circle icon).
    final clearBtn = find.byIcon(CupertinoIcons.xmark_circle);
    expect(clearBtn, findsOneWidget);
    await tester.tap(clearBtn);
    await tester.pump();

    // After clearing, the search row reappears and the venue name is gone.
    expect(find.text('The Blue Note'), findsNothing);
    expect(find.text('Search venue'), findsOneWidget);
    expect(draft.venueName, isNull);
  });

  testWidgets('free-text venue selection sets venueName via onChange',
      (tester) async {
    // The fake service returns no predictions, so the search sheet shows the
    // "Use '<query>' as venue name" free-text row — the manual-entry path
    // used for house gigs, small venues, and all of Linux.
    EventDraft draft = const EventDraft(title: 'X', date: '2026-06-13');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          venueSearchServiceProvider
              .overrideWithValue(_FakeVenueSearchService()),
        ],
        child: StatefulBuilder(
          builder: (context, setState) => CupertinoApp(
            home: SingleChildScrollView(
              child: EventSubFormCard(
        bandId: 1,
                draft: draft,
                canDelete: true,
                onChange: (d) => setState(() => draft = d),
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );

    // Open the search sheet from the empty-state row.
    await tester.tap(find.text('Search venue'));
    await tester.pumpAndSettle();

    // Type a venue name that has no autocomplete match.
    await tester.enterText(
        find.byType(CupertinoSearchTextField), "Smith's House Party");
    await tester.pumpAndSettle();

    // Tap the free-text acceptance row.
    await tester.tap(find.textContaining('as venue name'));
    await tester.pumpAndSettle();

    // The free-typed name is stored; address is left null (no map step).
    expect(draft.venueName, "Smith's House Party");
    expect(draft.venueAddress, isNull);
    // The card now shows the selected venue, not the search row.
    expect(find.text("Smith's House Party"), findsOneWidget);
    expect(find.text('Search venue'), findsNothing);
  });
}
