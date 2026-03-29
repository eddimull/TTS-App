import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/rehearsal_detail.dart';
import 'models/rehearsal_schedule.dart';

class RehearsalsRepository {
  RehearsalsRepository(this._dio);

  final Dio _dio;

  /// Fetches the rehearsal schedules (with upcoming rehearsals) for [bandId].
  Future<List<RehearsalSchedule>> getSchedules(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRehearsalSchedules(bandId),
    );

    final data = response.data!;
    final rawList = data['schedules'] as List<dynamic>;
    return rawList
        .cast<Map<String, dynamic>>()
        .map(RehearsalSchedule.fromJson)
        .toList();
  }

  /// Fetches the full detail for the rehearsal identified by [rehearsalId].
  Future<RehearsalDetail> getRehearsalDetail(int rehearsalId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalDetail(rehearsalId),
    );

    final data = response.data!;
    return RehearsalDetail.fromJson(
        data['rehearsal'] as Map<String, dynamic>);
  }

  /// Resolves a virtual rehearsal key to a real Rehearsal record.
  Future<RehearsalDetail> getRehearsalByKey(String key) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalByKey(key),
    );

    final data = response.data!;
    return RehearsalDetail.fromJson(
        data['rehearsal'] as Map<String, dynamic>);
  }

  /// Updates the notes on a rehearsal. Returns the saved notes string (or null).
  Future<String?> updateNotes(int rehearsalId, String? notes) async {
    final response = await _dio.patch<dynamic>(
      ApiEndpoints.mobileRehearsalUpdateNotes(rehearsalId),
      data: {'notes': notes},
    );

    // Dio may return a Map or a raw JSON String depending on response headers.
    final body = response.data is String
        ? (jsonDecode(response.data as String) as Map<String, dynamic>)
        : response.data as Map<String, dynamic>?;

    final value = body?['notes'];
    return (value is String && value.isNotEmpty) ? value : null;
  }
}

final rehearsalsRepositoryProvider = Provider<RehearsalsRepository>((ref) {
  return RehearsalsRepository(ref.watch(apiClientProvider).dio);
});
