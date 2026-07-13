import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_repository.dart';
import '../data/models/conversation.dart';

/// DM + band-channel list for the Messages screen. Invalidated by realtime
/// 'message' signals (band + user channels) and on thread reads.
final chatConversationsProvider = FutureProvider<List<Conversation>>(
  (ref) => ref.watch(chatRepositoryProvider).listConversations(),
);

/// Total unread across all conversations; 0 while loading or on error.
/// Drives the unread badge on the Messages tab in the bottom nav.
final chatUnreadTotalProvider = Provider<int>((ref) {
  final list = ref.watch(chatConversationsProvider).value;
  if (list == null) return 0;
  return list.fold(0, (sum, c) => sum + c.unreadCount);
});
