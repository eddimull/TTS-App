import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/event_setlist.dart';
import '../data/setlist_editor_repository.dart';

// ── Generation progress step ─────────────────────────────────────────────────

class GenerationStep {
  const GenerationStep({
    required this.step,
    required this.status,
    this.detail,
  });

  final String step;
  final String status;
  final String? detail;

  GenerationStep copyWith({String? status, String? detail}) => GenerationStep(
        step: step,
        status: status ?? this.status,
        detail: detail ?? this.detail,
      );
}

// ── State ─────────────────────────────────────────────────────────────────────

class SetlistEditorState {
  const SetlistEditorState({
    this.setlist,
    this.bandSongs = const [],
    this.canWrite = false,
    this.isLoading = false,
    this.isSaving = false,
    this.isGenerating = false,
    this.isRefining = false,
    this.isDirty = false,
    this.generationSteps = const [],
    this.error,
  });

  final EventSetlist? setlist;
  final List<BandSongSummary> bandSongs;
  final bool canWrite;
  final bool isLoading;
  final bool isSaving;
  final bool isGenerating;
  final bool isRefining;
  final bool isDirty;
  final List<GenerationStep> generationSteps;
  final String? error;

  // Nullable-wrapper closures only for fields that may be intentionally set to
  // null (setlist, error). Other fields use direct nullable.
  SetlistEditorState copyWith({
    EventSetlist? Function()? setlist,
    List<BandSongSummary>? bandSongs,
    bool? canWrite,
    bool? isLoading,
    bool? isSaving,
    bool? isGenerating,
    bool? isRefining,
    bool? isDirty,
    List<GenerationStep>? generationSteps,
    String? Function()? error,
  }) =>
      SetlistEditorState(
        setlist: setlist != null ? setlist() : this.setlist,
        bandSongs: bandSongs ?? this.bandSongs,
        canWrite: canWrite ?? this.canWrite,
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        isGenerating: isGenerating ?? this.isGenerating,
        isRefining: isRefining ?? this.isRefining,
        isDirty: isDirty ?? this.isDirty,
        generationSteps: generationSteps ?? this.generationSteps,
        error: error != null ? error() : this.error,
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────────

class SetlistEditorNotifier extends Notifier<SetlistEditorState> {
  SetlistEditorNotifier(this._eventKey);
  final String _eventKey;

  SetlistEditorRepository get _repo => ref.read(setlistEditorRepositoryProvider);

  @override
  SetlistEditorState build() => const SetlistEditorState(isLoading: true);

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final payload = await _repo.getSetlist(_eventKey);
      state = state.copyWith(
        setlist: () => payload.setlist,
        bandSongs: payload.bandSongs,
        canWrite: payload.canWrite,
        isLoading: false,
        isDirty: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: () => e.toString(),
      );
    }
  }

  // ── Local edits ──────────────────────────────────────────────────────────────

  void addSong(BandSongSummary song, {String? notes}) {
    final entries = _currentEntries();
    entries.add(SetlistEntry(
      type: 'song',
      position: entries.length + 1,
      songId: song.id,
      title: song.title,
      artist: song.artist,
      songKey: song.songKey,
      genre: song.genre,
      bpm: song.bpm,
      energy: song.energy,
      leadSinger: song.leadSinger,
      notes: notes,
    ));
    _emitEntries(entries);
  }

  void addCustomSong({required String title, String? artist, String? notes}) {
    final entries = _currentEntries();
    entries.add(SetlistEntry(
      type: 'song',
      position: entries.length + 1,
      customTitle: title,
      customArtist: artist,
      title: title,
      artist: artist,
      notes: notes,
    ));
    _emitEntries(entries);
  }

  void addBreak() {
    final entries = _currentEntries();
    entries.add(SetlistEntry(
      type: 'break',
      position: entries.length + 1,
    ));
    _emitEntries(entries);
  }

  void removeAt(int index) {
    final entries = _currentEntries();
    if (index < 0 || index >= entries.length) return;
    entries.removeAt(index);
    _emitEntries(entries);
  }

  void reorder(int oldIndex, int newIndex) {
    final entries = _currentEntries();
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    // ReorderableListView semantics: when moving down, target index shifts.
    if (oldIndex < newIndex) newIndex -= 1;
    final item = entries.removeAt(oldIndex);
    if (newIndex < 0) newIndex = 0;
    if (newIndex > entries.length) newIndex = entries.length;
    entries.insert(newIndex, item);
    _emitEntries(entries);
  }

  void updateEntry(int index, SetlistEntry next) {
    final entries = _currentEntries();
    if (index < 0 || index >= entries.length) return;
    entries[index] = next;
    _emitEntries(entries);
  }

  List<SetlistEntry> _currentEntries() =>
      List<SetlistEntry>.from(state.setlist?.songs ?? const []);

  void _emitEntries(List<SetlistEntry> entries) {
    final renumbered = [
      for (var i = 0; i < entries.length; i++)
        entries[i].copyWith(position: i + 1),
    ];
    final base = state.setlist ??
        const EventSetlist(id: 0, status: 'draft', songs: []);
    state = state.copyWith(
      setlist: () => base.copyWith(songs: renumbered),
      isDirty: true,
    );
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> save({String? status}) async {
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final entries = _currentEntries();
      final saved = await _repo.updateSetlist(_eventKey, entries, status: status);
      state = state.copyWith(
        setlist: () => saved,
        isSaving: false,
        isDirty: false,
      );
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: () => 'Save failed: $e',
      );
    }
  }

  Future<void> markReady() => save(status: 'ready');

  // ── AI generate / refine ──────────────────────────────────────────────────────

  Future<void> generate({String? context}) async {
    state = state.copyWith(
      isGenerating: true,
      generationSteps: const [],
      error: () => null,
    );
    try {
      final setlist = await _repo.generate(_eventKey, context: context);
      state = state.copyWith(
        setlist: () => setlist,
        isGenerating: false,
        isDirty: false,
      );
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: () => 'Generation failed: $e',
      );
    }
  }

  Future<({String summary, bool ok})> refine(
    String message, {
    List<Map<String, String>> history = const [],
  }) async {
    state = state.copyWith(isRefining: true, error: () => null);
    try {
      final result = await _repo.refine(
        _eventKey,
        message: message,
        history: history,
      );
      state = state.copyWith(
        setlist: () => result.setlist,
        isRefining: false,
        isDirty: false,
      );
      return (summary: result.summary, ok: true);
    } catch (e) {
      state = state.copyWith(
        isRefining: false,
        error: () => 'Refine failed: $e',
      );
      return (
        summary: "Sorry, I couldn't refine the setlist. Please try again.",
        ok: false,
      );
    }
  }

  // ── Generation progress (from real-time channel) ────────────────────────────

  void onGenerationProgress(String step, String status, String? detail) {
    final steps = List<GenerationStep>.from(state.generationSteps);
    final index = steps.indexWhere((s) => s.step == step);
    if (index >= 0) {
      steps[index] = steps[index].copyWith(status: status, detail: detail);
    } else {
      steps.add(GenerationStep(step: step, status: status, detail: detail));
    }
    state = state.copyWith(generationSteps: steps);
  }
}

// ── Provider ───────────────────────────────────────────────────────────────────

final setlistEditorProvider =
    NotifierProvider.family<SetlistEditorNotifier, SetlistEditorState, String>(
  (arg) => SetlistEditorNotifier(arg),
);
