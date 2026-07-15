import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_catalog.dart';
import 'package:tts_bandmate/features/questionnaires/data/questionnaires_repository.dart';

class FakeQuestionnairesRepository implements QuestionnairesRepository {
  FakeQuestionnairesRepository({this.questionnaires = const []});

  List<Questionnaire> questionnaires;
  String? createdName;
  String? createdPresetKey;
  int? archivedId;
  int? deletedId;
  String? updatedName;
  List<Map<String, dynamic>>? updatedFields;
  int _nextId = 100;

  @override
  Future<List<Questionnaire>> getQuestionnaires(int bandId) async =>
      questionnaires;

  @override
  Future<QuestionnaireCatalog> getCatalog(int bandId) async =>
      const QuestionnaireCatalog();

  @override
  Future<Questionnaire> getQuestionnaire(int bandId, int questionnaireId) async =>
      questionnaires.firstWhere((q) => q.id == questionnaireId);

  @override
  Future<Questionnaire> createQuestionnaire(
    int bandId, {
    required String name,
    String? description,
    String? presetKey,
  }) async {
    createdName = name;
    createdPresetKey = presetKey;
    return Questionnaire(
      id: _nextId++,
      name: name,
      description: description,
      instancesCount: 0,
    );
  }

  @override
  Future<Questionnaire> updateQuestionnaire(
    int bandId,
    int questionnaireId, {
    required String name,
    String? description,
    required List<Map<String, dynamic>> fields,
  }) async {
    updatedName = name;
    updatedFields = fields;
    return questionnaires.firstWhere((q) => q.id == questionnaireId);
  }

  @override
  Future<Questionnaire> archiveQuestionnaire(int bandId, int questionnaireId) async {
    archivedId = questionnaireId;
    final q = questionnaires.firstWhere((q) => q.id == questionnaireId);
    return q.copyWith(archivedAt: DateTime.utc(2026, 7, 15));
  }

  @override
  Future<Questionnaire> restoreQuestionnaire(int bandId, int questionnaireId) async {
    final q = questionnaires.firstWhere((q) => q.id == questionnaireId);
    return q.copyWith(clearArchivedAt: true);
  }

  @override
  Future<void> deleteQuestionnaire(int bandId, int questionnaireId) async {
    deletedId = questionnaireId;
  }
}
