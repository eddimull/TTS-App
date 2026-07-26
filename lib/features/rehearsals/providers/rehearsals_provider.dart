import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/rehearsals_repository.dart';
import '../data/models/rehearsal_detail.dart';
import '../data/models/rehearsal_schedule.dart';

// ── Rehearsal schedules (list) ────────────────────────────────────────────────

/// Notifier for the rehearsals window days.
class SchedulesWindowDaysNotifier extends Notifier<int> {
  @override
  int build() => 90;

  /// Extends the window by the given number of days.
  void extend(int days) => state += days;
}

/// Days ahead the rehearsals list covers. "Show more" bumps this by 90; a
/// pull-to-refresh keeps the current window.
final schedulesWindowDaysProvider =
    NotifierProvider<SchedulesWindowDaysNotifier, int>(
  SchedulesWindowDaysNotifier.new,
);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Provides the list of [RehearsalSchedule] for a given band, each including
/// its upcoming rehearsals.
///
/// Usage:
/// ```dart
/// final schedules = ref.watch(schedulesProvider(bandId));
/// ```
final schedulesProvider =
    FutureProvider.family<List<RehearsalSchedule>, int>(
        (ref, bandId) async {
  final windowDays = ref.watch(schedulesWindowDaysProvider);
  final until = DateTime.now().add(Duration(days: windowDays));
  final repo = ref.watch(rehearsalsRepositoryProvider);
  return repo.getSchedules(bandId, until: _ymd(until), includeVirtual: true);
});

// ── Rehearsal detail (single) ─────────────────────────────────────────────────

/// Provides the [RehearsalDetail] for a single rehearsal by integer id.
final rehearsalDetailProvider =
    FutureProvider.family<RehearsalDetail, int>(
        (ref, rehearsalId) async {
  final repo = ref.watch(rehearsalsRepositoryProvider);
  return repo.getRehearsalDetail(rehearsalId);
});

/// Provides the [RehearsalDetail] resolved from a virtual key string.
/// Used when navigating from the dashboard to a virtual rehearsal.
final rehearsalDetailByKeyProvider =
    FutureProvider.family<RehearsalDetail, String>(
        (ref, key) async {
  final repo = ref.watch(rehearsalsRepositoryProvider);
  return repo.getRehearsalByKey(key);
});
