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

typedef ChatChannelBinder = void Function(
  String channel,
  void Function(String eventName, Map<String, dynamic> data) onEvent,
);

/// Production binder: subscribes to the per-conversation private channel via
/// the shared PusherConnection (same pattern as plannerStreamBinderProvider).
final chatChannelBinderProvider = Provider<ChatChannelBinder>((ref) {
  return (channel, onEvent) async {
    final unsubscribe = await ref
        .read(pusherConnectionProvider)
        .subscribe(channel, (eventName, data) => onEvent(eventName, data));
    if (unsubscribe != null) {
      ref.onDispose(() {
        unsubscribe().catchError((Object e) {
          debugPrint('chatThread: unsubscribe failed: $e');
        });
      });
    }
  };
});

/// How long a peer's typing indicator stays visible after their last typing
/// event. Overridden to zero in tests.
final chatTypingTtlProvider =
    Provider<Duration>((_) => const Duration(seconds: 5));

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

  @override
  ChatThreadState build() {
    ref.onDispose(() {
      for (final t in _typingTimers.values) {
        t.cancel();
      }
    });
    return const ChatThreadState();
  }

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final page = await _repo.messages(_conversationId);
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
      state = state.copyWith(isLoading: false, error: () => e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.messages(_conversationId,
          beforeId: state.messages.first.id);
      state = state.copyWith(
        messages: [...page.messages, ...state.messages],
        hasMore: page.hasMore,
        isLoadingMore: false,
      );
    } catch (e) {
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
      _appendIfNew(message);
      state = state.copyWith(isSending: false);
      await markRead();
    } catch (e) {
      state = state.copyWith(isSending: false, error: () => e.toString());
    }
  }

  Future<void> editMsg(int messageId, String body) async {
    try {
      final updated = await _repo.editMessage(messageId, body);
      _replace(updated);
    } catch (e) {
      state = state.copyWith(error: () => e.toString());
    }
  }

  Future<void> deleteMsg(int messageId) async {
    try {
      await _repo.deleteMessage(messageId);
      _tombstone(messageId);
    } catch (e) {
      state = state.copyWith(error: () => e.toString());
    }
  }

  /// Marks the newest message read and refreshes the conversation list so
  /// unread badges drop. Best-effort.
  Future<void> markRead() async {
    final last = state.messages.isNotEmpty ? state.messages.last : null;
    if (last == null) return;
    try {
      await _repo.markRead(_conversationId, last.id);
      if (!ref.mounted) return;
      ref.invalidate(chatConversationsProvider);
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
    ref.read(chatChannelBinderProvider)(channel, _onChannelEvent);
  }

  void _onChannelEvent(String eventName, Map<String, dynamic> data) {
    switch (eventName) {
      case 'message.created':
        final raw = data['message'];
        if (raw is! Map<String, dynamic>) return;
        _appendIfNew(ChatMessage.fromJson(raw));
        // Someone else wrote while we're looking at the thread: mark it read.
        markRead();
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

  void _appendIfNew(ChatMessage message) {
    if (state.messages.any((m) => m.id == message.id)) return;
    state = state.copyWith(messages: [...state.messages, message]);
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

final chatThreadProvider =
    NotifierProvider.family<ChatThreadNotifier, ChatThreadState, int>(
  ChatThreadNotifier.new,
);
