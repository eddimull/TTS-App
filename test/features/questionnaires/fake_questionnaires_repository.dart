import 'package:tts_bandmate/features/questionnaires/data/models/eligible_booking.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_catalog.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_instance.dart';
import 'package:tts_bandmate/features/questionnaires/data/questionnaires_repository.dart';

class FakeQuestionnairesRepository implements QuestionnairesRepository {
  FakeQuestionnairesRepository({
    this.questionnaires = const [],
    this.instances = const [],
  });

  List<Questionnaire> questionnaires;
  List<QuestionnaireInstance> instances;
  String? createdName;
  String? createdPresetKey;
  int? archivedId;
  int? deletedId;
  String? updatedName;
  List<Map<String, dynamic>>? updatedFields;
  int? sentBookingId;
  int? sentContactId;
  int? sentQuestionnaireId;
  int? deletedInstanceId;
  int _nextId = 100;
  int _nextInstanceId = 500;

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

  @override
  Future<List<QuestionnaireInstance>> getInstances(int bandId, int questionnaireId) async =>
      instances;

  @override
  Future<List<EligibleBooking>> getEligibleBookings(int bandId, int questionnaireId) async =>
      const [];

  @override
  Future<BookingQuestionnaires> getBookingQuestionnaires(int bandId, int bookingId) async =>
      BookingQuestionnaires(instances: instances);

  @override
  Future<QuestionnaireInstance> getInstance(int bandId, int instanceId) async =>
      instances.firstWhere((i) => i.id == instanceId);

  @override
  Future<QuestionnaireInstance> sendQuestionnaire(
    int bandId,
    int bookingId, {
    required int questionnaireId,
    required int recipientContactId,
  }) async {
    sentBookingId = bookingId;
    sentContactId = recipientContactId;
    sentQuestionnaireId = questionnaireId;
    return QuestionnaireInstance(
      id: _nextInstanceId++,
      name: 'Intake',
      status: 'sent',
      recipientName: 'New Recipient',
      bookingId: bookingId,
      bookingName: 'Booking',
      questionnaireId: questionnaireId,
    );
  }

  @override
  Future<QuestionnaireInstance> resendInstance(int bandId, int instanceId) async =>
      instances.firstWhere((i) => i.id == instanceId);

  @override
  Future<QuestionnaireInstance> lockInstance(int bandId, int instanceId) async =>
      instances.firstWhere((i) => i.id == instanceId).copyWith(status: 'locked');

  @override
  Future<QuestionnaireInstance> unlockInstance(int bandId, int instanceId) async =>
      instances.firstWhere((i) => i.id == instanceId).copyWith(status: 'sent');

  @override
  Future<void> deleteInstance(int bandId, int instanceId) async {
    deletedInstanceId = instanceId;
  }
}
