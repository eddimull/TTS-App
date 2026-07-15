import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/questionnaire.dart';
import '../data/models/questionnaire_catalog.dart';
import '../data/questionnaires_repository.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final questionnairesRepositoryProvider = Provider<QuestionnairesRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return QuestionnairesRepository(dio);
});

// ── List notifier ─────────────────────────────────────────────────────────────

class QuestionnairesNotifier extends AsyncNotifier<List<Questionnaire>> {
  QuestionnairesNotifier(this._bandId);

  final int _bandId;

  QuestionnairesRepository get _repo =>
      ref.read(questionnairesRepositoryProvider);

  @override
  Future<List<Questionnaire>> build() => _repo.getQuestionnaires(_bandId);

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getQuestionnaires(_bandId));
  }

  Future<Questionnaire> create({
    required String name,
    String? description,
    String? presetKey,
  }) async {
    final created = await _repo.createQuestionnaire(
      _bandId,
      name: name,
      description: description,
      presetKey: presetKey,
    );
    final current = state.value ?? [];
    state = AsyncValue.data([...current, created]);
    return created;
  }

  Future<void> archive(int questionnaireId) async {
    final updated = await _repo.archiveQuestionnaire(_bandId, questionnaireId);
    _replace(updated);
  }

  Future<void> restoreArchived(int questionnaireId) async {
    final updated = await _repo.restoreQuestionnaire(_bandId, questionnaireId);
    _replace(updated);
  }

  Future<void> delete(int questionnaireId) async {
    await _repo.deleteQuestionnaire(_bandId, questionnaireId);
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.where((q) => q.id != questionnaireId).toList(),
    );
  }

  void _replace(Questionnaire updated) {
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.map((q) => q.id == updated.id ? updated : q).toList(),
    );
  }
}

final questionnairesProvider = AsyncNotifierProvider.family<
    QuestionnairesNotifier, List<Questionnaire>, int>(
  (arg) => QuestionnairesNotifier(arg),
);

// ── Detail + catalog ──────────────────────────────────────────────────────────

final questionnaireDetailProvider = FutureProvider.family<Questionnaire,
    ({int bandId, int questionnaireId})>(
  (ref, args) async {
    final repo = ref.watch(questionnairesRepositoryProvider);
    return repo.getQuestionnaire(args.bandId, args.questionnaireId);
  },
);

final questionnaireCatalogProvider =
    FutureProvider.family<QuestionnaireCatalog, int>(
  (ref, bandId) async {
    final repo = ref.watch(questionnairesRepositoryProvider);
    return repo.getCatalog(bandId);
  },
);
