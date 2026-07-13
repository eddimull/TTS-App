import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/connectivity_provider.dart';
import '../providers/band_realtime_provider.dart';
import '../providers/user_realtime_provider.dart';
import '../../features/chat/providers/conversations_provider.dart';
import '../../features/notifications/services/lifecycle_observer.dart';

class _NavDestination {
  const _NavDestination({
    required this.route,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
  final String route;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const _destinations = [
  _NavDestination(
    route: '/dashboard',
    label: 'Dashboard',
    icon: CupertinoIcons.home,
    activeIcon: CupertinoIcons.house_fill,
  ),
  _NavDestination(
    route: '/search',
    label: 'Search',
    icon: CupertinoIcons.search,
    activeIcon: CupertinoIcons.search,
  ),
  _NavDestination(
    route: '/messages',
    label: 'Messages',
    icon: CupertinoIcons.chat_bubble_2,
    activeIcon: CupertinoIcons.chat_bubble_2_fill,
  ),
  _NavDestination(
    route: '/library',
    label: 'Library',
    icon: CupertinoIcons.music_note_list,
    activeIcon: CupertinoIcons.music_note_list,
  ),
  _NavDestination(
    route: '/settings',
    label: 'Settings',
    icon: CupertinoIcons.ellipsis,
    activeIcon: CupertinoIcons.ellipsis,
  ),
];

class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  bool _showBackOnline = false;
  late final EnrichmentLifecycleObserver _enrichObserver;

  @override
  void initState() {
    super.initState();
    _enrichObserver = EnrichmentLifecycleObserver(ref);
    WidgetsBinding.instance.addObserver(_enrichObserver);
    // Cold start into the shell counts as a resume — run once after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enrichObserver.didChangeAppLifecycleState(AppLifecycleState.resumed);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_enrichObserver);
    super.dispose();
  }

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _destinations.indexWhere((d) => location.startsWith(d.route));
    return idx < 0 ? 0 : idx;
  }

  Widget _tabIcon(_NavDestination d, {required bool selected, required int unread}) {
    final icon = Icon(selected ? d.activeIcon : d.icon);
    if (d.route != '/messages' || unread <= 0) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          top: -4,
          right: -10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 16),
            height: 16,
            decoration: BoxDecoration(
              color: CupertinoColors.systemRed.resolveFrom(context),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              unread > 99 ? '99+' : '$unread',
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex(context);
    final connectivityAsync = ref.watch(connectivityProvider);
    final unread = ref.watch(chatUnreadTotalProvider);
    // Keeps the band realtime subscription alive for the whole shell.
    ref.watch(bandRealtimeProvider);
    // Keeps the per-user (DM) realtime subscription alive for the whole shell.
    ref.watch(userRealtimeProvider);

    ref.listen(connectivityProvider, (previous, next) {
      final wasOnline = previous?.value ?? true;
      final isOnline = next.value ?? true;
      if (!wasOnline && isOnline) {
        setState(() => _showBackOnline = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showBackOnline = false);
        });
      }
    });

    final isOffline = connectivityAsync.value == false;

    return Column(
      children: [
        if (isOffline) const _OfflineBanner(),
        if (_showBackOnline) const _BackOnlineBanner(),
        Expanded(child: widget.child),
        SafeArea(
          top: false,
          child: CupertinoTabBar(
            currentIndex: selectedIndex,
            onTap: (index) {
              final current = GoRouterState.of(context).matchedLocation;
              final route = _destinations[index].route;
              if (!current.startsWith(route)) {
                context.go(route);
              }
            },
            items: _destinations.map((d) {
              final isSelected = _destinations[selectedIndex].route == d.route;
              return BottomNavigationBarItem(
                icon: _tabIcon(d, selected: isSelected, unread: unread),
                activeIcon: _tabIcon(d, selected: true, unread: unread),
                label: d.label,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoColors.systemGrey.resolveFrom(context),
      child: const SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(CupertinoIcons.wifi_slash, size: 16, color: CupertinoColors.white),
              SizedBox(width: 8),
              Text(
                'No internet connection',
                style: TextStyle(color: CupertinoColors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackOnlineBanner extends StatelessWidget {
  const _BackOnlineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoColors.systemGreen,
      child: const SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(CupertinoIcons.wifi, size: 16, color: CupertinoColors.white),
              SizedBox(width: 8),
              Text(
                'Back online',
                style: TextStyle(color: CupertinoColors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
