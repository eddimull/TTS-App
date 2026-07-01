import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/pusher_authorizer.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/models/planner_message.dart';
import '../data/models/planner_plan.dart';
import '../data/rehearsal_planner_repository.dart';

typedef PlannerStreamBinder = void Function(
  String channel,
  void Function(String type, Map<String, dynamic> data) onEvent,
);

/// Family key for [rehearsalPlannerProvider]. A planner session is scoped to a
/// band and (always, in the current UI) a specific rehearsal. Value equality is
/// required so the family caches one notifier per (band, rehearsal) pair.
class PlannerArgs {
  const PlannerArgs({required this.bandId, this.rehearsalId});

  final int bandId;
  final int? rehearsalId;

  @override
  bool operator ==(Object other) =>
      other is PlannerArgs &&
      other.bandId == bandId &&
      other.rehearsalId == rehearsalId;

  @override
  int get hashCode => Object.hash(bandId, rehearsalId);
}

/// Production binder: subscribes to the private Pusher channel and forwards
/// 'planner.stream' events (type + data) to [onEvent].
///
/// Verified against `lib/features/setlist/providers/live_session_provider.dart`:
/// `secureStorageProvider.readToken()`, `AppConfig.pusherKey/.pusherCluster/
/// .baseUrl`, and the `pusher_channels_flutter` ^2.6.0 API
/// (`getInstance()`, `init`, `connect`, `subscribe`, `PusherEvent.eventName/.data`).
final plannerStreamBinderProvider = Provider<PlannerStreamBinder>((ref) {
  return (channel, onEvent) async {
    final token = await ref.read(secureStorageProvider).readToken();
    if (token == null || AppConfig.pusherKey.isEmpty) return;
    final pusher = PusherChannelsFlutter.getInstance();
    await pusher.init(
      apiKey: AppConfig.pusherKey,
      cluster: AppConfig.pusherCluster,
      onAuthorizer: pusherAuthorizer(token),
    );
    await pusher.connect();
    await pusher.subscribe(
      channelName: channel,
      // The parameter must be typed `dynamic` (not `PusherEvent`). The plugin's
      // `PusherChannel.onEvent` field is `Function(dynamic event)?`, and in AOT
      // (release) builds assigning a `(PusherEvent) => …` literal to it throws
      // `TypeError: '(PusherEvent) => Null' is not a subtype of '(dynamic) => dynamic'`
      // (function params are contravariant). A tearoff is tolerated but a literal
      // is not — see live_session_provider's `_onPusherEvent`. Cast inside instead.
      onEvent: (dynamic event) {
        final e = event as PusherEvent;
        if (e.eventName != 'planner.stream') return;
        final raw = e.data;
        if (raw == null) return;
        if (raw is! String) return;
        final dynamic decoded;
        try {
          decoded = jsonDecode(raw);
        } catch (_) {
          return;
        }
        if (decoded is! Map<String, dynamic>) return;
        final type = decoded['type'] as String? ?? '';
        onEvent(type, decoded);
      },
    );
    ref.onDispose(() async {
      await pusher.unsubscribe(channelName: channel);
    });
  };
});

class RehearsalPlannerState {
  const RehearsalPlannerState({
    this.messages = const [],
    this.isStarting = false,
    this.isSending = false,
    this.error,
    this.sessionId,
  });

  final List<PlannerMessage> messages;
  final bool isStarting;
  final bool isSending;
  final String? error;
  final int? sessionId;

  RehearsalPlannerState copyWith({
    List<PlannerMessage>? messages,
    bool? isStarting,
    bool? isSending,
    String? Function()? error,
    int? sessionId,
  }) =>
      RehearsalPlannerState(
        messages: messages ?? this.messages,
        isStarting: isStarting ?? this.isStarting,
        isSending: isSending ?? this.isSending,
        error: error != null ? error() : this.error,
        sessionId: sessionId ?? this.sessionId,
      );
}

class RehearsalPlannerNotifier extends Notifier<RehearsalPlannerState> {
  RehearsalPlannerNotifier(this._args);
  final PlannerArgs _args;

  RehearsalPlannerRepository get _repo =>
      ref.read(rehearsalPlannerRepositoryProvider);

  @override
  RehearsalPlannerState build() => const RehearsalPlannerState();

  Future<void> start() async {
    if (state.sessionId != null) return;
    state = state.copyWith(isStarting: true, error: () => null);
    try {
      final r = await _repo.startSession(
        _args.bandId,
        rehearsalId: _args.rehearsalId,
      );
      // Insert a streaming placeholder for the assistant's opening turn.
      final placeholder = PlannerMessage(
        id: r.assistantMessageId,
        role: 'assistant',
        text: '',
        status: 'streaming',
      );
      state = state.copyWith(
        sessionId: r.sessionId,
        messages: [placeholder],
        isStarting: false,
      );
      _bind(r.channel);
    } catch (e) {
      state = state.copyWith(isStarting: false, error: () => e.toString());
    }
  }

  Future<void> send(String text) async {
    final sessionId = state.sessionId;
    if (sessionId == null || text.trim().isEmpty) return;
    state = state.copyWith(isSending: true, error: () => null);
    try {
      final r = await _repo.sendMessage(_args.bandId, sessionId, text.trim());
      final placeholder = PlannerMessage(
        id: r.assistantMessageId,
        role: 'assistant',
        text: '',
        status: 'streaming',
      );
      state = state.copyWith(
        messages: [...state.messages, r.userMessage, placeholder],
        isSending: false,
      );
      // Channel is the same per session; binder is idempotent enough for v1.
      _bind(r.channel);
    } catch (e) {
      state = state.copyWith(isSending: false, error: () => e.toString());
    }
  }

  bool _bound = false;
  void _bind(String channel) {
    if (_bound) return;
    _bound = true;
    ref.read(plannerStreamBinderProvider)(channel, _onStreamEvent);
  }

  void _onStreamEvent(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'text_delta':
        final delta = data['delta'] as String? ?? '';
        final deltaMessageId = (data['message_id'] as num?)?.toInt();
        if (deltaMessageId != null) {
          // Backend included message_id: apply delta to that specific message.
          _updateById(
            deltaMessageId,
            (m) => m.copyWith(text: m.text + delta),
          );
        } else {
          // No message_id (current backend behaviour): fall back to the
          // most-recent streaming placeholder.
          _updateStreaming((m) => m.copyWith(text: m.text + delta));
        }
      case 'done':
        final id = (data['message_id'] as num?)?.toInt();
        final content = data['content'] as String? ?? '';
        final suggestions =
            (data['suggestions'] as List?)?.cast<String>() ?? const <String>[];
        final dynamic planRaw = data['plan'];
        final plan =
            planRaw is Map<String, dynamic> ? PlannerPlan.fromJson(planRaw) : null;
        _updateById(
          id,
          (m) => m.copyWith(
            // If the backend sends an empty content (e.g. all text was in
            // fenced plan/suggestions blocks and got stripped), preserve the
            // already-accumulated streamed text rather than blanking the bubble.
            text: content.isNotEmpty ? content : m.text,
            suggestions: suggestions,
            plan: plan,
            status: 'complete',
          ),
        );
      case 'error':
        final id = (data['message_id'] as num?)?.toInt();
        _updateById(id, (m) => m.copyWith(status: 'failed'));
    }
  }

  /// Apply [fn] to the most recent streaming assistant message.
  void _updateStreaming(PlannerMessage Function(PlannerMessage) fn) {
    final msgs = [...state.messages];
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == 'assistant' && msgs[i].status == 'streaming') {
        msgs[i] = fn(msgs[i]);
        state = state.copyWith(messages: msgs);
        return;
      }
    }
  }

  void _updateById(int? id, PlannerMessage Function(PlannerMessage) fn) {
    if (id == null) return;
    final msgs = [...state.messages];
    final idx = msgs.indexWhere((m) => m.id == id);
    if (idx < 0) return;
    msgs[idx] = fn(msgs[idx]);
    state = state.copyWith(messages: msgs);
  }

  Future<void> retryLast() async {
    // Drop a trailing failed assistant message and re-send the preceding user text.
    final msgs = [...state.messages];
    if (msgs.isEmpty || msgs.last.status != 'failed') return;
    msgs.removeLast();
    final lastUser = msgs.lastWhere(
      (m) => m.isUser,
      orElse: () => const PlannerMessage(id: -1, role: 'user', text: ''),
    );
    state = state.copyWith(messages: msgs);
    if (lastUser.id != -1) await send(lastUser.text);
  }
}

final rehearsalPlannerProvider = NotifierProvider.family<
    RehearsalPlannerNotifier, RehearsalPlannerState, PlannerArgs>(
  RehearsalPlannerNotifier.new,
);
