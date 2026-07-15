import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pusher_connection.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_message.dart';
import '../data/models/chat_participant.dart';
import '../data/models/conversation.dart';
import 'conversations_provider.dart';
import 'topic_thread_provider.dart';

/// Tears down a live channel subscription previously set up by a
/// [ChatChannelBinder].
typedef ChatChannelUnbind = Future<void> Function();

/// Binds [onEvent] to [channel]. Returns a future resolving to an unsubscribe
/// callback (or null when realtime is unavailable), or null outright (test
/// seams that never subscribe). The CALLER owns the returned callback and
/// must invoke it on dispose — the binder registers no cleanup of its own, so
/// the short-lived autoDispose thread notifier doesn't leak subscriptions
/// into the binder provider's app-long lifetime.
typedef ChatChannelBinder = Future<ChatChannelUnbind?>? Function(
  String channel,
  void Function(String eventName, Map<String, dynamic> data) onEvent,
);

/// Production binder: subscribes to the per-conversation private channel via
/// the shared PusherConnection (same pattern as plannerStreamBinderProvider,
/// except the unsubscribe callback is handed back to the calling notifier
/// instead of being tied to this provider's own — app-long — dispose).
final chatChannelBinderProvider = Provider<ChatChannelBinder>((ref) {
  return (channel, onEvent) => ref
      .read(pusherConnectionProvider)
      .subscribe(channel, (eventName, data) => onEvent(eventName, data));
});

/// How long a peer's typing indicator stays visible after their last typing
/// event. Overridden to zero in tests.
final chatTypingTtlProvider =
    Provider<Duration>((_) => const Duration(seconds: 5));

/// Debounce window for the markRead() triggered by an incoming realtime
/// message from someone else: a burst of messages arriving in quick
/// succession should collapse into a single read POST (plus the two
/// provider invalidations it drives) instead of one per message. Overridden
/// to zero in tests.
final chatMarkReadDebounceProvider =
    Provider<Duration>((_) => const Duration(milliseconds: 1500));

/// Other participants (excluding [currentUserId]) whose lastReadAt is at or
/// past the message's createdAt — i.e. they've seen it.
int seenByOthersCount(
  ChatMessage message,
  List<ChatParticipant> participants,
  int currentUserId,
) =>
    participants
        .where((p) =>
            p.userId != currentUserId &&
            p.lastReadAt != null &&
            !p.lastReadAt!.isBefore(message.createdAt))
        .length;

class ChatThreadState {
  const ChatThreadState({
    this.messages = const [],
    this.participants = const [],
    this.conversation,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.isSending = false,
    this.error,
    this.typingUsers = const {},
  });

  final List<ChatMessage> messages; // oldest → newest
  final List<ChatParticipant> participants;
  final Conversation? conversation;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isSending;
  final String? error;
  final Map<int, String> typingUsers; // userId → name

  ChatThreadState copyWith({
    List<ChatMessage>? messages,
    List<ChatParticipant>? participants,
    Conversation? conversation,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    bool? isSending,
    String? Function()? error,
    Map<int, String>? typingUsers,
  }) =>
      ChatThreadState(
        messages: messages ?? this.messages,
        participants: participants ?? this.participants,
        conversation: conversation ?? this.conversation,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        isSending: isSending ?? this.isSending,
        error: error != null ? error() : this.error,
        typingUsers: typingUsers ?? this.typingUsers,
      );
}

class ChatThreadNotifier extends Notifier<ChatThreadState> {
  ChatThreadNotifier(this._conversationId);
  final int _conversationId;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  int? get _currentUserId {
    final auth = ref.read(authProvider).value;
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  final Map<int, Timer> _typingTimers = {};
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _bound = false;
  ChatChannelUnbind? _unbind;
  Timer? _markReadDebounce;

  @override
  ChatThreadState build() {
    ref.onDispose(_teardown);
    return const ChatThreadState();
  }

  /// Runs on dispose AND on rebuild-after-invalidate: cancels every live
  /// typing timer and releases the Pusher channel subscription owned by this
  /// notifier. Resets [_bound] so a rebuilt notifier can re-bind on its next
  /// load().
  void _teardown() {
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _markReadDebounce?.cancel();
    _markReadDebounce = null;
    _bound = false;
    final unbind = _unbind;
    _unbind = null;
    unbind?.call().catchError((Object e) {
      debugPrint('chatThread: unsubscribe failed: $e');
    });
  }

  Future<void> load() async {
    if (state.isLoading) return;
    // Hold the (autoDispose) element alive while the initial fetch is in
    // flight: a bare read(...).notifier.load() with no listener registered
    // yet must not be torn down mid-request by the autoDispose scheduler.
    // Closing the link after a dispose is a no-op, so no guard is needed.
    final keepAlive = ref.keepAlive();
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final page = await _repo.messages(_conversationId);
      if (!ref.mounted) return;
      state = state.copyWith(
        messages: page.messages,
        participants: page.participants,
        conversation: page.conversation,
        hasMore: page.hasMore,
        isLoading: false,
      );
      _bind(page.channel);
      await markRead();
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, error: () => e.toString());
    } finally {
      keepAlive.close();
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.messages(_conversationId,
          beforeId: state.messages.first.id);
      if (!ref.mounted) return;
      state = state.copyWith(
        messages: [...page.messages, ...state.messages],
        hasMore: page.hasMore,
        isLoadingMore: false,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoadingMore: false, error: () => e.toString());
    }
  }

  Future<void> send({String? text, List<ChatImageUpload> images = const []}) async {
    final body = text?.trim() ?? '';
    if (body.isEmpty && images.isEmpty) return;
    state = state.copyWith(isSending: true, error: () => null);
    try {
      final message =
          await _repo.sendMessage(_conversationId, body: body, images: images);
      if (!ref.mounted) return;
      _appendIfNew(message);
      state = state.copyWith(isSending: false);
      await markRead();
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isSending: false, error: () => e.toString());
    }
  }

  Future<void> editMsg(int messageId, String body) async {
    try {
      final updated = await _repo.editMessage(messageId, body);
      if (!ref.mounted) return;
      _replace(updated);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(error: () => e.toString());
    }
  }

  Future<void> deleteMsg(int messageId) async {
    try {
      await _repo.deleteMessage(messageId);
      if (!ref.mounted) return;
      _tombstone(messageId);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(error: () => e.toString());
    }
  }

  /// Marks the newest message read and refreshes the conversation list so
  /// unread badges drop, plus every topicThreadProvider family member so a
  /// CommentBar embedded on a detail screen (event/rehearsal/booking)
  /// clears its stale unread badge for this conversation too. Best-effort.
  Future<void> markRead() async {
    final last = state.messages.isNotEmpty ? state.messages.last : null;
    if (last == null) return;
    try {
      await _repo.markRead(_conversationId, last.id);
      if (!ref.mounted) return;
      ref.invalidate(chatConversationsProvider);
      ref.invalidate(topicThreadProvider);
    } catch (e) {
      debugPrint('chatThread: markRead failed: $e');
    }
  }

  /// Called by the composer on text changes. Throttled to one POST per 3s.
  void notifyTyping() {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) < const Duration(seconds: 3)) return;
    _lastTypingSent = now;
    _repo.sendTyping(_conversationId).catchError((Object e) {
      debugPrint('chatThread: typing failed: $e');
    });
  }

  void _bind(String channel) {
    if (_bound || channel.isEmpty) return;
    _bound = true;
    final pending =
        ref.read(chatChannelBinderProvider)(channel, _onChannelEvent);
    pending?.then((unbind) {
      if (unbind == null) return;
      if (!ref.mounted) {
        // Disposed while the subscribe round-trip was in flight: release the
        // channel immediately instead of leaking it.
        unbind().catchError((Object e) {
          debugPrint('chatThread: unsubscribe failed: $e');
        });
        return;
      }
      _unbind = unbind;
    }).catchError((Object e) {
      debugPrint('chatThread: bind failed: $e');
    });
  }

  void _onChannelEvent(String eventName, Map<String, dynamic> data) {
    // A live event can still arrive between dispose and the async channel
    // unsubscribe completing — drop it rather than touch disposed state.
    if (!ref.mounted) return;
    switch (eventName) {
      case 'message.created':
        final raw = data['message'];
        if (raw is! Map<String, dynamic>) return;
        final message = ChatMessage.fromJson(raw);
        final appended = _appendIfNew(message);
        // Only mark read when we actually appended a message authored by
        // someone else — our own echo (from a send() we already handled)
        // must not re-trigger a read POST, and a duplicate must not either.
        if (appended && message.userId != _currentUserId) {
          _debouncedMarkRead();
        }
      case 'message.updated':
        final raw = data['message'];
        if (raw is! Map<String, dynamic>) return;
        _replace(ChatMessage.fromJson(raw));
      case 'message.deleted':
        final id = (data['message_id'] as num?)?.toInt();
        if (id != null) _tombstone(id);
      case 'conversation.read':
        final userId = (data['user_id'] as num?)?.toInt();
        final at = DateTime.tryParse(data['last_read_at'] as String? ?? '');
        if (userId == null || at == null) return;
        state = state.copyWith(participants: [
          for (final p in state.participants)
            p.userId == userId ? p.copyWith(lastReadAt: at) : p,
        ]);
      case 'conversation.typing':
        final userId = (data['user_id'] as num?)?.toInt();
        final name = data['name'] as String? ?? '';
        if (userId == null || userId == _currentUserId) return;
        state = state
            .copyWith(typingUsers: {...state.typingUsers, userId: name});
        _typingTimers[userId]?.cancel();
        _typingTimers[userId] = Timer(ref.read(chatTypingTtlProvider), () {
          final next = {...state.typingUsers}..remove(userId);
          state = state.copyWith(typingUsers: next);
        });
    }
  }

  /// Appends [message] unless it's already present (dedupes our own send()
  /// echo and duplicate realtime deliveries). Returns whether it appended.
  bool _appendIfNew(ChatMessage message) {
    if (state.messages.any((m) => m.id == message.id)) return false;
    state = state.copyWith(messages: [...state.messages, message]);
    return true;
  }

  /// Debounced markRead() for realtime-appended messages from other users:
  /// a burst of incoming messages collapses into a single read POST (and its
  /// two provider invalidations) fired [chatMarkReadDebounceProvider] after
  /// the last one, instead of one per message.
  void _debouncedMarkRead() {
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(ref.read(chatMarkReadDebounceProvider), () {
      _markReadDebounce = null;
      markRead();
    });
  }

  void _replace(ChatMessage message) {
    state = state.copyWith(messages: [
      for (final m in state.messages) m.id == message.id ? message : m,
    ]);
  }

  void _tombstone(int messageId) {
    state = state.copyWith(messages: [
      for (final m in state.messages)
        m.id == messageId ? m.copyWith(isDeleted: true, body: '') : m,
    ]);
  }
}

/// autoDispose: the thread screen's `watch` keeps a conversation's notifier
/// alive while it's on screen; navigating away (or switching conversations)
/// drops the last listener, which tears down the Pusher subscription and
/// typing timers via [ChatThreadNotifier._teardown]. Thread state is refetched
/// on reopen.
final chatThreadProvider =
    NotifierProvider.autoDispose.family<ChatThreadNotifier, ChatThreadState, int>(
  ChatThreadNotifier.new,
);
