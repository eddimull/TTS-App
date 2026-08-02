import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/rehearsal_detail.dart';
import 'models/rehearsal_schedule.dart';
import 'models/rehearsal_sub.dart';

class RehearsalsRepository {
  RehearsalsRepository(this._dio);

  final Dio _dio;

  /// Fetches the rehearsal schedules (with upcoming rehearsals) for [bandId].
  /// [until] (yyyy-MM-dd, inclusive) extends the upcoming window past the
  /// server's 60-day default; [includeVirtual] merges un-materialized
  /// occurrences generated from each schedule's recurrence rule.
  Future<List<RehearsalSchedule>> getSchedules(
    int bandId, {
    String? until,
    bool includeVirtual = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRehearsalSchedules(bandId),
      queryParameters: {
        if (until != null) 'until': until,
        if (includeVirtual) 'include_virtual': 1,
      },
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

  /// Sets (not toggles) the cancelled flag on a rehearsal. Returns the
  /// refreshed [RehearsalDetail].
  Future<RehearsalDetail> setCancelled(int rehearsalId, bool isCancelled) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalSetCancelled(rehearsalId),
      data: {'is_cancelled': isCancelled},
    );

    final data = response.data!;
    return RehearsalDetail.fromJson(data['rehearsal'] as Map<String, dynamic>);
  }

  /// Invites a sub to the rehearsal — either from a call-list entry or ad-hoc
  /// by name/email. Returns the rehearsal's refreshed subs list.
  Future<List<RehearsalSub>> addSub(
    int rehearsalId, {
    int? callListEntryId,
    String? name,
    String? email,
    String? phone,
    int? bandRoleId,
  }) async {
    assert(
      callListEntryId != null || (name != null && email != null),
      'addSub requires callListEntryId or name+email',
    );
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalSubs(rehearsalId),
      data: {
        if (callListEntryId != null) 'call_list_entry_id': callListEntryId,
        if (callListEntryId == null) ...{
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (bandRoleId != null) 'band_role_id': bandRoleId,
        },
      },
    );
    return _parseSubs(response.data!);
  }

  /// Removes an invited sub. Returns the rehearsal's refreshed subs list.
  Future<List<RehearsalSub>> removeSub(int rehearsalId, int subId) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalSub(rehearsalId, subId),
    );
    return _parseSubs(response.data!);
  }

  List<RehearsalSub> _parseSubs(Map<String, dynamic> data) {
    final raw = data['subs'];
    if (raw is! List) return const [];
    return raw.cast<Map<String, dynamic>>().map(RehearsalSub.fromJson).toList();
  }
}

final rehearsalsRepositoryProvider = Provider<RehearsalsRepository>((ref) {
  return RehearsalsRepository(ref.watch(apiClientProvider).dio);
});
