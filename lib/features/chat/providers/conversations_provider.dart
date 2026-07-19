import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_repository.dart';
import '../data/models/conversation.dart';

/// DM + band-channel list for the Messages screen. Invalidated by realtime
/// 'message' signals (band + user channels) and on thread reads.
final chatConversationsProvider = FutureProvider<List<Conversation>>((ref) async {
  final repo = ref.watch(chatRepositoryProvider);
  final conversations = await repo.listConversations();
  // Bulk delivered ack: this fetch IS "the app received what the server has".
  // Realtime message arrival invalidates this provider, so the refetch path
  // acks too — one hook covers both app-open and message-received triggers.
  unawaited(repo.markDelivered().catchError((_) {}));
  return conversations;
});

/// Total unread across all conversations; 0 while loading or on error.
/// Drives the unread badge on the Messages tab in the bottom nav.
final chatUnreadTotalProvider = Provider<int>((ref) {
  final list = ref.watch(chatConversationsProvider).value;
  if (list == null) return 0;
  return list.fold(0, (sum, c) => sum + c.unreadCount);
});
