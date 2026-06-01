import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';
import 'package:tts_bandmate/features/setlist_editor/widgets/setlist_row.dart';

// Minimal test harness — wraps the widget under test in a CupertinoApp so
// that CupertinoColors.resolveFrom() can resolve against a real Brightness.
Widget _wrap(Widget child) => CupertinoApp(
      home: CupertinoPageScaffold(child: child),
    );

SetlistEntry _songEntry({
  int id = 1,
  String title = 'Brown Eyed Girl',
  String artist = 'Van Morrison',
  String? songKey = 'G',
  int? bpm = 148,
  String? leadSinger = 'Eddie',
  String? notes,
}) =>
    SetlistEntry(
      id: id,
      type: 'song',
      position: 1,
      songId: 42,
      title: title,
      artist: artist,
      songKey: songKey,
      bpm: bpm,
      leadSinger: leadSinger,
      notes: notes,
    );

void main() {
  group('SetlistSongRow', () {
    testWidgets('renders title, artist, and BPM tag for a populated song entry',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SetlistSongRow(
          entry: _songEntry(),
          songNumber: 1,
          canWrite: false,
          onEdit: () {},
          onRemove: () {},
        ),
      ));

      expect(find.text('Brown Eyed Girl'), findsOneWidget);
      expect(find.text('Van Morrison'), findsOneWidget);
      // BPM tag text
      expect(find.text('148 BPM'), findsOneWidget);
    });

    testWidgets(
        'hides edit and remove buttons when canWrite is false',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SetlistSongRow(
          entry: _songEntry(),
          songNumber: 1,
          canWrite: false,
          onEdit: () {},
          onRemove: () {},
        ),
      ));

      expect(find.byIcon(CupertinoIcons.pencil), findsNothing);
      expect(find.byIcon(CupertinoIcons.delete), findsNothing);
    });

    testWidgets(
        'shows edit and remove buttons when canWrite is true and callbacks fire',
        (tester) async {
      var editCount = 0;
      var removeCount = 0;

      await tester.pumpWidget(_wrap(
        SetlistSongRow(
          entry: _songEntry(),
          songNumber: 1,
          canWrite: true,
          onEdit: () => editCount++,
          onRemove: () => removeCount++,
        ),
      ));

      expect(find.byIcon(CupertinoIcons.pencil), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.delete), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.pencil));
      await tester.tap(find.byIcon(CupertinoIcons.delete));

      expect(editCount, 1);
      expect(removeCount, 1);
    });

    testWidgets('renders notes text when notes are present', (tester) async {
      await tester.pumpWidget(_wrap(
        SetlistSongRow(
          entry: _songEntry(notes: 'Client request — play longer'),
          songNumber: 2,
          canWrite: false,
          onEdit: () {},
          onRemove: () {},
        ),
      ));

      expect(find.text('Client request — play longer'), findsOneWidget);
    });

    testWidgets('does not render notes section when notes are absent',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SetlistSongRow(
          entry: _songEntry(notes: null),
          songNumber: 2,
          canWrite: false,
          onEdit: () {},
          onRemove: () {},
        ),
      ));

      // Only title + artist texts should be present; no extra text widget.
      expect(find.text('Client request — play longer'), findsNothing);
    });
  });

  group('SetlistBreakRow', () {
    testWidgets(
        'renders SET BREAK label and fires onRemove when delete button tapped',
        (tester) async {
      var removeCalled = false;

      await tester.pumpWidget(_wrap(
        SetlistBreakRow(
          canWrite: true,
          onRemove: () => removeCalled = true,
        ),
      ));

      expect(find.text('— SET BREAK —'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.pause_circle), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.delete));
      expect(removeCalled, isTrue);
    });

    testWidgets('hides remove button when canWrite is false', (tester) async {
      await tester.pumpWidget(_wrap(
        SetlistBreakRow(
          canWrite: false,
          onRemove: () {},
        ),
      ));

      expect(find.text('— SET BREAK —'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.delete), findsNothing);
    });
  });
}
