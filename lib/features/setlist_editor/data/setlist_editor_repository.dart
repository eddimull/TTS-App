import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/event_setlist.dart';
import 'models/setlist_prompt_template.dart';

class SetlistEditorPayload {
  const SetlistEditorPayload({
    required this.setlist,
    required this.bandSongs,
    required this.canWrite,
  });

  final EventSetlist? setlist;
  final List<BandSongSummary> bandSongs;
  final bool canWrite;
}

class RefineResult {
  const RefineResult({required this.setlist, required this.summary});
  final EventSetlist setlist;
  final String summary;
}

class SetlistEditorRepository {
  SetlistEditorRepository(this._dio);
  final Dio _dio;

  // ── Setlist ────────────────────────────────────────────────────────────────

  Future<SetlistEditorPayload> getSetlist(String eventKey) async {
    final resp = await _dio.get(ApiEndpoints.mobileEventSetlist(eventKey));
    final data = resp.data as Map<String, dynamic>;

    final setlistJson = data['setlist'] as Map<String, dynamic>?;
    final songs = (data['songs'] as List<dynamic>? ?? [])
        .map((e) => BandSongSummary.fromJson(e as Map<String, dynamic>))
        .toList();

    return SetlistEditorPayload(
      setlist: setlistJson != null ? EventSetlist.fromJson(setlistJson) : null,
      bandSongs: songs,
      canWrite: data['can_write'] as bool? ?? false,
    );
  }

  Future<EventSetlist> updateSetlist(
    String eventKey,
    List<SetlistEntry> entries, {
    String? status,
  }) async {
    final body = {
      'songs': entries.map((e) => e.toUpdateJson()).toList(),
      if (status != null) 'status': status,
    };
    final resp = await _dio.put(
      ApiEndpoints.mobileEventSetlist(eventKey),
      data: body,
    );
    return EventSetlist.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<EventSetlist> generate(String eventKey, {String? context}) async {
    final resp = await _dio.post(
      ApiEndpoints.mobileEventSetlistGenerate(eventKey),
      data: {if (context != null && context.isNotEmpty) 'context': context},
    );
    return EventSetlist.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<RefineResult> refine(
    String eventKey, {
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    final resp = await _dio.post(
      ApiEndpoints.mobileEventSetlistRefine(eventKey),
      data: {'message': message, 'history': history},
    );
    final data = resp.data as Map<String, dynamic>;
    return RefineResult(
      setlist: EventSetlist.fromJson(data['setlist'] as Map<String, dynamic>),
      summary: data['summary'] as String? ?? '',
    );
  }

  // ── Prompt templates ───────────────────────────────────────────────────────

  Future<List<SetlistPromptTemplate>> listPromptTemplates(int bandId) async {
    final resp =
        await _dio.get(ApiEndpoints.mobileBandSetlistPromptTemplates(bandId));
    final raw = resp.data;
    // Backend wraps list endpoints inconsistently; tolerate either a bare list
    // or a {data: [...]} envelope.
    final list = raw is Map<String, dynamic>
        ? (raw['data'] as List<dynamic>? ?? [])
        : (raw as List<dynamic>);
    return list
        .map((e) => SetlistPromptTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SetlistPromptTemplate> createPromptTemplate(int bandId,
      {required String name, required String prompt}) async {
    final resp = await _dio.post(
      ApiEndpoints.mobileBandSetlistPromptTemplates(bandId),
      data: {'name': name, 'prompt': prompt},
    );
    final data = resp.data;
    final json = data is Map<String, dynamic> && data.containsKey('data')
        ? data['data'] as Map<String, dynamic>
        : data as Map<String, dynamic>;
    return SetlistPromptTemplate.fromJson(json);
  }

  Future<SetlistPromptTemplate> updatePromptTemplate(int bandId, int templateId,
      {String? name, String? prompt}) async {
    final resp = await _dio.patch(
      ApiEndpoints.mobileBandSetlistPromptTemplate(bandId, templateId),
      data: {
        if (name != null) 'name': name,
        if (prompt != null) 'prompt': prompt,
      },
    );
    final data = resp.data;
    final json = data is Map<String, dynamic> && data.containsKey('data')
        ? data['data'] as Map<String, dynamic>
        : data as Map<String, dynamic>;
    return SetlistPromptTemplate.fromJson(json);
  }

  Future<void> deletePromptTemplate(int bandId, int templateId) => _dio
      .delete(ApiEndpoints.mobileBandSetlistPromptTemplate(bandId, templateId));
}
