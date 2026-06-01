import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';
import 'package:tts_bandmate/features/setlist_editor/data/setlist_editor_repository.dart';
import 'package:tts_bandmate/features/setlist_editor/providers/setlist_editor_provider.dart';

class _FakeRepo extends SetlistEditorRepository {
  _FakeRepo(this._payload, {this.aiThrows = false}) : super(Dio());

  final SetlistEditorPayload _payload;
  final bool aiThrows;
  List<SetlistEntry>? lastSavedEntries;
  String? lastSavedStatus;

  @override
  Future<SetlistEditorPayload> getSetlist(String eventKey) async => _payload;

  @override
  Future<EventSetlist> updateSetlist(
    String eventKey,
    List<SetlistEntry> entries, {
    String? status,
  }) async {
    lastSavedEntries = entries;
    lastSavedStatus = status;
    return EventSetlist(
      id: _payload.setlist?.id ?? 1,
      status: status ?? _payload.setlist?.status ?? 'draft',
      songs: entries,
    );
  }

  @override
  Future<EventSetlist> generate(String eventKey, {String? context}) async {
    if (aiThrows) throw Exception('boom');
    return const EventSetlist(
      id: 1,
      status: 'draft',
      eventContext: 'generated',
      songs: [SetlistEntry(type: 'song', position: 1, songId: 99, title: 'Gen')],
    );
  }

  @override
  Future<RefineResult> refine(
    String eventKey, {
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    if (aiThrows) throw Exception('boom');
    return const RefineResult(
      setlist: EventSetlist(
        id: 1,
        status: 'draft',
        songs: [SetlistEntry(type: 'song', position: 1, songId: 5, title: 'Refined')],
      ),
      summary: 'Did the thing.',
    );
  }
}

ProviderContainer _container(_FakeRepo repo) {
  return ProviderContainer(overrides: [
    setlistEditorRepositoryProvider.overrideWithValue(repo),
  ]);
}

void main() {
  test('load fetches setlist and exposes can_write', () async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(
        id: 1,
        status: 'draft',
        songs: [SetlistEntry(type: 'song', position: 1, songId: 10, title: 'A')],
      ),
      bandSongs: [BandSongSummary(id: 10, title: 'A')],
      canWrite: true,
    ));
    final container = _container(repo);
    addTearDown(container.dispose);

    await container.read(setlistEditorProvider('event-key').notifier).load();

    final state = container.read(setlistEditorProvider('event-key'));
    expect(state.canWrite, true);
    expect(state.setlist?.songs.length, 1);
    expect(state.isLoading, false);
  });

  test('addSong appends entry locally without saving and sets dirty', () async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(id: 1, status: 'draft', songs: []),
      bandSongs: [BandSongSummary(id: 10, title: 'A')],
      canWrite: true,
    ));
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(setlistEditorProvider('event-key').notifier);
    await notifier.load();
    notifier.addSong(const BandSongSummary(id: 10, title: 'A'));

    expect(container.read(setlistEditorProvider('event-key')).setlist!.songs.length, 1);
    expect(repo.lastSavedEntries, isNull); // not auto-saved
    expect(container.read(setlistEditorProvider('event-key')).isDirty, true);
  });

  test('reorder updates order and renumbers positions', () async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(
        id: 1,
        status: 'draft',
        songs: [
          SetlistEntry(type: 'song', position: 1, songId: 1, title: 'A'),
          SetlistEntry(type: 'song', position: 2, songId: 2, title: 'B'),
          SetlistEntry(type: 'song', position: 3, songId: 3, title: 'C'),
        ],
      ),
      bandSongs: [],
      canWrite: true,
    ));
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(setlistEditorProvider('event-key').notifier);
    await notifier.load();
    notifier.reorder(0, 2); // move A after B (ReorderableListView semantics)

    final songs = container.read(setlistEditorProvider('event-key')).setlist!.songs;
    expect(songs.map((s) => s.title).toList(), ['B', 'A', 'C']);
    expect(songs.map((s) => s.position).toList(), [1, 2, 3]);
    expect(container.read(setlistEditorProvider('event-key')).isDirty, true);
  });

  test('removeAt deletes the entry and renumbers', () async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(
        id: 1,
        status: 'draft',
        songs: [
          SetlistEntry(type: 'song', position: 1, songId: 1, title: 'A'),
          SetlistEntry(type: 'song', position: 2, songId: 2, title: 'B'),
        ],
      ),
      bandSongs: [],
      canWrite: true,
    ));
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(setlistEditorProvider('event-key').notifier);
    await notifier.load();
    notifier.removeAt(0);

    final songs = container.read(setlistEditorProvider('event-key')).setlist!.songs;
    expect(songs.map((s) => s.title).toList(), ['B']);
    expect(songs.first.position, 1);
  });

  test('save calls repo and clears dirty', () async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(id: 1, status: 'draft', songs: []),
      bandSongs: [],
      canWrite: true,
    ));
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(setlistEditorProvider('event-key').notifier);
    await notifier.load();
    notifier.addBreak();
    await notifier.save();

    expect(repo.lastSavedEntries!.length, 1);
    expect(container.read(setlistEditorProvider('event-key')).isDirty, false);
  });

  test('onGenerationProgress accumulates and updates steps by name', () async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(id: 1, status: 'draft', songs: []),
      bandSongs: [],
      canWrite: true,
    ));
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(setlistEditorProvider('event-key').notifier);
    await notifier.load();
    notifier.onGenerationProgress('analyze', 'in-progress', null);
    notifier.onGenerationProgress('analyze', 'done', 'ok');

    final steps = container.read(setlistEditorProvider('event-key')).generationSteps;
    expect(steps.length, 1); // same step name updated in place
    expect(steps.first.status, 'done');
  });

  test('load failure clears loading and sets error', () async {
    final repo = _ThrowingLoadRepo();
    final container = ProviderContainer(overrides: [
      setlistEditorRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await container.read(setlistEditorProvider('event-key').notifier).load();

    final state = container.read(setlistEditorProvider('event-key'));
    expect(state.isLoading, false);
    expect(state.error, isNotNull);
  });

  test('addCustomSong adds a custom entry', () async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(id: 1, status: 'draft', songs: []),
      bandSongs: [],
      canWrite: true,
    ));
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(setlistEditorProvider('event-key').notifier);
    await notifier.load();
    notifier.addCustomSong(title: 'Garage Anthem', artist: 'Us');

    final entry = container.read(setlistEditorProvider('event-key')).setlist!.songs.single;
    expect(entry.isCustom, true);
    expect(entry.songId, isNull);
    expect(entry.customTitle, 'Garage Anthem');
  });

  test('reorder does not mutate the previous state list', () async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(
        id: 1,
        status: 'draft',
        songs: [
          SetlistEntry(type: 'song', position: 1, songId: 1, title: 'A'),
          SetlistEntry(type: 'song', position: 2, songId: 2, title: 'B'),
        ],
      ),
      bandSongs: [],
      canWrite: true,
    ));
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(setlistEditorProvider('event-key').notifier);
    await notifier.load();
    final before = container.read(setlistEditorProvider('event-key')).setlist!.songs;
    notifier.reorder(0, 2);

    // The captured reference must be unchanged (immutability guard).
    expect(before.map((s) => s.title).toList(), ['A', 'B']);
  });

  test('generate success updates setlist and clears generating', () async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(id: 1, status: 'draft', songs: []),
      bandSongs: [],
      canWrite: true,
    ));
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(setlistEditorProvider('event-key').notifier);
    await notifier.load();
    await notifier.generate(context: 'go');

    final state = container.read(setlistEditorProvider('event-key'));
    expect(state.isGenerating, false);
    expect(state.isDirty, false);
    expect(state.setlist!.songs.single.title, 'Gen');
  });

  test('generate failure clears generating and steps', () async {
    final repo = _FakeRepo(
      const SetlistEditorPayload(
        setlist: EventSetlist(id: 1, status: 'draft', songs: []),
        bandSongs: [],
        canWrite: true,
      ),
      aiThrows: true,
    );
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(setlistEditorProvider('event-key').notifier);
    await notifier.load();
    notifier.onGenerationProgress('analyze', 'in-progress', null);
    await notifier.generate();

    final state = container.read(setlistEditorProvider('event-key'));
    expect(state.isGenerating, false);
    expect(state.generationSteps, isEmpty); // ghost steps cleared
    expect(state.error, isNotNull);
  });

  test('refine success returns ok and updates setlist', () async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(id: 1, status: 'draft', songs: []),
      bandSongs: [],
      canWrite: true,
    ));
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(setlistEditorProvider('event-key').notifier);
    await notifier.load();
    final result = await notifier.refine('shorter');

    expect(result.ok, true);
    expect(result.summary, 'Did the thing.');
    final state = container.read(setlistEditorProvider('event-key'));
    expect(state.isRefining, false);
    expect(state.setlist!.songs.single.title, 'Refined');
  });

  test('refine failure returns ok:false without setting state.error', () async {
    final repo = _FakeRepo(
      const SetlistEditorPayload(
        setlist: EventSetlist(id: 1, status: 'draft', songs: []),
        bandSongs: [],
        canWrite: true,
      ),
      aiThrows: true,
    );
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(setlistEditorProvider('event-key').notifier);
    await notifier.load();
    final result = await notifier.refine('shorter');

    expect(result.ok, false);
    final state = container.read(setlistEditorProvider('event-key'));
    expect(state.isRefining, false);
    expect(state.error, isNull); // refine errors go to the returned record, not state
  });
}

class _ThrowingLoadRepo extends SetlistEditorRepository {
  _ThrowingLoadRepo() : super(Dio());

  @override
  Future<SetlistEditorPayload> getSetlist(String eventKey) async =>
      throw Exception('network down');
}
