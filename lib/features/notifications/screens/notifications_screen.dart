import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/context_colors.dart';
import '../../chat/utils/message_time.dart' show dateSeparatorLabel;
import '../data/models/notification_item.dart';
import '../providers/notification_feed_provider.dart';
import '../widgets/notification_row.dart';

typedef NotificationNavigate = void Function(BuildContext context, String deeplink);

/// The in-app feed (the web "bell"). Opening it marks everything seen (badge
/// clears); tapping a row marks it read and follows its deeplink.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key, this.navigate});

  final NotificationNavigate? navigate;

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationFeedProvider.notifier).markSeen();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      ref.read(notificationFeedProvider.notifier).loadMore();
    }
  }

  void _open(NotificationItem item) {
    ref.read(notificationFeedProvider.notifier).markRead(item.id);
    (widget.navigate ?? (ctx, link) => ctx.go(link))(context, item.deeplink);
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(notificationFeedProvider);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Notifications'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => ref.read(notificationFeedProvider.notifier).markAllRead(),
          child: const Text('Mark all read', style: TextStyle(fontSize: 14)),
        ),
      ),
      child: SafeArea(
        child: feed.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load notifications'),
                CupertinoButton(
                  onPressed: () => ref.read(notificationFeedProvider.notifier).refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (state) {
            if (state.items.isEmpty) {
              return const Center(child: Text("You're all caught up"));
            }
            final now = DateTime.now();
            return CustomScrollView(
              controller: _scroll,
              slivers: [
                CupertinoSliverRefreshControl(
                  onRefresh: () => ref.read(notificationFeedProvider.notifier).refresh(),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = state.items[index];
                      final prev = index == 0 ? null : state.items[index - 1];
                      final showHeader = prev == null || !_sameDay(prev.createdAt, item.createdAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showHeader)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(
                                _dayLabel(item.createdAt, now),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.secondaryText,
                                ),
                              ),
                            ),
                          NotificationRow(item: item, onTap: () => _open(item)),
                        ],
                      );
                    },
                    childCount: state.items.length,
                  ),
                ),
                if (state.loadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(padding: EdgeInsets.all(16), child: CupertinoActivityIndicator()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final la = a.toLocal(), lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  /// "Today" / "Yesterday" / weekday / date — the chat helper includes a clock,
  /// which a day header doesn't want, so strip the trailing time.
  static String _dayLabel(DateTime at, DateTime now) {
    final full = dateSeparatorLabel(at, now: now);
    final i = full.lastIndexOf(' ');
    return i > 0 ? full.substring(0, i).replaceFirst(RegExp(r' \d{1,2}:\d{2}$'), '') : full;
  }
}
