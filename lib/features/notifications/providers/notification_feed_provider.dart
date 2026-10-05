import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/notification_item.dart';
import '../data/notification_repository.dart';

class NotificationFeedState {
  const NotificationFeedState({
    this.items = const [],
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<NotificationItem> items;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  NotificationFeedState copyWith({
    List<NotificationItem>? items,
    Object? nextCursor = _unset,
    bool? loadingMore,
  }) =>
      NotificationFeedState(
        items: items ?? this.items,
        nextCursor: nextCursor == _unset ? this.nextCursor : nextCursor as String?,
        loadingMore: loadingMore ?? this.loadingMore,
      );

  static const _unset = Object();
}

/// Unseen count for the Dashboard bell. Invalidated by the user-channel
/// 'notification' signal, by markSeen(), and on resume.
final unseenNotificationsCountProvider = FutureProvider<int>((ref) {
  return ref.watch(notificationRepositoryProvider).unseenCount();
});

/// The feed itself: first page on build, cursor pagination, optimistic reads.
/// Refetches on app resume (Pusher has no replay while backgrounded).
class NotificationFeedNotifier extends AsyncNotifier<NotificationFeedState> {
  AppLifecycleListener? _lifecycle;

  @override
  Future<NotificationFeedState> build() async {
    ref.onDispose(() {
      _lifecycle?.dispose();
      _lifecycle = null;
    });
    _lifecycle ??= AppLifecycleListener(onResume: () {
      ref.invalidateSelf();
      ref.invalidate(unseenNotificationsCountProvider);
    });
    final page = await ref.watch(notificationRepositoryProvider).list();
    return NotificationFeedState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(notificationRepositoryProvider).list(cursor: current.nextCursor);
      if (!ref.mounted) return;
      final seen = current.items.map((i) => i.id).toSet();
      state = AsyncData(current.copyWith(
        items: [...current.items, ...page.items.where((i) => !seen.contains(i.id))],
        nextCursor: page.nextCursor,
        loadingMore: false,
      ));
    } catch (_) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }

  Future<void> markRead(String id) async {
    final current = state.value;
    if (current == null) return;
    final now = DateTime.now();
    state = AsyncData(current.copyWith(
      items: [for (final i in current.items) i.id == id && i.isUnread ? i.copyWith(readAt: now) : i],
    ));
    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
      if (!ref.mounted) return;
    } catch (_) {
      // best-effort; the next refresh reconciles
    }
  }

  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null) return;
    final now = DateTime.now();
    state = AsyncData(current.copyWith(
      items: [for (final i in current.items) i.isUnread ? i.copyWith(readAt: now) : i],
    ));
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
      if (!ref.mounted) return;
    } catch (_) {}
  }

  Future<void> markSeen() async {
    try {
      await ref.read(notificationRepositoryProvider).markSeen();
      if (!ref.mounted) return;
    } catch (_) {
      return;
    }
    ref.invalidate(unseenNotificationsCountProvider);
  }
}

final notificationFeedProvider =
    AsyncNotifierProvider<NotificationFeedNotifier, NotificationFeedState>(
  NotificationFeedNotifier.new,
);
