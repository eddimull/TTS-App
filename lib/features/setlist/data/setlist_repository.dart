import 'package:dio/dio.dart';
import 'models/band_song.dart';
import 'models/live_session.dart';
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
    int currentUserId
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
    );
  }

  Future<({LiveSession? session, List<BandSong> songs, bool isCaptain, bool canWrite, int currentUserId})>
      getSession(String eventKey) async {
    final result = await getSessionRaw(eventKey);
    return (
      session: result.session,
      songs: result.songs,
      isCaptain: result.isCaptain,
      canWrite: result.canWrite,
      currentUserId: result.currentUserId,
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

  Future<QueueEntry> addOffSetlist(int sessionId, int songId) async {
    final resp = await _dio.post(
      '/api/mobile/setlist/sessions/$sessionId/off-setlist',
      data: {'song_id': songId},
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
