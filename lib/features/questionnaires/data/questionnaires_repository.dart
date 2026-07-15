import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/questionnaire.dart';
import 'models/questionnaire_catalog.dart';

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
}
