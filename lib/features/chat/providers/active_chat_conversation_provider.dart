import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the conversation id of the chat thread currently visible on screen,
/// or null when no thread is open.
///
/// `ConversationThreadScreen` is opened via `context.push` (an imperative
/// go_router push), which is NOT reflected in the router's
/// `currentConfiguration.uri` — so route-string matching cannot tell whether
/// a given thread is on screen. This provider is the explicit source of
/// truth instead: the thread screen sets it to its own id in `initState` and
/// clears it in `dispose`, and `PushService` consults it to suppress a
/// local notification for a message belonging to the thread the user is
/// already looking at.
class ActiveChatConversationNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  /// Mark [conversationId] as the thread currently on screen.
  void open(int conversationId) => state = conversationId;

  /// Clear the marker, but only if it still points at [conversationId] — a
  /// push-another-thread-on-top edge (thread B opened while thread A is still
  /// disposing) must not let A's dispose clobber B's already-set value.
  void closeIfCurrent(int conversationId) {
    if (state == conversationId) state = null;
  }
}

final activeChatConversationProvider =
    NotifierProvider<ActiveChatConversationNotifier, int?>(
  ActiveChatConversationNotifier.new,
);
