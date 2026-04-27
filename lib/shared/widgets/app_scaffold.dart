import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/connectivity_provider.dart';
import '../../core/storage/route_storage.dart';

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
    route: '/bookings',
    label: 'Bookings',
    icon: CupertinoIcons.book,
    activeIcon: CupertinoIcons.book_fill,
  ),
  _NavDestination(
    route: '/library',
    label: 'Library',
    icon: CupertinoIcons.music_note_list,
    activeIcon: CupertinoIcons.music_note_list,
  ),
  _NavDestination(
    route: '/more',
    label: 'More',
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

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _destinations.indexWhere((d) => location.startsWith(d.route));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex(context);
    final connectivityAsync = ref.watch(connectivityProvider);

    // Save the active tab root after each build so cold-start restore works.
    // Only the tab root (e.g. /library) is saved — never nested routes that
    // require `extra` parameters and cannot be restored via redirect alone.
    final tabRoot = _destinations[selectedIndex].route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(routeStorageProvider).value?.writeLastRoute(tabRoot);
    });

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
              final route = _destinations[index].route;
              if (!GoRouterState.of(context).matchedLocation.startsWith(route)) {
                context.go(route);
              }
            },
            items: _destinations.map((d) {
              final isSelected = _destinations[selectedIndex].route == d.route;
              return BottomNavigationBarItem(
                icon: Icon(isSelected ? d.activeIcon : d.icon),
                activeIcon: Icon(d.activeIcon),
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
