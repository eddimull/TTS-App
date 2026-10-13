import 'package:dio/dio.dart';
import 'models/band_song.dart';
import 'models/live_session.dart';
import 'models/client_notes.dart';
import 'models/live_suggestion.dart';
import '../../setlist_editor/data/models/event_setlist.dart' show ClientSongRequests;
import 'models/queue_entry.dart';

class SetlistRepository {
  SetlistRepository(this._dio);

  final Dio _dio;

  // ── Session lifecycle ──────────────────────────────────────────────────────

  /// Parses the session payload. Shared by live fetches and the offline
  /// cache so both go through identical decoding.
  static ({
    LiveSession? session,
    List<BandSong> songs,
    bool isCaptain,
    bool canWrite,
    int currentUserId,
    ClientSongRequests? clientRequests,
    ClientNotes? clientNotes
  }) parseSession(Map<String, dynamic> data) {
    final sessionJson = data['session'] as Map<String, dynamic>?;
    final songs = (data['songs'] as List<dynamic>? ?? [])
        .map((e) => BandSong.fromJson(e as Map<String, dynamic>))
        .toList();

    return (
      session: sessionJson != null ? LiveSession.fromJson(sessionJson) : null,
      songs: songs,
      isCaptain: data['is_captain'] as bool? ?? false,
      canWrite: data['can_write'] as bool? ?? false,
      currentUserId: data['current_user_id'] as int,
      clientRequests: data['client_requests'] is Map<String, dynamic>
          ? ClientSongRequests.fromJson(
              data['client_requests'] as Map<String, dynamic>)
          : null,
      clientNotes: data['client_notes'] is Map<String, dynamic>
          ? ClientNotes.fromJson(data['client_notes'] as Map<String, dynamic>)
          : null,
    );
  }

  Future<
      ({
        LiveSession? session,
        List<BandSong> songs,
        bool isCaptain,
        bool canWrite,
        int currentUserId,
        ClientSongRequests? clientRequests,
        ClientNotes? clientNotes
      })> getSession(String eventKey) async {
    final result = await getSessionRaw(eventKey);
    return (
      session: result.session,
      songs: result.songs,
      isCaptain: result.isCaptain,
      canWrite: result.canWrite,
      currentUserId: result.currentUserId,
      clientRequests: result.clientRequests,
      clientNotes: result.clientNotes,
    );
  }

  /// Like [getSession] but also returns the raw response JSON so callers can
  /// persist it verbatim (the models have no `toJson`).
  Future<
      ({
        LiveSession? session,
        List<BandSong> songs,
        bool isCaptain,
        bool canWrite,
        int currentUserId,
        ClientSongRequests? clientRequests,
        ClientNotes? clientNotes,
        Map<String, dynamic> raw
      })> getSessionRaw(String eventKey) async {
    final resp = await _dio.get('/api/mobile/setlist/events/$eventKey/session');
    final data = resp.data as Map<String, dynamic>;
    final parsed = parseSession(data);
    return (
      session: parsed.session,
      songs: parsed.songs,
      isCaptain: parsed.isCaptain,
      canWrite: parsed.canWrite,
      currentUserId: parsed.currentUserId,
      clientRequests: parsed.clientRequests,
      clientNotes: parsed.clientNotes,
      raw: data
    );
  }

  Future<LiveSession> startSession(String eventKey) async {
    final resp = await _dio.post('/api/mobile/setlist/events/$eventKey/session');
    return LiveSession.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> endSession(String eventKey) async {
    await _dio.delete('/api/mobile/setlist/events/$eventKey/session');
  }

  // ── Captain actions ────────────────────────────────────────────────────────

  Future<void> next(int sessionId) =>
      _dio.post('/api/mobile/setlist/sessions/$sessionId/next');

  Future<void> skip(int sessionId) =>
      _dio.post('/api/mobile/setlist/sessions/$sessionId/skip');

  Future<void> skipRemove(int sessionId) =>
      _dio.post('/api/mobile/setlist/sessions/$sessionId/skip-remove');

  Future<void> react(int sessionId, int queueEntryId, String reaction) =>
      _dio.post('/api/mobile/setlist/sessions/$sessionId/reaction', data: {
        'queue_entry_id': queueEntryId,
        'reaction': reaction,
      });

  /// [appendToEnd] queues the song behind everything already upcoming;
  /// otherwise the server inserts it right after the current song.
  ///
  /// Pass [songId] for a catalog song, or [customTitle] (and optionally
  /// [customArtist]) for a client request that isn't in the catalog.
  Future<QueueEntry> addOffSetlist(
    int sessionId,
    int? songId, {
    bool appendToEnd = false,
    String? customTitle,
    String? customArtist,
  }) async {
    final resp = await _dio.post(
      '/api/mobile/setlist/sessions/$sessionId/off-setlist',
      data: {
        if (songId != null) 'song_id': songId,
        if (songId == null) 'custom_title': customTitle,
        if (songId == null && customArtist != null)
          'custom_artist': customArtist,
        if (appendToEnd) 'placement': 'end',
      },
    );
    final d = resp.data as Map<String, dynamic>;
    return QueueEntry(
      id: d['id'] as int,
      type: 'song',
      position: 0,
      status: 'pending',
      isOffSetlist: true,
      title: d['title'] as String?,
      artist: d['artist'] as String?,
    );
  }

  // ── AI suggestions ─────────────────────────────────────────────────────────

  /// Asks the AI for the next song. [skip] holds songs already shown this
  /// round ("give me a different one") — skipped for this request only,
  /// not remembered for the night. When there's no suggestion, [message]
  /// says why (nothing left, or nothing that fits the client's requests).
  Future<({LiveSuggestion? suggestion, String? message})> suggest(
    int sessionId, {
    List<int> skip = const [],
    List<String> skipTitles = const [],
  }) async {
    final resp = await _dio.get(
      '/api/mobile/setlist/sessions/$sessionId/suggest',
      queryParameters: {
        if (skip.isNotEmpty) 'skip[]': skip,
        // Client requests outside the catalog are known by title.
        if (skipTitles.isNotEmpty) 'skip_titles[]': skipTitles,
      },
    );
    final data = resp.data as Map<String, dynamic>;
    return (
      suggestion: LiveSuggestion.fromResponse(data),
      message: data['message'] as String?,
    );
  }

  /// Queues a suggestion at the end of the queue (and clears the server's
  /// post-break flag).
  Future<void> acceptSuggestion(int sessionId, int songId) => _dio.post(
        '/api/mobile/setlist/sessions/$sessionId/accept-suggestion',
        data: {'song_id': songId},
      );

  /// Drops an upcoming (not currently playing) entry from the queue.
  Future<void> removeUpcoming(int sessionId, int queueEntryId) =>
      _dio.delete('/api/mobile/setlist/sessions/$sessionId/queue/$queueEntryId');

  /// Sets the order of the upcoming queue; [queueEntryIds] must be every
  /// upcoming entry (songs and breaks), in their new order.
  Future<void> reorderUpcoming(int sessionId, List<int> queueEntryIds) =>
      _dio.put(
        '/api/mobile/setlist/sessions/$sessionId/queue/order',
        data: {'entry_ids': queueEntryIds},
      );

  Future<void> promote(int sessionId, int userId) =>
      _dio.post('/api/mobile/setlist/sessions/$sessionId/promote', data: {'user_id': userId});

  Future<void> demote(int sessionId, int userId) =>
      _dio.post('/api/mobile/setlist/sessions/$sessionId/demote', data: {'user_id': userId});

  // ── Break ──────────────────────────────────────────────────────────────────

  Future<void> startBreak(int sessionId) =>
      _dio.post('/api/mobile/setlist/sessions/$sessionId/break');

  Future<void> resumeFromBreak(int sessionId, int songId) =>
      _dio.post('/api/mobile/setlist/sessions/$sessionId/break/resume', data: {'song_id': songId});
}
