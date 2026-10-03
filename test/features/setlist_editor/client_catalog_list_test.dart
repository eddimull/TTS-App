import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';
import 'package:tts_bandmate/features/setlist_editor/widgets/client_catalog_list.dart';

Widget _wrap(Widget child) => CupertinoApp(
      home: CupertinoPageScaffold(child: child),
    );

const _songs = [
  BandSongSummary(id: 1, title: 'Zebra Song', artist: 'Band Z'),
  BandSongSummary(id: 2, title: 'Apple Song', artist: 'Band A'),
  BandSongSummary(id: 3, title: 'Mango Song', artist: 'Band M'),
];

final _requests = ClientSongRequests(
  mustPlayIds: const {2},
  doNotPlayIds: const {3},
  sourceName: 'Wedding Questionnaire',
  submittedAt: DateTime.utc(2026, 9, 12, 15),
);

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  testWidgets('lists every band song alphabetically', (tester) async {
    await tester.pumpWidget(_wrap(
      ClientCatalogList(songs: _songs, requests: _requests),
    ));

    expect(find.text('Apple Song'), findsOneWidget);
    expect(find.text('Mango Song'), findsOneWidget);
    expect(find.text('Zebra Song'), findsOneWidget);

    final apple = tester.getTopLeft(find.text('Apple Song')).dy;
    final mango = tester.getTopLeft(find.text('Mango Song')).dy;
    final zebra = tester.getTopLeft(find.text('Zebra Song')).dy;
    expect(apple, lessThan(mango));
    expect(mango, lessThan(zebra));
  });

  testWidgets('shows summary header with counts and source', (tester) async {
    await tester.pumpWidget(_wrap(
      ClientCatalogList(songs: _songs, requests: _requests),
    ));

    expect(find.textContaining('1 must play'), findsOneWidget);
    expect(find.textContaining('1 do not play'), findsOneWidget);
    expect(find.textContaining('Wedding Questionnaire'), findsOneWidget);
  });

  testWidgets('header has no stray comma when picks match no listed song',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ClientCatalogList(
        songs: _songs,
        requests: const ClientSongRequests(
          mustPlayIds: {99},
          doNotPlayIds: {},
          sourceName: 'Wedding Questionnaire',
        ),
      ),
    ));

    expect(find.text('from Wedding Questionnaire'), findsOneWidget);
  });

  testWidgets('must-play row shows a star and caption', (tester) async {
    await tester.pumpWidget(_wrap(
      ClientCatalogList(songs: _songs, requests: _requests),
    ));

    expect(find.byIcon(CupertinoIcons.star_fill), findsOneWidget);
    expect(find.text('Must play'), findsOneWidget);
    expect(_styleOf(tester, 'Apple Song').decoration, isNot(TextDecoration.lineThrough));
  });

  testWidgets('do-not-play row is struck through with caption', (tester) async {
    await tester.pumpWidget(_wrap(
      ClientCatalogList(songs: _songs, requests: _requests),
    ));

    expect(_styleOf(tester, 'Mango Song').decoration, TextDecoration.lineThrough);
    expect(_styleOf(tester, 'Band M').decoration, TextDecoration.lineThrough);
    expect(find.text('Do not play'), findsOneWidget);
    // Unflagged song is plain.
    expect(_styleOf(tester, 'Zebra Song').decoration, isNot(TextDecoration.lineThrough));
  });
}
