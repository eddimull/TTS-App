import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/lodging.dart';

class LodgingRepository {
  LodgingRepository(this._dio);

  final Dio _dio;

  Future<({List<LodgingSummary> lodgings, bool canWrite})> getLodgings(
      int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandLodgings(bandId),
    );
    final data = response.data!;
    final raw = data['lodgings'];
    final lodgings = raw is List
        ? raw.cast<Map<String, dynamic>>().map(LodgingSummary.fromJson).toList()
        : <LodgingSummary>[];
    return (lodgings: lodgings, canWrite: data['can_write'] as bool? ?? false);
  }

  Future<({Lodging lodging, bool canWrite})> getLodging(
      int bandId, int lodgingId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandLodging(bandId, lodgingId),
    );
    final data = response.data!;
    return (
      lodging: Lodging.fromJson(data['lodging'] as Map<String, dynamic>),
      canWrite: data['can_write'] as bool? ?? false,
    );
  }

  Future<Lodging> createLodging(
    int bandId, {
    required String name,
    String? address,
    double? latitude,
    double? longitude,
    required String checkInAt,
    required String checkOutAt,
    String? notes,
    int? bookingId,
    int? eventId,
    List<LodgingRoom> rooms = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandLodgings(bandId),
      data: {
        'name': name,
        if (address != null) 'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'check_in_at': checkInAt,
        'check_out_at': checkOutAt,
        if (notes != null) 'notes': notes,
        if (bookingId != null) 'booking_id': bookingId,
        if (eventId != null) 'event_id': eventId,
        'rooms': rooms.map((r) => r.toJson()).toList(),
      },
    );
    return Lodging.fromJson(response.data!['lodging'] as Map<String, dynamic>);
  }

  /// PATCH with an explicit field map — callers control exactly which keys
  /// are sent (null values included intentionally clear fields server-side).
  Future<Lodging> updateLodging(
      int bandId, int lodgingId, Map<String, dynamic> patch) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileBandLodging(bandId, lodgingId),
      data: patch,
    );
    return Lodging.fromJson(response.data!['lodging'] as Map<String, dynamic>);
  }

  Future<void> deleteLodging(int bandId, int lodgingId) async {
    await _dio.delete<void>(ApiEndpoints.mobileBandLodging(bandId, lodgingId));
  }

  Future<LodgingAttachment> uploadAttachment(
    int bandId,
    int lodgingId, {
    required List<int> bytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileLodgingAttachments(bandId, lodgingId),
      data: formData,
    );
    return LodgingAttachment.fromJson(
        response.data!['attachment'] as Map<String, dynamic>);
  }

  Future<void> deleteAttachment(
      int bandId, int lodgingId, int attachmentId) async {
    await _dio.delete<void>(
        ApiEndpoints.mobileLodgingAttachment(bandId, lodgingId, attachmentId));
  }
}

final lodgingRepositoryProvider = Provider<LodgingRepository>((ref) {
  return LodgingRepository(ref.watch(apiClientProvider).dio);
});
