import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import 'models/event_detail.dart';
import 'models/event_summary.dart';
import 'models/sub_entry.dart';

class EventsRepository {
  EventsRepository(this._dio);

  final Dio _dio;

  /// Fetches the list of events for [bandId].
  ///
  /// Optional [from] and [to] are ISO date strings used to filter the range,
  /// e.g. "2026-04-01".
  Future<List<EventSummary>> getBandEvents(
    int bandId, {
    String? from,
    String? to,
  }) async {
    final queryParams = <String, String>{};
    if (from != null) queryParams['from'] = from;
    if (to != null) queryParams['to'] = to;

    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandEvents(bandId),
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final data = response.data!;
    final rawList = data['events'] as List<dynamic>;
    return rawList
        .cast<Map<String, dynamic>>()
        .map(EventSummary.fromJson)
        .toList();
  }

  /// Fetches the full detail for the event identified by [key].
  Future<EventDetail> getEventDetail(String key) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileEventDetail(key),
    );

    final data = response.data!;
    return EventDetail.fromJson(data['event'] as Map<String, dynamic>);
  }

  /// Sends a partial update for the event identified by [key].
  Future<void> updateEvent(String key, Map<String, dynamic> data) async {
    await _dio.patch<void>(ApiEndpoints.mobileUpdateEvent(key), data: data);
  }

  /// Uploads a single file attachment for the event identified by [key].
  Future<EventAttachment> uploadAttachment(
    String key, {
    required List<int> bytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileEventAttachments(key),
      data: formData,
    );
    return EventAttachment.fromJson(
      response.data!['attachment'] as Map<String, dynamic>,
    );
  }

  /// Deletes the attachment with [attachmentId] from the event identified by [key].
  Future<void> deleteAttachment(String key, int attachmentId) async {
    await _dio.delete<void>(
      ApiEndpoints.mobileDeleteEventAttachment(key, attachmentId),
    );
  }

  /// Fetches the substitute call list for a given role on [eventKey].
  Future<List<SubEntry>> fetchSubs(String eventKey, int bandRoleId) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileEventSubs(eventKey),
      queryParameters: {'band_role_id': bandRoleId},
    );
    final raw = resp.data!['subs'] as List;
    return raw.cast<Map<String, dynamic>>().map(SubEntry.fromJson).toList();
  }

  /// Assigns or clears a substitute for a roster slot on [eventKey].
  ///
  /// [memberId] is the EventMember id. Pass 0 when the slot has no EventMember
  /// row yet (synthetic unfilled slot) — in that case [slotId] is required.
  ///
  /// Pass [clear] = true to remove the current sub.
  /// Pass [rosterMemberId] to assign from the call list.
  /// Pass [name] (and optionally [email]) to assign a custom sub.
  Future<void> assignSub(
    String eventKey,
    int memberId, {
    int? slotId,
    int? rosterMemberId,
    String? name,
    String? email,
    bool clear = false,
  }) async {
    final body = <String, dynamic>{};
    if (slotId != null) body['slot_id'] = slotId;
    if (clear) {
      body['clear'] = true;
    } else if (rosterMemberId != null) {
      body['roster_member_id'] = rosterMemberId;
    } else if (name != null) {
      body['name'] = name;
      if (email != null) body['email'] = email;
    }
    await _dio.post<void>(
      ApiEndpoints.mobileEventMemberSub(eventKey, memberId),
      data: body,
    );
  }
}

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  return EventsRepository(ref.watch(apiClientProvider).dio);
});
