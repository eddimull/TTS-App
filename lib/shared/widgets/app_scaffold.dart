import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/connectivity_provider.dart';

/// Destination configuration for the bottom navigation bar.
class _NavDestination {
  const _NavDestination({
    required this.route,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String route;
  final String label;
  final Widget icon;
  final Widget selectedIcon;
}

const _destinations = [
  _NavDestination(
    route: '/dashboard',
    label: 'Dashboard',
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home),
  ),
  _NavDestination(
    route: '/events',
    label: 'Events',
    icon: Icon(Icons.calendar_month_outlined),
    selectedIcon: Icon(Icons.calendar_month),
  ),
  _NavDestination(
    route: '/bookings',
    label: 'Bookings',
    icon: Icon(Icons.book_outlined),
    selectedIcon: Icon(Icons.book),
  ),
  _NavDestination(
    route: '/media',
    label: 'Media',
    icon: Icon(Icons.perm_media_outlined),
    selectedIcon: Icon(Icons.perm_media),
  ),
  _NavDestination(
    route: '/more',
    label: 'More',
    icon: Icon(Icons.menu_outlined),
    selectedIcon: Icon(Icons.menu),
  ),
];

class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _destinations.indexWhere((d) => location.startsWith(d.route));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex(context);
    final connectivityAsync = ref.watch(connectivityProvider);

    // Show snackbar when connection is restored.
    ref.listen(connectivityProvider, (previous, next) {
      final wasOnline = previous?.valueOrNull ?? true;
      final isOnline = next.valueOrNull ?? true;

      if (!wasOnline && isOnline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Back online'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });

    final isOffline = connectivityAsync.valueOrNull == false;

    return Scaffold(
      body: Column(
        children: [
          if (isOffline) const _OfflineBanner(),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          final route = _destinations[index].route;
          if (!GoRouterState.of(context).matchedLocation.startsWith(route)) {
            context.go(route);
          }
        },
        destinations: _destinations
            .map(
              (d) => NavigationDestination(
                icon: d.icon,
                selectedIcon: d.selectedIcon,
                label: d.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade800,
      child: const SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.wifi_off, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text(
                'No internet connection',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
