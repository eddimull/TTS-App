import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/pusher_connection.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/chat/providers/conversations_provider.dart';
import 'band_realtime_provider.dart'
    show BandChannelBinder, bandRealtimeDebounceProvider, providerInvalidatorProvider;

/// Wire event name — must match the backend's user-channel broadcast.
const String userDataChangedEvent = 'user.data-changed';

/// Production binder for the per-user private channel. Same shape as the band
/// binder so tests can override it identically.
final userChannelBinderProvider = Provider<BandChannelBinder>((ref) {
  return (channel, onEvent) =>
      ref.read(pusherConnectionProvider).subscribe(channel, onEvent);
});

/// Subscribes to the authed user's private channel and turns thin
/// `user.data-changed` signals (currently only DM 'message' signals) into
/// Riverpod invalidations. State is the subscribed user id.
///
/// Kept alive by AppScaffold, next to bandRealtimeProvider. Deliberately
/// simpler than the band notifier: no resume blanket (the band notifier's
/// resume already refreshes; DM staleness self-heals on thread open), no
/// cache clearers (no chat disk cache in v1).
class UserRealtimeNotifier extends Notifier<int?> {
  Future<void> Function()? _unsubscribe;
  Timer? _flushTimer;
  bool _pending = false;
  int _generation = 0;
  bool _disposed = false;

  @override
  int? build() {
    ref.onDispose(_teardown);
    ref.listen(authProvider, (previous, next) {
      final auth = next.value;
      _resubscribe(auth is AuthAuthenticated ? auth.user.id : null);
    }, fireImmediately: true);
    return null;
  }

  Future<void> _resubscribe(int? userId) async {
    final gen = ++_generation;
    final old = _unsubscribe;
    _unsubscribe = null;
    try {
      await old?.call();
    } catch (e) {
      debugPrint('userRealtime: unsubscribe failed: $e');
    }
    if (_disposed || gen != _generation) return;

    state = null;
    if (userId == null) return;

    final binder = ref.read(userChannelBinderProvider);
    final Future<void> Function()? unsubscribe;
    try {
      unsubscribe = await binder('private-App.Models.User.$userId', _onSignal);
    } catch (e) {
      debugPrint('userRealtime: subscribe for user $userId failed: $e');
      return;
    }
    if (_disposed || gen != _generation) {
      try {
        await unsubscribe?.call();
      } catch (e) {
        debugPrint('userRealtime: stale unsubscribe failed: $e');
      }
      return;
    }

    _unsubscribe = unsubscribe;
    if (_unsubscribe != null) state = userId;
  }

  void _onSignal(String eventName, Map<String, dynamic> data) {
    if (eventName != userDataChangedEvent) return;
    if (data['model'] != 'message') return;
    _pending = true;
    _flushTimer ??= Timer(ref.read(bandRealtimeDebounceProvider), _flush);
  }

  void _flush() {
    _flushTimer = null;
    if (!_pending) return;
    _pending = false;
    ref.read(providerInvalidatorProvider)(chatConversationsProvider);
  }

  void _teardown() {
    _disposed = true;
    _generation++;
    _flushTimer?.cancel();
    final unsubscribe = _unsubscribe;
    _unsubscribe = null;
    try {
      unsubscribe?.call().catchError((Object e) {
        debugPrint('userRealtime: teardown unsubscribe failed: $e');
      });
    } catch (e) {
      debugPrint('userRealtime: teardown unsubscribe failed: $e');
    }
  }
}

final userRealtimeProvider = NotifierProvider<UserRealtimeNotifier, int?>(
  UserRealtimeNotifier.new,
);
