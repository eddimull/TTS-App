import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/pusher_connection.dart';
import '../../../core/providers/core_providers.dart';
import '../../../shared/cache/api_cache_storage.dart';
import '../../../shared/cache/swr.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/band_song.dart';
import '../data/models/live_session.dart';
import '../data/models/client_notes.dart';
import '../data/models/live_suggestion.dart';
import '../data/models/queue_entry.dart';
import '../data/setlist_repository.dart';
import '../../setlist_editor/data/models/event_setlist.dart'
    show ClientSongRequests;

// ── State ──────────────────────────────────────────────────────────────────────

class LiveSessionState {
  const LiveSessionState({
    this.session,
    this.songs = const [],
    this.isCaptain = false,
    this.canWrite = false,
    this.currentUserId = 0,
    this.isLoading = false,
    this.error,
    this.clientRequests,
    this.clientNotes,
    this.suggestion,
    this.isSuggesting = false,
    this.suggestionError,
  });

  final LiveSession? session;
  final List<BandSong> songs;
  final bool isCaptain;
  final bool canWrite;
  final int currentUserId;
  final bool isLoading;
  final String? error;

  /// Client must-play / do-not-play picks from submitted questionnaires.
  final ClientSongRequests? clientRequests;

  /// The questionnaire's free text as read by the AI: requests (in or out
  /// of the catalog), per-song notes, rules and crowd.
  final ClientNotes? clientNotes;

  /// Catalog songs the client must hear — song pickers plus free text.
  Set<int> get mustPlayIds => {
        ...?clientRequests?.mustPlayIds,
        ...?clientNotes?.idsOf(
            {ClientRequestKind.mustPlay, ClientRequestKind.specialMoment}),
      }.difference(doNotPlayIds);

  Set<int> get ifTimeIds =>
      (clientNotes?.idsOf({ClientRequestKind.ifTime}) ?? const <int>{})
          .difference({...mustPlayIds, ...doNotPlayIds});

  Set<int> get doNotPlayIds => {
        ...?clientRequests?.doNotPlayIds,
        ...?clientNotes?.idsOf({ClientRequestKind.doNotPlay}),
      };

  /// The AI's current "play next" pick, shown until queued or dismissed.
  final LiveSuggestion? suggestion;
  final bool isSuggesting;
  final String? suggestionError;

  bool get hasActiveSession => session != null && !session!.isCompleted;

  // Use nullable-wrapper closures only for fields that may be intentionally
  // set to null (session, error). For bool/int fields use direct nullable.
  LiveSessionState copyWith({
    LiveSession? Function()? session,
    List<BandSong>? songs,
    bool? isCaptain,
    bool? canWrite,
    int? currentUserId,
    bool? isLoading,
    String? Function()? error,
    ClientSongRequests? Function()? clientRequests,
    ClientNotes? Function()? clientNotes,
    LiveSuggestion? Function()? suggestion,
    bool? isSuggesting,
    String? Function()? suggestionError,
  }) =>
      LiveSessionState(
        session: session != null ? session() : this.session,
        songs: songs ?? this.songs,
        isCaptain: isCaptain ?? this.isCaptain,
        canWrite: canWrite ?? this.canWrite,
        currentUserId: currentUserId ?? this.currentUserId,
        isLoading: isLoading ?? this.isLoading,
        error: error != null ? error() : this.error,
        clientRequests:
            clientRequests != null ? clientRequests() : this.clientRequests,
        clientNotes: clientNotes != null ? clientNotes() : this.clientNotes,
        suggestion: suggestion != null ? suggestion() : this.suggestion,
        isSuggesting: isSuggesting ?? this.isSuggesting,
        suggestionError:
            suggestionError != null ? suggestionError() : this.suggestionError,
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────────

class LiveSessionNotifier extends Notifier<LiveSessionState> {
  LiveSessionNotifier(this._eventKey);
  final String _eventKey;
  SetlistRepository? _repo;

  @override
  LiveSessionState build() {
    ref.onDispose(_disconnect);
    return const LiveSessionState(isLoading: true);
  }

  SetlistRepository get _repository {
    _repo ??= SetlistRepository(ref.read(apiClientProvider).dio);
    return _repo!;
  }

  // ── Initialise ─────────────────────────────────────────────────────────────

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: () => null);
    final bandId = ref.read(selectedBandProvider).value;
    final cacheKey =
        bandId == null ? null : '$bandId:setlist_session:$_eventKey';
    final cache = ref.read(apiCacheStorageProvider);
    try {
      final result = await _repository.getSessionRaw(_eventKey);
      if (cacheKey != null) cache.write(cacheKey, result.raw);
      state = state.copyWith(
        session: () => result.session,
        songs: result.songs,
        isCaptain: result.isCaptain,
        canWrite: result.canWrite,
        currentUserId: result.currentUserId,
        clientRequests: () => result.clientRequests,
        clientNotes: () => result.clientNotes,
        isLoading: false,
      );

      if (result.session != null) {
        await _connectPusher(result.session!.id);
      }
    } catch (e) {
      // Offline fallback: paint the cached song list read-only so the band
      // can still see the set with no signal. Controls stay disabled
      // (isCaptain/canWrite false) — session actions are server-driven, and
      // no Pusher connect is attempted.
      final cached = cacheKey == null ? null : cache.read(cacheKey);
      if (cached != null && isOfflineError(e)) {
        final parsed = SetlistRepository.parseSession(cached.payload);
        state = state.copyWith(
          session: () => parsed.session,
          songs: parsed.songs,
          isCaptain: false,
          canWrite: false,
          currentUserId: parsed.currentUserId,
          clientRequests: () => parsed.clientRequests,
          clientNotes: () => parsed.clientNotes,
          isLoading: false,
          error: () => null,
        );
        return;
      }
      state = state.copyWith(
        isLoading: false,
        error: () => isOfflineError(e) ? kOfflineMessage : e.toString(),
      );
    }
  }

  // ── Session lifecycle ──────────────────────────────────────────────────────

  Future<void> startSession() async {
    state = state.copyWith(isLoading: true);
    try {
      final session = await _repository.startSession(_eventKey);
      state = state.copyWith(
        session: () => session,
        isCaptain: true,
        isLoading: false,
      );
      await _connectPusher(session.id);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: () => 'Failed to start session: $e',
      );
    }
  }

  Future<void> endSession() async {
    try {
      await _repository.endSession(_eventKey);
      await _disconnect();
      state = state.copyWith(
        session: () => state.session?.copyWith(status: 'completed'),
      );
    } catch (e) {
      state = state.copyWith(error: () => 'Failed to end session: $e');
    }
  }

  // ── Captain actions ────────────────────────────────────────────────────────

  Future<void> next() async {
    final session = state.session;
    if (session == null) return;
    try {
      await _repository.next(session.id);
      await _resync();
    } catch (e) {
      state = state.copyWith(error: () => 'Error: $e');
    }
  }

  Future<void> skip() async {
    final session = state.session;
    if (session == null) return;
    try {
      await _repository.skip(session.id);
      await _resync();
    } catch (e) {
      state = state.copyWith(error: () => 'Error: $e');
    }
  }

  Future<void> skipRemove() async {
    final session = state.session;
    if (session == null) return;
    try {
      await _repository.skipRemove(session.id);
      await _resync();
    } catch (e) {
      state = state.copyWith(error: () => 'Error: $e');
    }
  }

  /// Records the crowd's reaction to a song. Tapping the reaction it
  /// already has clears it. Shown immediately; the resync confirms.
  Future<void> react(int queueEntryId, String reaction) async {
    final session = state.session;
    if (session == null) return;
    final entry = session.queue.where((e) => e.id == queueEntryId).firstOrNull;
    final next = entry?.crowdReaction == reaction ? 'neutral' : reaction;
    state = state.copyWith(
      session: () => session.copyWith(queue: [
        for (final e in session.queue)
          e.id == queueEntryId
              ? e.copyWith(
                  crowdReaction: () => next == 'neutral' ? null : next)
              : e,
      ]),
    );
    try {
      await _repository.react(session.id, queueEntryId, next);
    } catch (e) {
      state = state.copyWith(error: () => 'Error: $e');
    }
    await _resync();
  }

  /// Queues [songIds] in the given order. When nothing is playing (an empty
  /// pick-as-you-go session, or the queue ran out) the first one starts
  /// playing immediately — otherwise it would sit in "Up next" with no Next
  /// button to reach it.
  ///
  /// Pick-as-you-go sessions append to the end of the queue, so tapping songs
  /// one after another builds the set in tap order. Sessions running a
  /// prepared setlist slot picks in right after the current song instead, so
  /// a request doesn't land behind the rest of the set.
  Future<void> addSongs(List<int> songIds) async {
    final session = state.session;
    if (session == null) return;
    // A song can only be in a session once — drop anything already queued
    // or played (stale picker, double tap).
    final taken = {
      for (final e in session.queue)
        if (e.songId != null && (e.isPending || e.isPlayed)) e.songId!,
      // The client asked us not to play these.
      ...state.doNotPlayIds,
    };
    songIds = [
      for (final id in songIds.toSet())
        if (!taken.contains(id)) id,
    ];
    if (songIds.isEmpty) return;
    var rest = songIds;
    try {
      if (session.isActive && session.currentSong == null) {
        await _repository.addOffSetlist(session.id, songIds.first,
            appendToEnd: session.isDynamic);
        await _repository.next(session.id);
        rest = songIds.sublist(1);
      }
      if (session.isDynamic) {
        for (final id in rest) {
          await _repository.addOffSetlist(session.id, id, appendToEnd: true);
        }
      } else {
        // The server inserts each song directly after the current one, so
        // add in reverse to end up in the order the captain picked them.
        for (final id in rest.reversed) {
          await _repository.addOffSetlist(session.id, id);
        }
      }
    } catch (e) {
      state = state.copyWith(error: () => 'Failed to add song: $e');
    }
    // Resync even after a partial failure so the screen shows what landed.
    await _resync();
  }

  Future<void> addOffSetlist(int songId) => addSongs([songId]);

  /// Removes an upcoming song. Drops it from the local queue first so a
  /// swiped row disappears immediately; the resync restores it if the
  /// server refused.
  Future<void> removeUpcoming(int queueEntryId) async {
    final session = state.session;
    if (session == null) return;
    state = state.copyWith(
      session: () => session.copyWith(
        queue: [
          for (final e in session.queue)
            if (e.id != queueEntryId) e,
        ],
      ),
    );
    try {
      await _repository.removeUpcoming(session.id, queueEntryId);
    } catch (e) {
      state = state.copyWith(error: () => 'Failed to remove song: $e');
    }
    await _resync();
  }

  /// Moves the upcoming entry at [oldIndex] to [newIndex] (indices into the
  /// upcoming list as shown, ReorderableList semantics). Applied locally
  /// first so the drop sticks; the resync corrects it if the server refused.
  Future<void> reorderUpcoming(int oldIndex, int newIndex) async {
    final session = state.session;
    if (session == null) return;
    final upcoming = session.upcoming;
    if (oldIndex < 0 || oldIndex >= upcoming.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;

    final reordered = [...upcoming];
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    // The entries trade places within the same set of positions.
    final newPosition = {
      for (var i = 0; i < reordered.length; i++)
        reordered[i].id: upcoming[i].position,
    };
    state = state.copyWith(
      session: () => session.copyWith(
        queue: [
          for (final e in session.queue)
            newPosition.containsKey(e.id)
                ? e.copyWith(position: newPosition[e.id])
                : e,
        ],
      ),
    );
    try {
      await _repository.reorderUpcoming(
          session.id, [for (final e in reordered) e.id]);
    } catch (e) {
      state = state.copyWith(error: () => 'Failed to reorder: $e');
    }
    await _resync();
  }

  /// Queues a client request that isn't in the band's catalog, by title.
  /// Same placement rules as [addSongs]; starts it if nothing is playing.
  Future<void> addCustomSong(String title, {String? artist}) async {
    final session = state.session;
    if (session == null) return;
    final t = title.trim().toLowerCase();
    final already = session.queue.any((e) =>
        e.songId == null &&
        (e.isPending || e.isPlayed) &&
        (e.title ?? '').trim().toLowerCase() == t);
    if (already) return;
    final playNow = session.isActive && session.currentSong == null;
    try {
      await _repository.addOffSetlist(
        session.id,
        null,
        customTitle: title,
        customArtist: artist,
        appendToEnd: session.isDynamic || playNow,
      );
      if (playNow) await _repository.next(session.id);
    } catch (e) {
      state = state.copyWith(error: () => 'Failed to add song: $e');
    }
    await _resync();
  }

  // ── AI suggestions ─────────────────────────────────────────────────────────

  /// Songs suggested since the captain last asked fresh — skipped by
  /// "another" so it doesn't repeat itself. Not a rejection: cleared when a
  /// suggestion is queued or dismissed.
  final List<int> _shownThisRound = [];
  final List<String> _shownTitlesThisRound = [];

  void _resetRound() {
    _shownThisRound.clear();
    _shownTitlesThisRound.clear();
  }

  /// Asks the AI what to play next. With [another], the captain wants a
  /// different song than the ones just shown.
  Future<void> suggestNext({bool another = false}) async {
    final session = state.session;
    if (session == null || state.isSuggesting) return;
    if (!another) _resetRound();
    final current = state.suggestion;
    if (another && current != null) {
      if (current.isCustom) {
        if (!_shownTitlesThisRound.contains(current.title)) {
          _shownTitlesThisRound.add(current.title);
        }
      } else if (!_shownThisRound.contains(current.songId)) {
        _shownThisRound.add(current.songId!);
      }
    }
    state = state.copyWith(isSuggesting: true, suggestionError: () => null);
    try {
      final result = await _repository.suggest(
        session.id,
        skip: List.of(_shownThisRound),
        skipTitles: List.of(_shownTitlesThisRound),
      );
      state = state.copyWith(
        isSuggesting: false,
        suggestion: () => result.suggestion,
        suggestionError: () => result.suggestion == null
            ? result.message ?? 'No more songs to suggest.'
            : null,
      );
    } catch (e) {
      state = state.copyWith(
        isSuggesting: false,
        suggestion: () => null,
        suggestionError: () => 'Couldn\'t get a suggestion. Try again.',
      );
    }
  }

  /// Queues the current suggestion. If nothing is playing it starts right
  /// away, same as tapping a song in the picker.
  Future<void> acceptSuggestion() async {
    final session = state.session;
    final suggestion = state.suggestion;
    if (session == null || suggestion == null) return;
    _resetRound();
    state = state.copyWith(suggestion: () => null);
    // A client request outside the catalog is queued by title.
    if (suggestion.isCustom) {
      await addCustomSong(suggestion.title, artist: suggestion.artist);
      return;
    }
    // Already picked by hand since it was suggested — nothing to add.
    final alreadyIn = session.queue.any((e) =>
        e.songId == suggestion.songId && (e.isPending || e.isPlayed));
    if (alreadyIn) return;
    try {
      await _repository.acceptSuggestion(session.id, suggestion.songId!);
      await _resync();
      // Accepting appends; on an empty queue the server already makes it
      // current, but after the queue ran out it would sit in Upcoming.
      final after = state.session;
      if (after != null &&
          after.isActive &&
          after.currentSong == null &&
          after.upcoming.isNotEmpty) {
        await _repository.next(after.id);
      }
    } catch (e) {
      state = state.copyWith(error: () => 'Failed to add song: $e');
    }
    await _resync();
  }

  void dismissSuggestion() {
    _resetRound();
    state = state.copyWith(
      suggestion: () => null,
      suggestionError: () => null,
    );
  }

  Future<void> startBreak() async {
    final id = state.session?.id;
    if (id == null) return;
    try {
      await _repository.startBreak(id);
      await _resync();
    } catch (e) {
      state = state.copyWith(error: () => 'Error: $e');
    }
  }

  Future<void> resumeFromBreak(int songId) async {
    final id = state.session?.id;
    if (id == null) return;
    try {
      await _repository.resumeFromBreak(id, songId);
      await _resync();
    } catch (e) {
      state = state.copyWith(error: () => 'Failed to resume: $e');
    }
  }

  /// Re-fetches the session after a captain action so the captain's own
  /// screen is correct even when Pusher is down (venue Wi-Fi, or a socket
  /// that never reconnected). Also covers the server not broadcasting when a
  /// pick-as-you-go session finishes its last queued song.
  Future<void> _resync() async {
    try {
      final result = await _repository.getSession(_eventKey);
      state = state.copyWith(
        session: () => result.session,
        isCaptain: result.isCaptain,
        clientRequests: () => result.clientRequests,
        clientNotes: () => result.clientNotes,
      );
    } catch (_) {
      // Best effort — Pusher or the next action will reconcile.
    }
  }

  // ── Pusher ─────────────────────────────────────────────────────────────────

  Future<void> Function()? _unsubscribe;

  Future<void> _connectPusher(int sessionId) async {
    _unsubscribe = await ref
        .read(pusherConnectionProvider)
        .subscribe('private-setlist.$sessionId', _onPusherEvent);
  }

  void _onPusherEvent(String eventName, Map<String, dynamic> data) {
    switch (eventName) {
      case 'SetlistQueueAdvanced':
        _handleQueueAdvanced(data);
      case 'SetlistQueueUpdated':
        _handleQueueUpdated(data);
      case 'SetlistSessionStateChanged':
        _handleStateChanged(data);
      case 'SetlistCaptainChanged':
        _handleCaptainChanged(data);
      case 'SetlistQueueingNext':
        // Informational — captain is picking the next song.
        break;
    }
  }

  void _handleQueueAdvanced(Map<String, dynamic> data) {
    final session = state.session;
    if (session == null) return;

    final newPosition = data['current_position'] as int? ?? session.currentPosition;

    final updatedQueue = session.queue.map((e) {
      if (e.position == session.currentPosition && e.isPending) {
        return QueueEntry(
          id: e.id,
          type: e.type,
          songId: e.songId,
          position: e.position,
          status: 'played',
          title: e.title,
          artist: e.artist,
          songKey: e.songKey,
          genre: e.genre,
          bpm: e.bpm,
          leadSinger: e.leadSinger,
          crowdReaction:
              (data['current_song'] as Map<String, dynamic>?)?['crowd_reaction']
                  as String?,
          isOffSetlist: e.isOffSetlist,
          playedAt: clock.now().toIso8601String(),
        );
      }
      return e;
    }).toList();

    state = state.copyWith(
      session: () => session.copyWith(
        currentPosition: newPosition,
        queue: updatedQueue,
      ),
    );
  }

  void _handleQueueUpdated(Map<String, dynamic> data) {
    final session = state.session;
    if (session == null) return;

    final queueJson = data['queue'] as List<dynamic>? ?? [];
    final newQueue = queueJson
        .map((e) => QueueEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final newPosition =
        data['current_position'] as int? ?? session.currentPosition;

    state = state.copyWith(
      session: () => session.copyWith(
        queue: newQueue,
        currentPosition: newPosition,
      ),
    );
  }

  void _handleStateChanged(Map<String, dynamic> data) {
    final session = state.session;
    if (session == null) return;

    final newStatus = data['status'] as String? ?? session.status;
    final newPosition =
        data['current_position'] as int? ?? session.currentPosition;
    final breakStartedAt = data['break_started_at'] as String?;
    final afterBreak = data['after_break'] as bool? ?? session.afterBreak;

    state = state.copyWith(
      session: () => session.copyWith(
        status: newStatus,
        currentPosition: newPosition,
        breakStartedAt: breakStartedAt ?? session.breakStartedAt,
        afterBreak: afterBreak,
      ),
    );
  }

  void _handleCaptainChanged(Map<String, dynamic> data) {
    final userId = data['user_id'] as int?;
    final action = data['action'] as String?;
    if (userId == null || action == null) return;

    if (userId == state.currentUserId) {
      state = state.copyWith(isCaptain: action == 'promoted');
    }
  }

  Future<void> _disconnect() async {
    try {
      await _unsubscribe?.call();
    } catch (_) {}
    _unsubscribe = null;
  }
}

// ── Provider ───────────────────────────────────────────────────────────────────

final liveSessionProvider = NotifierProvider.family<
    LiveSessionNotifier, LiveSessionState, String>(
  (arg) => LiveSessionNotifier(arg),
);
