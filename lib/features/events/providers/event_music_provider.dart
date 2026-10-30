import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/selected_band_provider.dart';
import '../../rehearsals/data/models/rehearsal_summary.dart';
import '../../rehearsals/data/rehearsals_repository.dart';
import '../../rehearsals/providers/rehearsals_provider.dart';
import '../../setlist_editor/data/setlist_editor_repository.dart';
import '../data/event_music.dart';
import '../data/rehearsal_prep.dart';
import 'events_provider.dart';

/// The event's setlist, the band's catalog and the client's picks, via the
/// endpoint the setlist editor uses. Null when the fetch fails, so the Music
/// tab and page fall back to what the event itself carries.
final eventMusicProvider =
    FutureProvider.autoDispose.family<EventMusic?, String>((ref, key) async {
  try {
    final p = await ref.watch(setlistEditorRepositoryProvider).getSetlist(key);
    return EventMusic(
      setlist: p.setlist,
      bandSongs: p.bandSongs,
      requests: p.clientRequests,
      canWrite: p.canWrite,
    );
  } catch (_) {
    return null;
  }
});

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Rehearsals between today and the gig, soonest first (see
/// [rehearsalsBefore]). Empty for past events.
final rehearsalsBeforeEventProvider = FutureProvider.autoDispose
    .family<List<RehearsalSummary>, String>((ref, key) async {
  final event = await ref.watch(eventDetailProvider(key).future);
  final bandId = await ref.watch(selectedBandProvider.future);
  final now = clock.now();
  final gig = event.parsedDate;
  if (bandId == null || !gig.isAfter(now)) return const [];
  final schedules = await ref.watch(rehearsalsRepositoryProvider).getSchedules(
        bandId,
        until: _ymd(gig.subtract(const Duration(days: 1))),
        includeVirtual: true,
      );
  return rehearsalsBefore(schedules, gig, now);
});

/// What Add to rehearsal did.
sealed class AddToRehearsalResult {
  const AddToRehearsalResult();
}

class AddedToRehearsal extends AddToRehearsalResult {
  const AddedToRehearsal(this.added);
  final List<String> added;
}

class AlreadyOnRehearsal extends AddToRehearsalResult {
  const AlreadyOnRehearsal();
}

/// Appends a learn line for [titles] to [rehearsal]'s notes, skipping titles
/// already there. A virtual rehearsal is created first through its key.
/// Reads the rehearsal fresh so it never writes over newer notes. Throws on
/// a failed request.
Future<AddToRehearsalResult> addToRehearsal(
  WidgetRef ref, {
  required String eventKey,
  required String eventTitle,
  required DateTime eventDate,
  required RehearsalSummary rehearsal,
  required List<String> titles,
}) async {
  final repo = ref.read(rehearsalsRepositoryProvider);
  final detail = rehearsal.id != null
      ? await repo.getRehearsalDetail(rehearsal.id!)
      : await repo.getRehearsalByKey(rehearsal.eventKey!);
  final next = appendLearnLine(
    notes: detail.notes,
    eventTitle: eventTitle,
    eventDate: eventDate,
    titles: titles,
  );
  if (next == null) return const AlreadyOnRehearsal();
  await repo.updateNotes(detail.id, next.notes);
  ref.invalidate(rehearsalDetailProvider(detail.id));
  ref.invalidate(schedulesProvider);
  ref.invalidate(rehearsalsBeforeEventProvider(eventKey));
  return AddedToRehearsal(next.added);
}
