import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/cache/cache_invalidator.dart';
import '../data/bookings_repository.dart';
import '../data/models/contract_term.dart';
import 'bookings_provider.dart' show bookingDetailProvider;

typedef ContractEditorKey = ({int bandId, int bookingId});

class ContractEditorState {
  const ContractEditorState({
    required this.terms,
    required this.unsavedChanges,
    this.lastSavedAt,
    this.envelopeId,
    this.buyerNameOverride,
  });

  final List<ContractTerm> terms;
  final bool unsavedChanges;
  final DateTime? lastSavedAt;
  final String? envelopeId;
  final String? buyerNameOverride;

  ContractEditorState copyWith({
    List<ContractTerm>? terms,
    bool? unsavedChanges,
    DateTime? lastSavedAt,
    String? envelopeId,
    String? buyerNameOverride,
  }) =>
      ContractEditorState(
        terms: terms ?? this.terms,
        unsavedChanges: unsavedChanges ?? this.unsavedChanges,
        lastSavedAt: lastSavedAt ?? this.lastSavedAt,
        envelopeId: envelopeId ?? this.envelopeId,
        buyerNameOverride: buyerNameOverride ?? this.buyerNameOverride,
      );
}

/// Owns the contract editor's working state: list of [ContractTerm]s with
/// stable ids, an [unsavedChanges] flag, the last-saved timestamp, and the
/// contract's envelope id. Text edits are debounced (500ms); structural
/// changes (add/remove/reorder) save immediately.
class ContractEditorNotifier extends AsyncNotifier<ContractEditorState> {
  ContractEditorNotifier(this._key);

  final ContractEditorKey _key;

  Timer? _debounce;

  @override
  Future<ContractEditorState> build() async {
    ref.onDispose(() {
      _debounce?.cancel();
    });

    final detail = await ref.watch(bookingDetailProvider(_key).future);
    final stored = detail.contract?.customTerms;
    final terms = stored ?? await loadInitialTermsForTest();
    final withIds = _assignStableIds(terms);

    return ContractEditorState(
      terms: withIds,
      unsavedChanges: stored == null,
      lastSavedAt: detail.contract?.updatedAt,
      envelopeId: detail.contract?.envelopeId,
      buyerNameOverride: detail.contract?.buyerNameOverride,
    );
  }

  /// Loads the bundled default-terms JSON.
  /// Public-named-for-test so unit tests can exercise it; also the production
  /// path when a booking has no stored custom terms.
  Future<List<ContractTerm>> loadInitialTermsForTest() async {
    final raw =
        await rootBundle.loadString('assets/contract/initial_terms.json');
    final parsed = jsonDecode(raw) as List<dynamic>;
    return parsed
        .cast<Map<String, dynamic>>()
        .map(ContractTerm.fromJson)
        .toList();
  }

  List<ContractTerm> _assignStableIds(List<ContractTerm> terms) {
    return [
      for (var i = 0; i < terms.length; i++)
        ContractTerm(id: i, title: terms[i].title, content: terms[i].content),
    ];
  }

  void updateTitle(int id, String title) {
    final current = state.value;
    if (current == null) return;
    final newTerms = [
      for (final t in current.terms)
        if (t.id == id) t.copyWith(title: title) else t,
    ];
    state = AsyncData(current.copyWith(terms: newTerms, unsavedChanges: true));
    _scheduleSave();
  }

  void updateContent(int id, String content) {
    final current = state.value;
    if (current == null) return;
    final newTerms = [
      for (final t in current.terms)
        if (t.id == id) t.copyWith(content: content) else t,
    ];
    state = AsyncData(current.copyWith(terms: newTerms, unsavedChanges: true));
    _scheduleSave();
  }

  void updateBuyerNameOverride(String value) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(buyerNameOverride: value, unsavedChanges: true),
    );
    _scheduleSave();
  }

  Future<void> addSection() async {
    final current = state.value;
    if (current == null) return;
    final maxId = current.terms.isEmpty
        ? -1
        : current.terms.map((t) => t.id).reduce((a, b) => a > b ? a : b);
    final newTerms = [
      ...current.terms,
      ContractTerm(id: maxId + 1, title: '', content: ''),
    ];
    state = AsyncData(current.copyWith(terms: newTerms, unsavedChanges: true));
    await save(force: true);
  }

  Future<void> removeSection(int id) async {
    final current = state.value;
    if (current == null) return;
    final newTerms = current.terms.where((t) => t.id != id).toList();
    state = AsyncData(current.copyWith(terms: newTerms, unsavedChanges: true));
    await save(force: true);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = state.value;
    if (current == null) return;
    final reordered = reorderForTest(current.terms, oldIndex, newIndex);
    state =
        AsyncData(current.copyWith(terms: reordered, unsavedChanges: true));
    await save(force: true);
  }

  /// Pure function — exposed for testing the reorder math.
  /// Implements ReorderableListView semantics: when moving an item down,
  /// `newIndex` is the position AFTER removal of the item from `oldIndex`,
  /// so the caller's `newIndex` needs `-1` adjustment.
  static List<ContractTerm> reorderForTest(
    List<ContractTerm> terms,
    int oldIndex,
    int newIndex,
  ) {
    final list = [...terms];
    final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final moved = list.removeAt(oldIndex);
    list.insert(adjustedNew, moved);
    return list;
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => save());
  }

  Future<void> save({bool force = false}) async {
    final current = state.value;
    if (current == null) return;
    if (!force && !current.unsavedChanges) return;

    final repo = ref.read(bookingsRepositoryProvider);
    try {
      await repo.saveContractTerms(
        _key.bandId,
        _key.bookingId,
        current.terms,
        buyerNameOverride: current.buyerNameOverride,
      );
      state = AsyncData(
        current.copyWith(
          unsavedChanges: false,
          lastSavedAt: DateTime.now(),
        ),
      );
      ref.read(cacheInvalidatorProvider).onBookingDetailChanged(
            bandId: _key.bandId,
            bookingId: _key.bookingId,
          );
    } catch (e, st) {
      // Surface the error without losing the user's in-flight edits.
      // copyWithPrevious keeps state.value pointing at the prior terms
      // so the editor UI can keep rendering them while showing a retry banner.
      // The method is marked @internal by Riverpod but is the documented way
      // to retain prior data on the error side in 3.x.
      // ignore: invalid_use_of_internal_member
      state = AsyncValue<ContractEditorState>.error(e, st)
          // ignore: invalid_use_of_internal_member
          .copyWithPrevious(state);
    }
  }
}

final contractEditorProvider = AsyncNotifierProvider.autoDispose
    .family<ContractEditorNotifier, ContractEditorState, ContractEditorKey>(
  ContractEditorNotifier.new,
);
