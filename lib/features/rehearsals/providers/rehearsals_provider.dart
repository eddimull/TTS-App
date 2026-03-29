import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/rehearsals_repository.dart';
import '../data/models/rehearsal_detail.dart';
import '../data/models/rehearsal_schedule.dart';

// ── Rehearsal schedules (list) ────────────────────────────────────────────────

/// Provides the list of [RehearsalSchedule] for a given band, each including
/// its upcoming rehearsals.
///
/// Usage:
/// ```dart
/// final schedules = ref.watch(schedulesProvider(bandId));
/// ```
final schedulesProvider =
    AutoDisposeFutureProviderFamily<List<RehearsalSchedule>, int>(
        (ref, bandId) async {
  final repo = ref.watch(rehearsalsRepositoryProvider);
  return repo.getSchedules(bandId);
});

// ── Rehearsal detail (single) ─────────────────────────────────────────────────

/// Provides the [RehearsalDetail] for a single rehearsal by integer id.
final rehearsalDetailProvider =
    AutoDisposeFutureProviderFamily<RehearsalDetail, int>(
        (ref, rehearsalId) async {
  final repo = ref.watch(rehearsalsRepositoryProvider);
  return repo.getRehearsalDetail(rehearsalId);
});

/// Provides the [RehearsalDetail] resolved from a virtual key string.
/// Used when navigating from the dashboard to a virtual rehearsal.
final rehearsalDetailByKeyProvider =
    AutoDisposeFutureProviderFamily<RehearsalDetail, String>(
        (ref, key) async {
  final repo = ref.watch(rehearsalsRepositoryProvider);
  return repo.getRehearsalByKey(key);
});
