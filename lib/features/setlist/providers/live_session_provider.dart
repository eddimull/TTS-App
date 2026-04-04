import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import '../../../core/config/app_config.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/band_song.dart';
import '../data/models/live_session.dart';
import '../data/models/queue_entry.dart';
import '../data/setlist_repository.dart';

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
  });

  final LiveSession? session;
  final List<BandSong> songs;
  final bool isCaptain;
  final bool canWrite;
  final int currentUserId;
  final bool isLoading;
  final String? error;

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
  }) =>
      LiveSessionState(
        session: session != null ? session() : this.session,
        songs: songs ?? this.songs,
        isCaptain: isCaptain ?? this.isCaptain,
        canWrite: canWrite ?? this.canWrite,
        currentUserId: currentUserId ?? this.currentUserId,
        isLoading: isLoading ?? this.isLoading,
        error: error != null ? error() : this.error,
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────────

class LiveSessionNotifier extends Notifier<LiveSessionState> {
  LiveSessionNotifier(this._eventKey);
  final String _eventKey;
  SetlistRepository? _repo;
  PusherChannelsFlutter? _pusher;
  String? _token;

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
    try {
      final result = await _repository.getSession(_eventKey);
      state = state.copyWith(
        session: () => result.session,
        songs: result.songs,
        isCaptain: result.isCaptain,
        canWrite: result.canWrite,
        currentUserId: result.currentUserId,
        isLoading: false,
      );

      if (result.session != null) {
        await _connectPusher(result.session!.id);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: () => e.toString(),
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
      _disconnectChannel();
      state = state.copyWith(
        session: () => state.session?.copyWith(status: 'completed'),
      );
    } catch (e) {
      state = state.copyWith(error: () => 'Failed to end session: $e');
    }
  }

  // ── Captain actions ────────────────────────────────────────────────────────

  Future<void> next() async {
    final id = state.session?.id;
    if (id == null) return;
    try {
      await _repository.next(id);
    } catch (e) {
      state = state.copyWith(error: () => 'Error: $e');
    }
  }

  Future<void> skip() async {
    final id = state.session?.id;
    if (id == null) return;
    try {
      await _repository.skip(id);
    } catch (e) {
      state = state.copyWith(error: () => 'Error: $e');
    }
  }

  Future<void> skipRemove() async {
    final id = state.session?.id;
    if (id == null) return;
    try {
      await _repository.skipRemove(id);
    } catch (e) {
      state = state.copyWith(error: () => 'Error: $e');
    }
  }

  Future<void> react(int queueEntryId, String reaction) async {
    final id = state.session?.id;
    if (id == null) return;
    try {
      await _repository.react(id, queueEntryId, reaction);
    } catch (e) {
      state = state.copyWith(error: () => 'Error: $e');
    }
  }

  Future<void> addOffSetlist(int songId) async {
    final id = state.session?.id;
    if (id == null) return;
    try {
      await _repository.addOffSetlist(id, songId);
    } catch (e) {
      state = state.copyWith(error: () => 'Failed to add song: $e');
    }
  }

  Future<void> startBreak() async {
    final id = state.session?.id;
    if (id == null) return;
    try {
      await _repository.startBreak(id);
    } catch (e) {
      state = state.copyWith(error: () => 'Error: $e');
    }
  }

  Future<void> resumeFromBreak(int songId) async {
    final id = state.session?.id;
    if (id == null) return;
    try {
      await _repository.resumeFromBreak(id, songId);
    } catch (e) {
      state = state.copyWith(error: () => 'Failed to resume: $e');
    }
  }

  // ── Pusher ─────────────────────────────────────────────────────────────────

  Future<void> _connectPusher(int sessionId) async {
    _token = await ref.read(secureStorageProvider).readToken();
    if (_token == null) return;

    const pusherKey = AppConfig.pusherKey;
    if (pusherKey.isEmpty) return; // Pusher not configured yet

    _pusher = PusherChannelsFlutter.getInstance();

    await _pusher!.init(
      apiKey: pusherKey,
      cluster: AppConfig.pusherCluster,
      authEndpoint: '${AppConfig.baseUrl}/broadcasting/auth',
      onAuthorizer: (String channelName, String socketId, dynamic options) {
        return {
          'headers': {
            'Authorization': 'Bearer $_token',
            'Accept': 'application/json',
          },
        };
      },
    );

    await _pusher!.connect();

    await _pusher!.subscribe(
      channelName: 'private-setlist.$sessionId',
      onEvent: _onPusherEvent,
    );
  }

  void _onPusherEvent(PusherEvent event) {
    final rawData = event.data;
    if (rawData == null) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(rawData) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (event.eventName) {
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
          playedAt: DateTime.now().toIso8601String(),
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

  void _disconnectChannel() {
    if (state.session != null) {
      _pusher?.unsubscribe(
          channelName: 'private-setlist.${state.session!.id}');
    }
  }

  Future<void> _disconnect() async {
    _disconnectChannel();
    try {
      await _pusher?.disconnect();
    } catch (_) {}
    _pusher = null;
  }
}

// ── Provider ───────────────────────────────────────────────────────────────────

final liveSessionProvider = NotifierProvider.family<
    LiveSessionNotifier, LiveSessionState, String>(
  (arg) => LiveSessionNotifier(arg),
);
