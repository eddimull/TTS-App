import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/planner_message.dart';

class RehearsalPlannerRepository {
  RehearsalPlannerRepository(this._dio);
  final Dio _dio;

  Future<({int sessionId, String channel, int assistantMessageId})>
      startSession(int bandId, {int? rehearsalId}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalPlannerSessions(bandId),
      data: rehearsalId != null ? {'rehearsal_id': rehearsalId} : null,
    );
    final data = res.data!;
    return (
      sessionId: (data['session_id'] as num).toInt(),
      channel: data['channel'] as String,
      assistantMessageId: (data['assistant_message_id'] as num).toInt(),
    );
  }

  Future<({PlannerMessage userMessage, int assistantMessageId, String channel})>
      sendMessage(int bandId, int sessionId, String text) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalPlannerMessages(bandId, sessionId),
      data: {'text': text},
    );
    final data = res.data!;
    return (
      userMessage: PlannerMessage.fromJson(
          data['user_message'] as Map<String, dynamic>),
      assistantMessageId: (data['assistant_message_id'] as num).toInt(),
      channel: data['channel'] as String,
    );
  }

  Future<List<PlannerMessage>> history(int bandId, int sessionId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalPlannerSession(bandId, sessionId),
    );
    final raw = res.data?['messages'];
    return raw is List
        ? raw.cast<Map<String, dynamic>>().map(PlannerMessage.fromJson).toList()
        : <PlannerMessage>[];
  }
}

final rehearsalPlannerRepositoryProvider =
    Provider<RehearsalPlannerRepository>(
  (ref) => RehearsalPlannerRepository(ref.watch(apiClientProvider).dio),
);
