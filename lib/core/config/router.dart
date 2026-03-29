import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/band_selector_screen.dart';
import '../../features/bookings/screens/booking_detail_screen.dart';
import '../../features/bookings/screens/bookings_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/events/screens/events_screen.dart';
import '../../features/events/screens/event_detail_screen.dart';
import '../../features/rehearsals/screens/rehearsal_detail_by_key_screen.dart';
import '../../features/rehearsals/screens/rehearsal_detail_screen.dart';
import '../../features/rehearsals/screens/rehearsals_screen.dart';
import '../../features/media/screens/media_screen.dart';
import '../../features/more/screens/more_screen.dart';
import '../../features/setlist/screens/live_session_screen.dart';
import '../../shared/providers/selected_band_provider.dart';

// ── Router provider ───────────────────────────────────────────────────────────

/// A [ChangeNotifier] that GoRouter uses as a [refreshListenable]. It bridges
/// Riverpod state changes into GoRouter's re-evaluation loop.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(this._ref) {
    _ref.listen(authProvider, (_, __) => notifyListeners());
    _ref.listen(selectedBandProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authAsync = ref.read(authProvider);
      final bandAsync = ref.read(selectedBandProvider);

      // While auth is resolving, stay put (GoRouter will re-evaluate when
      // refreshListenable fires after the async completes).
      if (authAsync.isLoading) return null;

      final authState = authAsync.valueOrNull;

      final isLoginRoute = state.matchedLocation == '/login';
      final isBandsRoute = state.matchedLocation == '/bands';

      // Not authenticated → force to login.
      if (authState == null || authState is AuthUnauthenticated) {
        return isLoginRoute ? null : '/login';
      }

      // Auth is in a transient loading-within-authenticated state.
      if (authState is AuthLoading) return null;

      // Authenticated — check band selection.
      if (authState is AuthAuthenticated) {
        // If already on login, clear it.
        if (isLoginRoute) return '/dashboard';

        final bandId = bandAsync.valueOrNull;

        if (bandId == null) {
          // No band selected yet.
          final bands = authState.bands;
          if (bands.length == 1) {
            // Auto-select the only band. Fire-and-forget — when selectBand()
            // completes it updates selectedBandProvider state, which notifies
            // the refreshListenable and triggers another redirect evaluation
            // that will find bandId != null and allow through.
            ref.read(selectedBandProvider.notifier).selectBand(bands.first.id);
            // Stay put while the async write completes.
            return null;
          }
          return isBandsRoute ? null : '/bands';
        }

        // Band is selected — don't show bands screen again unless explicitly
        // navigated there.
        if (isBandsRoute) return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/bands',
        builder: (context, state) => const BandSelectorScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/events',
        builder: (_, __) => const EventsScreen(),
      ),
      GoRoute(
        path: '/events/:key',
        builder: (_, state) =>
            EventDetailScreen(eventKey: state.pathParameters['key']!),
      ),
      GoRoute(
        path: '/events/:key/setlist/live',
        builder: (_, state) => LiveSessionScreen(
          eventKey: state.pathParameters['key']!,
        ),
      ),
      GoRoute(
        path: '/bookings',
        builder: (_, __) => const BookingsScreen(),
      ),
      GoRoute(
        path: '/bookings/:bandId/:id',
        builder: (_, state) => BookingDetailScreen(
          bandId: int.parse(state.pathParameters['bandId']!),
          bookingId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/media',
        builder: (_, __) => const MediaScreen(),
      ),
      GoRoute(
        path: '/more',
        builder: (_, __) => const MoreScreen(),
      ),
      GoRoute(
        path: '/rehearsals',
        builder: (_, __) => const RehearsalsScreen(),
      ),
      GoRoute(
        path: '/rehearsals/by-key/:key',
        builder: (_, state) => RehearsalDetailByKeyScreen(
          eventKey: state.pathParameters['key']!,
        ),
      ),
      GoRoute(
        path: '/rehearsals/:id',
        builder: (_, state) => RehearsalDetailScreen(
          rehearsalId: int.tryParse(state.pathParameters['id']!),
        ),
      ),
    ],
    errorBuilder: (context, state) => CupertinoPageScaffold(
      child: Center(
        child: Text('Page not found: ${state.error}'),
      ),
    ),
  );
});
