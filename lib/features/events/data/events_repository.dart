import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import 'models/event_detail.dart';
import 'models/event_summary.dart';

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
  Future<EventAttachment> uploadAttachment(String key, File file) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
      ),
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
}

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  return EventsRepository(ref.watch(apiClientProvider).dio);
});
