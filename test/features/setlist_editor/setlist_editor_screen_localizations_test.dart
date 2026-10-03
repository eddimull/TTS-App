import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';
import 'package:tts_bandmate/features/setlist_editor/data/setlist_editor_repository.dart';
import 'package:tts_bandmate/features/setlist_editor/screens/setlist_editor_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _Repo extends SetlistEditorRepository {
  _Repo() : super(Dio());

  @override
  Future<SetlistEditorPayload> getSetlist(String eventKey) async =>
      const SetlistEditorPayload(
        setlist: EventSetlist(
          id: 1,
          status: 'draft',
          songs: [
            SetlistEntry(type: 'song', position: 1, songId: 10, title: 'Alpha'),
          ],
        ),
        bandSongs: [],
        canWrite: true,
      );
}

class _Band extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

void main() {
  // The real app is a plain CupertinoApp with no Material localizations
  // (see app.dart). ReorderableListView needs them, so the editor must
  // supply its own or it red-screens as soon as the setlist has a row.
  testWidgets('renders a populated setlist inside a bare CupertinoApp',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        setlistEditorRepositoryProvider.overrideWithValue(_Repo()),
        selectedBandProvider.overrideWith(_Band.new),
      ],
      child: const CupertinoApp(
        home: SetlistEditorScreen(eventKey: 'k'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Alpha'), findsOneWidget);
  });
}
