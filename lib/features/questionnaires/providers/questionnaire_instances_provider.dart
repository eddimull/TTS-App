import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/eligible_booking.dart';
import '../data/models/questionnaire_instance.dart';
import '../data/questionnaires_repository.dart';
import 'questionnaires_provider.dart';

class QuestionnaireInstancesNotifier
    extends AsyncNotifier<List<QuestionnaireInstance>> {
  QuestionnaireInstancesNotifier(this._key);

  final ({int bandId, int questionnaireId}) _key;

  QuestionnairesRepository get _repo =>
      ref.read(questionnairesRepositoryProvider);

  @override
  Future<List<QuestionnaireInstance>> build() =>
      _repo.getInstances(_key.bandId, _key.questionnaireId);

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => _repo.getInstances(_key.bandId, _key.questionnaireId));
  }

  Future<QuestionnaireInstance> send({
    required int bookingId,
    required int recipientContactId,
  }) async {
    final created = await _repo.sendQuestionnaire(
      _key.bandId,
      bookingId,
      questionnaireId: _key.questionnaireId,
      recipientContactId: recipientContactId,
    );
    final current = state.value ?? [];
    state = AsyncValue.data([created, ...current]);
    // Times-sent count on the template list + already_sent flags change.
    ref.invalidate(questionnairesProvider(_key.bandId));
    ref.invalidate(eligibleBookingsProvider(_key));
    return created;
  }

  Future<void> resend(int instanceId) async {
    await _repo.resendInstance(_key.bandId, instanceId);
  }

  Future<void> lock(int instanceId) async {
    final updated = await _repo.lockInstance(_key.bandId, instanceId);
    _replace(updated);
  }

  Future<void> unlock(int instanceId) async {
    final updated = await _repo.unlockInstance(_key.bandId, instanceId);
    _replace(updated);
  }

  Future<void> deleteInstance(int instanceId) async {
    await _repo.deleteInstance(_key.bandId, instanceId);
    final current = state.value ?? [];
    state = AsyncValue.data(
        current.where((i) => i.id != instanceId).toList());
    ref.invalidate(questionnairesProvider(_key.bandId));
  }

  void _replace(QuestionnaireInstance updated) {
    final current = state.value ?? [];
    state = AsyncValue.data(
        current.map((i) => i.id == updated.id ? updated : i).toList());
  }
}

final questionnaireInstancesProvider = AsyncNotifierProvider.family<
    QuestionnaireInstancesNotifier,
    List<QuestionnaireInstance>,
    ({int bandId, int questionnaireId})>(
  (arg) => QuestionnaireInstancesNotifier(arg),
);

final instanceDetailProvider = FutureProvider.family<QuestionnaireInstance,
    ({int bandId, int instanceId})>(
  (ref, args) async {
    final repo = ref.watch(questionnairesRepositoryProvider);
    return repo.getInstance(args.bandId, args.instanceId);
  },
);

final eligibleBookingsProvider = FutureProvider.family<List<EligibleBooking>,
    ({int bandId, int questionnaireId})>(
  (ref, args) async {
    final repo = ref.watch(questionnairesRepositoryProvider);
    return repo.getEligibleBookings(args.bandId, args.questionnaireId);
  },
);

final bookingQuestionnairesProvider = FutureProvider.family<
    BookingQuestionnaires, ({int bandId, int bookingId})>(
  (ref, args) async {
    final repo = ref.watch(questionnairesRepositoryProvider);
    return repo.getBookingQuestionnaires(args.bandId, args.bookingId);
  },
);
