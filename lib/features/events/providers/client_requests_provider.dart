import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../setlist_editor/data/setlist_editor_repository.dart';
import '../data/client_requests_summary.dart';

/// The client's song picks for an event, via the setlist endpoint the editor
/// already uses. Null when there are none or the fetch fails — the Music tab
/// then just leaves the card out.
final eventClientRequestsProvider = FutureProvider.autoDispose
    .family<ClientRequestsSummary?, String>((ref, eventKey) async {
  try {
    final payload =
        await ref.watch(setlistEditorRepositoryProvider).getSetlist(eventKey);
    return summarizeClientRequests(payload.clientRequests, payload.bandSongs);
  } catch (_) {
    return null;
  }
});
