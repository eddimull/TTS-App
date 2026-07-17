import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/eligible_booking.dart';
import 'models/questionnaire.dart';
import 'models/questionnaire_catalog.dart';
import 'models/questionnaire_instance.dart';

class QuestionnairesRepository {
  QuestionnairesRepository(this._dio);

  final Dio _dio;

  Future<List<Questionnaire>> getQuestionnaires(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaires(bandId),
    );
    final list = response.data!['questionnaires'] as List<dynamic>;
    return list
        .map((q) => Questionnaire.fromJson(q as Map<String, dynamic>))
        .toList();
  }

  Future<QuestionnaireCatalog> getCatalog(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireCatalog(bandId),
    );
    return QuestionnaireCatalog.fromJson(response.data!);
  }

  Future<Questionnaire> getQuestionnaire(int bandId, int questionnaireId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaire(bandId, questionnaireId),
    );
    return Questionnaire.fromJson(
        response.data!['questionnaire'] as Map<String, dynamic>);
  }

  Future<Questionnaire> createQuestionnaire(
    int bandId, {
    required String name,
    String? description,
    String? presetKey,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaires(bandId),
      data: {
        'name': name,
        if (description != null) 'description': description,
        if (presetKey != null) 'preset_key': presetKey,
      },
    );
    return Questionnaire.fromJson(
        response.data!['questionnaire'] as Map<String, dynamic>);
  }

  Future<Questionnaire> updateQuestionnaire(
    int bandId,
    int questionnaireId, {
    required String name,
    String? description,
    required List<Map<String, dynamic>> fields,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaire(bandId, questionnaireId),
      data: {
        'name': name,
        'description': description,
        'fields': fields,
      },
    );
    return Questionnaire.fromJson(
        response.data!['questionnaire'] as Map<String, dynamic>);
  }

  Future<Questionnaire> archiveQuestionnaire(int bandId, int questionnaireId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireArchive(bandId, questionnaireId),
    );
    return Questionnaire.fromJson(
        response.data!['questionnaire'] as Map<String, dynamic>);
  }

  Future<Questionnaire> restoreQuestionnaire(int bandId, int questionnaireId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireRestore(bandId, questionnaireId),
    );
    return Questionnaire.fromJson(
        response.data!['questionnaire'] as Map<String, dynamic>);
  }

  Future<void> deleteQuestionnaire(int bandId, int questionnaireId) async {
    await _dio.delete<void>(
      ApiEndpoints.mobileBandQuestionnaire(bandId, questionnaireId),
    );
  }

  Future<List<QuestionnaireInstance>> getInstances(
      int bandId, int questionnaireId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstances(bandId, questionnaireId),
    );
    final list = response.data!['instances'] as List<dynamic>;
    return list
        .map((i) => QuestionnaireInstance.fromJson(i as Map<String, dynamic>))
        .toList();
  }

  Future<List<EligibleBooking>> getEligibleBookings(
      int bandId, int questionnaireId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireEligibleBookings(
          bandId, questionnaireId),
    );
    final list = response.data!['bookings'] as List<dynamic>;
    return list
        .map((b) => EligibleBooking.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  Future<BookingQuestionnaires> getBookingQuestionnaires(
      int bandId, int bookingId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandBookingQuestionnaireInstances(bandId, bookingId),
    );
    return BookingQuestionnaires.fromJson(response.data!);
  }

  Future<QuestionnaireInstance> getInstance(int bandId, int instanceId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstance(bandId, instanceId),
    );
    return QuestionnaireInstance.fromJson(
        response.data!['instance'] as Map<String, dynamic>);
  }

  Future<QuestionnaireInstance> sendQuestionnaire(
    int bandId,
    int bookingId, {
    required int questionnaireId,
    required int recipientContactId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandBookingQuestionnairesSend(bandId, bookingId),
      data: {
        'questionnaire_id': questionnaireId,
        'recipient_contact_id': recipientContactId,
      },
    );
    return QuestionnaireInstance.fromJson(
        response.data!['instance'] as Map<String, dynamic>);
  }

  Future<QuestionnaireInstance> resendInstance(int bandId, int instanceId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstanceResend(bandId, instanceId),
    );
    return QuestionnaireInstance.fromJson(
        response.data!['instance'] as Map<String, dynamic>);
  }

  Future<QuestionnaireInstance> lockInstance(int bandId, int instanceId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstanceLock(bandId, instanceId),
    );
    return QuestionnaireInstance.fromJson(
        response.data!['instance'] as Map<String, dynamic>);
  }

  Future<QuestionnaireInstance> unlockInstance(int bandId, int instanceId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstanceUnlock(bandId, instanceId),
    );
    return QuestionnaireInstance.fromJson(
        response.data!['instance'] as Map<String, dynamic>);
  }

  Future<void> deleteInstance(int bandId, int instanceId) async {
    await _dio.delete<void>(
      ApiEndpoints.mobileBandQuestionnaireInstance(bandId, instanceId),
    );
  }

  Future<void> applyResponse(int bandId, int instanceId, int responseId) async {
    await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireResponseApply(
          bandId, instanceId, responseId),
    );
  }

  Future<int> applyAllResponses(int bandId, int instanceId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstanceApplyAll(bandId, instanceId),
    );
    return ((response.data!['applied_count'] as num?) ?? 0).toInt();
  }

  Future<void> appendToNotes(int bandId, int instanceId) async {
    await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstanceAppendToNotes(
          bandId, instanceId),
    );
  }
}
