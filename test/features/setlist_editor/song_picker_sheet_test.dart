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
}) async {
  SongPickerResult? captured;

  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => CupertinoPageScaffold(
          child: CupertinoButton(
            onPressed: () async {
              final result = await showSongPickerSheet(context, songs: songs);
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
      // Song key shown for aSong
      expect(find.text('G'), findsOneWidget);
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

    testWidgets(
        'tapping a song row fires the pick callback with that exact song',
        (tester) async {
      SongPickerResult? result;

      await _pumpSheet(
        tester,
        [_aSong, _bSong],
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('Brown Eyed Girl'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isLibrary, isTrue);
      expect(result!.song?.id, 1);
      expect(result!.song?.title, 'Brown Eyed Girl');
    });

    testWidgets(
        'tapping a second song returns that song (not the first)',
        (tester) async {
      SongPickerResult? result;

      await _pumpSheet(
        tester,
        [_aSong, _bSong],
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('Sweet Home Alabama'));
      await tester.pumpAndSettle();

      expect(result!.song?.id, 2);
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
    test('library result exposes song and isLibrary == true', () {
      const result = SongPickerResult.library(_aSong);
      expect(result.isLibrary, isTrue);
      expect(result.isCustom, isFalse);
      expect(result.song, same(_aSong));
      expect(result.customTitle, isNull);
    });

    test('custom result exposes title and isCustom == true', () {
      const result =
          SongPickerResult.custom(customTitle: 'Foo', customArtist: 'Bar');
      expect(result.isCustom, isTrue);
      expect(result.isLibrary, isFalse);
      expect(result.customTitle, 'Foo');
      expect(result.customArtist, 'Bar');
      expect(result.song, isNull);
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
      const result = SongPickerResult.library(_aSong);
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
