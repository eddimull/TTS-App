import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/client_requests_summary.dart';
import 'event_music_provider.dart';

/// The client's song picks for an event. Null when there are none or the
/// fetch fails — the Music tab then just leaves the card out.
final eventClientRequestsProvider = FutureProvider.autoDispose
    .family<ClientRequestsSummary?, String>((ref, eventKey) async {
  final music = await ref.watch(eventMusicProvider(eventKey).future);
  return music?.requestsSummary;
});
