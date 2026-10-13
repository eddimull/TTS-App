import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';
import 'package:tts_bandmate/features/setlist_editor/widgets/song_picker_sheet.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Wraps the given widget in a CupertinoApp so that CupertinoColors.resolveFrom
/// has a live BuildContext with a proper Brightness, matching how the sheet
/// behaves in production.
Widget _app(Widget child) => CupertinoApp(home: child);

/// Pump the sheet inside a CupertinoApp + Scaffold so that Navigator.pop
/// works (showCupertinoModalPopup requires a Navigator in the tree).
Future<void> _pumpSheet(
  WidgetTester tester,
  List<BandSongSummary> songs, {
  void Function(SongPickerResult)? onResult,
  Set<int> onSetlistIds = const {},
}) async {
  SongPickerResult? captured;

  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => CupertinoPageScaffold(
          child: CupertinoButton(
            onPressed: () async {
              final result = await showSongPickerSheet(
                context,
                songs: songs,
                onSetlistIds: onSetlistIds,
              );
              if (result != null) {
                captured = result;
                onResult?.call(result);
              }
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );

  // Tap to open the sheet.
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  // captured is used only when onResult is provided; declared to allow
  // the widget tree closure to write into it.
  assert(captured == null || captured != null);
}

/// Sample songs used across tests.
const _aSong = BandSongSummary(
  id: 1,
  title: 'Brown Eyed Girl',
  artist: 'Van Morrison',
  songKey: 'G',
  leadSinger: 'Eddie',
);
const _bSong = BandSongSummary(
  id: 2,
  title: 'Sweet Home Alabama',
  artist: 'Lynyrd Skynyrd',
);
const _cSong = BandSongSummary(
  id: 3,
  title: 'Piano Man',
  artist: 'Billy Joel',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SongPickerSheet — library list', () {
    testWidgets('renders all provided songs on open', (tester) async {
      await _pumpSheet(tester, [_aSong, _bSong, _cSong]);

      expect(find.text('Brown Eyed Girl'), findsOneWidget);
      expect(find.text('Van Morrison'), findsOneWidget);
      expect(find.text('Sweet Home Alabama'), findsOneWidget);
      expect(find.text('Piano Man'), findsOneWidget);
      // Lead singer shown instead of the song key.
      expect(find.text('Eddie'), findsOneWidget);
      expect(find.text('G'), findsNothing);
    });

    testWidgets('shows empty-library message when songs list is empty',
        (tester) async {
      await _pumpSheet(tester, []);

      expect(find.text('No songs in the library yet.'), findsOneWidget);
    });

    testWidgets('typing in the search field filters by title', (tester) async {
      await _pumpSheet(tester, [_aSong, _bSong, _cSong]);

      await tester.enterText(
          find.byType(CupertinoSearchTextField), 'brown');
      await tester.pump();

      expect(find.text('Brown Eyed Girl'), findsOneWidget);
      // Other songs should be gone after filtering.
      expect(find.text('Sweet Home Alabama'), findsNothing);
      expect(find.text('Piano Man'), findsNothing);
    });

    testWidgets('typing in the search field filters by artist', (tester) async {
      await _pumpSheet(tester, [_aSong, _bSong, _cSong]);

      await tester.enterText(
          find.byType(CupertinoSearchTextField), 'joel');
      await tester.pump();

      expect(find.text('Piano Man'), findsOneWidget);
      expect(find.text('Brown Eyed Girl'), findsNothing);
      expect(find.text('Sweet Home Alabama'), findsNothing);
    });

    testWidgets(
        'shows no-results message when search query matches nothing',
        (tester) async {
      await _pumpSheet(tester, [_aSong, _bSong]);

      await tester.enterText(
          find.byType(CupertinoSearchTextField), 'zzz_notareal_song');
      await tester.pump();

      expect(find.textContaining('No songs match your search'), findsOneWidget);
    });

    testWidgets('tapping a song selects it instead of closing the sheet',
        (tester) async {
      SongPickerResult? result;
      await _pumpSheet(tester, [_aSong, _bSong], onResult: (r) => result = r);

      await tester.tap(find.text('Brown Eyed Girl'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.text('Pick Songs'), findsOneWidget);
      expect(find.text('Add 1 Song'), findsOneWidget);
    });

    testWidgets('confirming returns every selected song in tap order',
        (tester) async {
      SongPickerResult? result;
      await _pumpSheet(tester, [_aSong, _bSong, _cSong],
          onResult: (r) => result = r);

      await tester.tap(find.text('Piano Man'));
      await tester.tap(find.text('Brown Eyed Girl'));
      await tester.pump();

      await tester.tap(find.text('Add 2 Songs'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isLibrary, isTrue);
      expect(result!.songs.map((s) => s.id), [3, 1]);
    });

    testWidgets('tapping a selected song again deselects it', (tester) async {
      SongPickerResult? result;
      await _pumpSheet(tester, [_aSong, _bSong], onResult: (r) => result = r);

      await tester.tap(find.text('Brown Eyed Girl'));
      await tester.tap(find.text('Sweet Home Alabama'));
      await tester.tap(find.text('Brown Eyed Girl'));
      await tester.pump();

      await tester.tap(find.text('Add 1 Song'));
      await tester.pumpAndSettle();

      expect(result!.songs.map((s) => s.id), [2]);
    });

    testWidgets('selection survives changing the search query',
        (tester) async {
      SongPickerResult? result;
      await _pumpSheet(tester, [_aSong, _bSong, _cSong],
          onResult: (r) => result = r);

      final search = find.byType(CupertinoSearchTextField);
      await tester.enterText(search, 'brown');
      await tester.pump();
      await tester.tap(find.text('Brown Eyed Girl'));
      await tester.enterText(search, 'piano');
      await tester.pump();
      await tester.tap(find.text('Piano Man'));
      await tester.pump();

      await tester.tap(find.text('Add 2 Songs'));
      await tester.pumpAndSettle();

      expect(result!.songs.map((s) => s.id), [1, 3]);
    });

    testWidgets('add button is disabled until a song is selected',
        (tester) async {
      await _pumpSheet(tester, [_aSong]);

      final button = tester.widget<CupertinoButton>(find.ancestor(
        of: find.text('Select Songs'),
        matching: find.byType(CupertinoButton),
      ));
      expect(button.onPressed, isNull);
    });

    testWidgets('marks songs already on the setlist', (tester) async {
      await _pumpSheet(tester, [_aSong, _bSong], onSetlistIds: {2});

      expect(find.text('On setlist'), findsOneWidget);
      // Still selectable (e.g. for a reprise).
      await tester.tap(find.text('Sweet Home Alabama'));
      await tester.pump();
      expect(find.text('Add 1 Song'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------

  group('SongPickerSheet — custom mode', () {
    testWidgets('switching to Custom mode shows the text fields',
        (tester) async {
      await _pumpSheet(tester, [_aSong]);

      // Tap the "Custom" toggle button in the header.
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      // The sheet header should now read "Add Custom Song".
      expect(find.text('Add Custom Song'), findsOneWidget);
      // Both text fields should be present.
      expect(
          find.widgetWithText(CupertinoTextField, 'Song title'), findsOneWidget);
      expect(
          find.widgetWithText(CupertinoTextField, 'Artist (optional)'),
          findsOneWidget);
      // "Add Song" button should be present (but disabled until title filled).
      expect(find.text('Add Song'), findsOneWidget);
    });

    testWidgets('Add Song button is disabled when title is empty',
        (tester) async {
      await _pumpSheet(tester, []);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      // Find the CupertinoButton for "Add Song" and confirm it has no onPressed.
      final buttons = tester.widgetList<CupertinoButton>(
        find.ancestor(
          of: find.text('Add Song'),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(buttons.any((b) => b.onPressed == null), isTrue);
    });

    testWidgets(
        'entering a title enables Add Song; tapping it fires custom callback',
        (tester) async {
      SongPickerResult? result;

      await _pumpSheet(tester, [], onResult: (r) => result = r);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Song title'),
          'My Original Song');
      await tester.pump();

      // Button should now be enabled.
      final buttons = tester.widgetList<CupertinoButton>(
        find.ancestor(
          of: find.text('Add Song'),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(buttons.any((b) => b.onPressed != null), isTrue);

      await tester.tap(find.text('Add Song'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isCustom, isTrue);
      expect(result!.customTitle, 'My Original Song');
      expect(result!.customArtist, isNull);
    });

    testWidgets(
        'entering title + artist fires custom callback with both fields',
        (tester) async {
      SongPickerResult? result;

      await _pumpSheet(tester, [], onResult: (r) => result = r);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Song title'), 'Jambalaya');
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Artist (optional)'),
          'Hank Williams');
      await tester.pump();

      await tester.tap(find.text('Add Song'));
      await tester.pumpAndSettle();

      expect(result!.customTitle, 'Jambalaya');
      expect(result!.customArtist, 'Hank Williams');
    });

    testWidgets('toggling back to library shows the song list again',
        (tester) async {
      await _pumpSheet(tester, [_aSong]);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      expect(find.text('Brown Eyed Girl'), findsNothing);

      // "From Library" is the toggle label in custom mode.
      await tester.tap(find.text('From Library'));
      await tester.pumpAndSettle();

      expect(find.text('Brown Eyed Girl'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------

  group('SongPickerResult', () {
    test('library result exposes songs and isLibrary == true', () {
      const result = SongPickerResult.library([_aSong, _bSong]);
      expect(result.isLibrary, isTrue);
      expect(result.isCustom, isFalse);
      expect(result.songs, [_aSong, _bSong]);
      expect(result.customTitle, isNull);
    });

    test('custom result exposes title and isCustom == true', () {
      const result =
          SongPickerResult.custom(customTitle: 'Foo', customArtist: 'Bar');
      expect(result.isCustom, isTrue);
      expect(result.isLibrary, isFalse);
      expect(result.customTitle, 'Foo');
      expect(result.customArtist, 'Bar');
      expect(result.songs, isEmpty);
    });

    test('custom result with null artist is allowed', () {
      const result = SongPickerResult.custom(customTitle: 'Solo Track');
      expect(result.customArtist, isNull);
    });

    test('custom result carries notes when provided', () {
      const result = SongPickerResult.custom(
        customTitle: 'Improv Jam',
        notes: 'Start quiet, build to full band',
      );
      expect(result.isCustom, isTrue);
      expect(result.notes, 'Start quiet, build to full band');
    });

    test('library result notes is null by default', () {
      const result = SongPickerResult.library([_aSong]);
      expect(result.notes, isNull);
    });
  });

  // ---------------------------------------------------------------------------

  group('SongPickerSheet — notes field in custom mode', () {
    testWidgets(
        'entering notes in custom mode returns them on the result',
        (tester) async {
      SongPickerResult? result;

      await _pumpSheet(tester, [], onResult: (r) => result = r);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Song title'),
          'Freebird');
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Notes (optional)'),
          'Long outro — cue drummer');
      await tester.pump();

      await tester.tap(find.text('Add Song'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isCustom, isTrue);
      expect(result!.customTitle, 'Freebird');
      expect(result!.notes, 'Long outro — cue drummer');
    });

    testWidgets(
        'leaving notes blank returns null notes on the result',
        (tester) async {
      SongPickerResult? result;

      await _pumpSheet(tester, [], onResult: (r) => result = r);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Song title'),
          'Unnamed Track');
      await tester.pump();

      // Notes field left empty — no interaction.

      await tester.tap(find.text('Add Song'));
      await tester.pumpAndSettle();

      expect(result!.notes, isNull);
    });
  });
}
