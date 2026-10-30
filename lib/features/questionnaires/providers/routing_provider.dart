import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../bookings/data/bookings_repository.dart';
import '../../../shared/cache/cache_invalidator.dart';
import '../data/models/routing_preview.dart';
import 'questionnaire_instances_provider.dart';
import 'questionnaires_provider.dart';

typedef RoutingKey = ({int bandId, int instanceId});

/// The routing preview for an instance. The value is null when the server has
/// no routing endpoint yet (404); callers hide the new entry point and keep
/// the per-field Apply UI.
final routingPreviewProvider =
    FutureProvider.family<RoutingPreview?, RoutingKey>((ref, key) async {
  final repo = ref.watch(questionnairesRepositoryProvider);
  return repo.fetchRouting(key.bandId, key.instanceId);
});

/// Tracks what the user has chosen on the Send to Event screen.
class RoutingSelection {
  const RoutingSelection({
    this.checked = const {},
    this.targetOverrides = const {},
    this.remember = const {},
    this.songResolutions = const {},
    this.venueResolution,
    this.sending = false,
  });

  /// Response ids that will be sent.
  final Set<int> checked;

  /// Per-answer destination overrides (Send-to sheet), by response id.
  final Map<int, String> targetOverrides;

  /// Response ids whose override should also be saved on the template.
  final Set<int> remember;

  /// song id -> `must_play` | `do_not_play`.
  final Map<int, String> songResolutions;

  /// `booking` | `form`, or null while unresolved.
  final String? venueResolution;
  final bool sending;

  RoutingSelection copyWith({
    Set<int>? checked,
    Map<int, String>? targetOverrides,
    Set<int>? remember,
    Map<int, String>? songResolutions,
    String? venueResolution,
    bool clearVenue = false,
    bool? sending,
  }) =>
      RoutingSelection(
        checked: checked ?? this.checked,
        targetOverrides: targetOverrides ?? this.targetOverrides,
        remember: remember ?? this.remember,
        songResolutions: songResolutions ?? this.songResolutions,
        venueResolution:
            clearVenue ? null : (venueResolution ?? this.venueResolution),
        sending: sending ?? this.sending,
      );

  bool isResolved(RoutingConflict c) => c.isSong
      ? songResolutions.containsKey(c.songId)
      : venueResolution != null;

  /// Conflicts the user still has to decide; they're skipped on send.
  int unresolvedCount(RoutingPreview p) =>
      p.knownConflicts.where((c) => !isResolved(c)).length;

  /// Answers going out: ticked items, ticked unrouted picks, and resolved
  /// conflicts. Unresolved conflicts never count.
  int sendCount(RoutingPreview p) {
    final itemCount =
        p.allItems.where((i) => checked.contains(i.responseId)).length;
    final pickCount = p.unrouted
        .where((u) =>
            checked.contains(u.responseId) &&
            targetOverrides.containsKey(u.responseId))
        .length;
    final resolved = p.knownConflicts.where(isResolved).length;
    return itemCount + pickCount + resolved;
  }

  /// Number of distinct destinations (the "16 items -> 5 places" subtitle).
  int placeCount(RoutingPreview p) =>
      p.groups.where((g) => g.items.isNotEmpty).length;

  /// Body for `POST …/route`.
  ({List<Map<String, dynamic>> items, Map<String, dynamic> resolutions})
      payload(RoutingPreview p) {
    final items = <Map<String, dynamic>>[];
    for (final i in p.allItems) {
      if (!checked.contains(i.responseId)) continue;
      items
          .add(_entry(i.responseId, targetOverrides[i.responseId] ?? i.target));
    }
    for (final u in p.unrouted) {
      final t = targetOverrides[u.responseId];
      if (t == null || !checked.contains(u.responseId)) continue;
      items.add(_entry(u.responseId, t));
    }
    final resolutions = <String, dynamic>{};
    final songs = <String, String>{};
    for (final c in p.knownConflicts.where((c) => c.isSong)) {
      final r = songResolutions[c.songId];
      if (r != null) songs['${c.songId}'] = r;
    }
    if (songs.isNotEmpty) resolutions['songs'] = songs;
    if (venueResolution != null && p.knownConflicts.any((c) => c.isVenue)) {
      resolutions['venue'] = venueResolution;
    }
    return (items: items, resolutions: resolutions);
  }

  Map<String, dynamic> _entry(int responseId, String target) => {
        'response_id': responseId,
        'target': target,
        if (remember.contains(responseId)) 'remember': true,
      };
}

class RoutingSelectionNotifier extends Notifier<RoutingSelection> {
  RoutingSelectionNotifier(this._key);

  final RoutingKey _key;

  @override
  RoutingSelection build() {
    // A refetch (e.g. after adding a contact) merges into the current
    // selection instead of resetting what the user already chose.
    ref.listen(routingPreviewProvider(_key), (prev, next) {
      final fresh = next.value;
      final old = prev?.value;
      if (fresh == null || old == null) return;
      final oldIds = old.allItems.map((i) => i.responseId).toSet();
      final freshIds = fresh.allItems.map((i) => i.responseId).toSet();
      state = state.copyWith(checked: {
        ...state.checked.where((id) =>
            freshIds.contains(id) ||
            state.targetOverrides.containsKey(id)),
        for (final i in fresh.allItems)
          if (!oldIds.contains(i.responseId) && i.defaultChecked)
            i.responseId,
      });
    });
    final preview = ref.read(routingPreviewProvider(_key)).value;
    if (preview == null) return const RoutingSelection();
    return RoutingSelection(
      checked: {
        for (final i in preview.allItems)
          if (i.defaultChecked) i.responseId,
      },
      songResolutions: {
        for (final c in preview.knownConflicts)
          if (c.isSong && c.songId != null && c.resolution != null)
            c.songId!: c.resolution!,
      },
      venueResolution: preview.knownConflicts
          .where((c) => c.isVenue)
          .map((c) => c.resolution)
          .firstOrNull,
    );
  }

  void toggle(int responseId) {
    final next = {...state.checked};
    if (!next.remove(responseId)) next.add(responseId);
    state = state.copyWith(checked: next);
  }

  /// Applies a Send-to sheet choice. A null [target] means "Don't send".
  void setTarget(int responseId, String? target, {bool remember = false}) {
    final checked = {...state.checked};
    final overrides = {...state.targetOverrides};
    final remembered = {...state.remember};
    if (target == null) {
      checked.remove(responseId);
      overrides.remove(responseId);
      remembered.remove(responseId);
    } else {
      checked.add(responseId);
      overrides[responseId] = target;
      remember ? remembered.add(responseId) : remembered.remove(responseId);
    }
    state = state.copyWith(
        checked: checked, targetOverrides: overrides, remember: remembered);
  }

  void resolveSong(int songId, String resolution) => state = state.copyWith(
      songResolutions: {...state.songResolutions, songId: resolution});

  void resolveVenue(String resolution) =>
      state = state.copyWith(venueResolution: resolution);

  /// Adds a questionnaire contact to the booking through the bookings
  /// repository, then refetches the preview. Errors propagate to the caller.
  Future<void> addContact(RoutingContact contact, int bookingId) async {
    final link = ref.keepAlive();
    try {
      await ref
          .read(bookingsRepositoryProvider)
          .addContact(_key.bandId, bookingId, contact.toAddContactBody());
      ref.invalidate(routingPreviewProvider(_key));
      await ref.read(routingPreviewProvider(_key).future);
    } finally {
      link.close();
    }
  }

  /// Sends the selection. Records the application for the event screen's
  /// session-only undo banner and refreshes dependent providers.
  Future<RouteResult> send(RoutingPreview preview) async {
    final body = state.payload(preview);
    // The screen may be popped while the request is in flight; keep this
    // notifier alive until the completion handling below has run.
    final link = ref.keepAlive();
    state = state.copyWith(sending: true);
    try {
      final result = await ref.read(questionnairesRepositoryProvider).route(
            _key.bandId,
            _key.instanceId,
            items: body.items,
            resolutions: body.resolutions,
          );
      ref.read(lastRoutedApplicationProvider.notifier).set(RoutedApplication(
            bandId: _key.bandId,
            applicationId: result.applicationId,
            applied: result.applied,
            eventId: result.eventId,
            eventKey: result.eventKey,
          ));
      // Drops cached event details (memory and disk) and client picks.
      ref
          .read(cacheInvalidatorProvider)
          .onQuestionnaireAppliedToEvents(bandId: _key.bandId);
      ref.invalidate(instanceDetailProvider((
        bandId: _key.bandId,
        instanceId: _key.instanceId,
      )));
      ref.invalidate(routingPreviewProvider(_key));
      return result;
    } finally {
      // The notifier rebuilds when the preview is invalidated; guard so a
      // disposed notifier doesn't throw.
      if (ref.mounted) state = state.copyWith(sending: false);
      link.close();
    }
  }
}

final routingSelectionProvider = NotifierProvider.autoDispose
    .family<RoutingSelectionNotifier, RoutingSelection, RoutingKey>(
  (key) => RoutingSelectionNotifier(key),
);

/// The most recent send in this app session, shown as an undo banner on the
/// matching event. Cleared on undo or dismissal; never persisted.
class RoutedApplication {
  const RoutedApplication({
    required this.bandId,
    required this.applicationId,
    required this.applied,
    this.eventId,
    this.eventKey,
  });

  final int bandId;
  final int applicationId;
  final int applied;
  final int? eventId;
  final String? eventKey;

  bool matches({required int id, required String key}) =>
      (eventId != null && eventId == id) ||
      (eventKey != null && eventKey == key);
}

class LastRoutedApplicationNotifier extends Notifier<RoutedApplication?> {
  @override
  RoutedApplication? build() => null;

  void set(RoutedApplication? value) => state = value;
}

final lastRoutedApplicationProvider =
    NotifierProvider<LastRoutedApplicationNotifier, RoutedApplication?>(
        LastRoutedApplicationNotifier.new);

/// Undoes [app]; the server answers 409 if the event was edited since.
///
/// Takes a [ProviderContainer] rather than a `WidgetRef` so the completion
/// handling still works if the banner is disposed while the request is
/// pending. Capture it with `ProviderScope.containerOf(context)` before the
/// first await.
Future<void> undoRoutedApplication(
    ProviderContainer container, RoutedApplication app) async {
  await container
      .read(questionnairesRepositoryProvider)
      .undoApplication(app.bandId, app.applicationId);
  container.read(lastRoutedApplicationProvider.notifier).set(null);
  container
      .read(cacheInvalidatorProvider)
      .onQuestionnaireAppliedToEvents(bandId: app.bandId);
  // Applied statuses and default selections changed back.
  container.invalidate(instanceDetailProvider);
  container.invalidate(routingPreviewProvider);
}
