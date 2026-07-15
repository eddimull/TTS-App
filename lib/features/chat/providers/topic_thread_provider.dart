import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_repository.dart';

/// Family key for a topic (comment) thread. kind: 'events'|'rehearsals'|'bookings'.
class TopicRef {
  const TopicRef({required this.kind, required this.idOrKey, this.bandId});
  final String kind;
  final String idOrKey;
  final int? bandId; // Required for bookings, ignored for others

  @override
  bool operator ==(Object other) =>
      other is TopicRef &&
      other.kind == kind &&
      other.idOrKey == idOrKey &&
      other.bandId == bandId;

  @override
  int get hashCode => Object.hash(kind, idOrKey, bandId);
}

/// Resolves (creating if needed) the comment thread for a topic and returns
/// its first page. Invalidated by realtime 'message' signals and by
/// [ChatThreadNotifier.markRead] (see chat_thread_provider.dart) so a stale
/// unread badge on a detail screen's CommentBar clears once the full
/// thread has been read.
final topicThreadProvider = FutureProvider.family<ThreadPage, TopicRef>(
  (ref, topic) => ref
      .watch(chatRepositoryProvider)
      .topicThread(kind: topic.kind, idOrKey: topic.idOrKey, bandId: topic.bandId),
);
