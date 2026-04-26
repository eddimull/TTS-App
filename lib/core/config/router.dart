import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/band_selector_screen.dart';
import '../../features/auth/screens/sign_up_screen.dart';
import '../../features/auth/screens/path_selection_screen.dart';
import '../../features/bands/screens/create_band_screen.dart';
import '../../features/bands/screens/join_band_screen.dart';
import '../../features/bookings/data/models/booking_detail.dart';
import '../../features/bookings/screens/booking_contacts_screen.dart';
import '../../features/bookings/screens/booking_contract_screen.dart';
import '../../features/bookings/screens/booking_detail_screen.dart';
import '../../features/bookings/screens/booking_form_screen.dart';
import '../../features/bookings/screens/booking_history_screen.dart';
import '../../features/bookings/screens/booking_payments_screen.dart';
import '../../features/bookings/screens/booking_payout_screen.dart';
import '../../features/bookings/screens/bookings_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/events/screens/event_detail_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/events/screens/event_edit_screen.dart';
import '../../features/events/data/models/event_detail.dart';
import '../../features/rehearsals/screens/rehearsal_detail_by_key_screen.dart';
import '../../features/rehearsals/screens/rehearsal_detail_screen.dart';
import '../../features/rehearsals/screens/rehearsals_screen.dart';
import '../../features/library/screens/chart_detail_screen.dart';
import '../../features/library/screens/create_chart_screen.dart';
import '../../features/library/screens/library_screen.dart';
import '../../features/media/screens/media_screen.dart';
import '../../features/finances/screens/finances_screen.dart';
import '../../features/more/screens/more_screen.dart';
import '../../features/band_settings/screens/band_settings_screen.dart';
import '../../features/setlist/screens/live_session_screen.dart';
import '../../shared/providers/selected_band_provider.dart';
import '../../shared/widgets/app_scaffold.dart';

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

class _DismissKeyboardObserver extends NavigatorObserver {
  void _dismiss() => primaryFocus?.unfocus();

  @override
  void didPush(Route route, Route? previousRoute) => _dismiss();
  @override
  void didPop(Route route, Route? previousRoute) => _dismiss();
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => _dismiss();
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  debugPrint('Initializing GoRouter');
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    observers: [_DismissKeyboardObserver()],
    redirect: (context, state) {
      final authAsync = ref.read(authProvider);
      final bandAsync = ref.read(selectedBandProvider);

      debugPrint(
        '[Router] redirect fired | location=${state.matchedLocation} '
        'authLoading=${authAsync.isLoading} bandLoading=${bandAsync.isLoading} '
        'authState=${authAsync.value?.runtimeType} bandId=${bandAsync.value}',
      );

      // While auth or band selection is resolving, stay put (GoRouter will
      // re-evaluate when refreshListenable fires after the async completes).
      if (authAsync.isLoading || bandAsync.isLoading) {
        debugPrint('[Router] still loading — staying put');
        return null;
      }

      final authState = authAsync.value;

      final isLoginRoute = state.matchedLocation == '/login';
      final isSignupRoute = state.matchedLocation == '/signup';
      final isBandsRoute = state.matchedLocation == '/bands';
      final isBandsCreateRoute = state.matchedLocation == '/bands/create';
      final isBandsJoinRoute = state.matchedLocation == '/bands/join';

      // Not authenticated → force to login (signup is also allowed).
      if (authState == null || authState is AuthUnauthenticated) {
        final dest = (isLoginRoute || isSignupRoute) ? null : '/login';
        debugPrint('[Router] unauthenticated → $dest');
        return dest;
      }

      // Auth is in a transient loading-within-authenticated state.
      if (authState is AuthLoading) {
        debugPrint('[Router] AuthLoading — staying put');
        return null;
      }

      // Authenticated — check band selection.
      if (authState is AuthAuthenticated) {
        final bands = authState.bands;
        final bandId = bandAsync.value;

        debugPrint(
          '[Router] AuthAuthenticated | bands=${bands.map((b) => '${b.id}:${b.name}').toList()} '
          'storedBandId=$bandId',
        );

        // Validate that the stored band ID belongs to this user's bands.
        // It may be stale from a previous account's session.
        final bandIsValid =
            bandId != null && bands.any((b) => b.id == bandId);

        debugPrint('[Router] bandIsValid=$bandIsValid');

        if (!bandIsValid) {
          // Clear any stale stored band so it doesn't interfere later.
          if (bandId != null) {
            debugPrint('[Router] clearing stale bandId=$bandId');
            ref.read(selectedBandProvider.notifier).clear();
          }

          if (bands.isEmpty) {
            final dest = isBandsRoute ? null : '/bands';
            debugPrint('[Router] no bands → $dest');
            return dest;
          }

          if (bands.length == 1) {
            debugPrint('[Router] single band — auto-selecting ${bands.first.id}');
            ref.read(selectedBandProvider.notifier).selectBand(bands.first.id);
            return null;
          }

          final dest = isBandsRoute ? null : '/bands';
          debugPrint('[Router] multiple bands, none selected → $dest');
          return dest;
        }

        // Band is selected and valid.
        // Clear login screen if still showing it.
        if (isLoginRoute) {
          debugPrint('[Router] authenticated + valid band, on /login → /dashboard');
          return '/dashboard';
        }

        // Don't show bands/onboarding screens once band is selected.
        if (isBandsRoute || isBandsCreateRoute || isBandsJoinRoute) {
          debugPrint('[Router] valid band selected, on bands route → /dashboard');
          return '/dashboard';
        }

        debugPrint('[Router] all good — no redirect');
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) {
          final email = state.uri.queryParameters['email'];
          return SignUpScreen(prefillEmail: email);
        },
      ),
      GoRoute(
        path: '/bands/create',
        builder: (context, state) => const CreateBandScreen(),
      ),
      GoRoute(
        path: '/bands/join',
        builder: (context, state) => const JoinBandScreen(),
      ),
      GoRoute(
        path: '/bands',
        builder: (context, state) {
          // PathSelectionScreen for new users with no bands.
          // BandSelectorScreen for existing users with multiple bands.
          return Consumer(
            builder: (context, ref, _) {
              final authState = ref.watch(authProvider).value;
              if (authState is AuthAuthenticated && authState.bands.isNotEmpty) {
                return const BandSelectorScreen();
              }
              return const PathSelectionScreen();
            },
          );
        },
      ),
      ShellRoute(
        builder: (context, state, child) => AppScaffold(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/search',
            builder: (_, __) => const SearchScreen(),
          ),
          GoRoute(
            path: '/bookings',
            builder: (_, __) => const BookingsScreen(),
          ),
          GoRoute(
            path: '/library',
            builder: (_, __) => const LibraryScreen(),
          ),
          GoRoute(
            path: '/more',
            builder: (_, __) => const MoreScreen(),
          ),
          GoRoute(
            path: '/band-settings',
            builder: (_, __) => const BandSettingsScreen(),
          ),
          GoRoute(
            path: '/finances',
            builder: (_, __) => const FinancesScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/events/:key',
        builder: (_, state) =>
            EventDetailScreen(eventKey: state.pathParameters['key']!),
      ),
      GoRoute(
        path: '/events/:key/edit',
        builder: (_, state) => EventEditScreen(
          event: state.extra as EventDetail,
        ),
      ),
      GoRoute(
        path: '/events/:key/setlist/live',
        builder: (_, state) => LiveSessionScreen(
          eventKey: state.pathParameters['key']!,
        ),
      ),
      // Literal-segment routes before parameterised ones to avoid ambiguity
      GoRoute(
        path: '/bookings/:bandId/new',
        builder: (_, state) => BookingFormScreen(
          bandId: int.parse(state.pathParameters['bandId']!),
        ),
      ),
      GoRoute(
        path: '/bookings/:bandId/:id',
        builder: (_, state) => BookingDetailScreen(
          bandId: int.parse(state.pathParameters['bandId']!),
          bookingId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/bookings/:bandId/:bookingId/edit',
        builder: (_, state) => BookingFormScreen(
          bandId: int.parse(state.pathParameters['bandId']!),
          existing: state.extra as BookingDetail?,
        ),
      ),
      GoRoute(
        path: '/bookings/:bandId/:bookingId/contacts',
        builder: (_, state) => BookingContactsScreen(
          bandId: int.parse(state.pathParameters['bandId']!),
          bookingId: int.parse(state.pathParameters['bookingId']!),
        ),
      ),
      GoRoute(
        path: '/bookings/:bandId/:bookingId/payments',
        builder: (_, state) => BookingPaymentsScreen(
          bandId: int.parse(state.pathParameters['bandId']!),
          bookingId: int.parse(state.pathParameters['bookingId']!),
        ),
      ),
      GoRoute(
        path: '/bookings/:bandId/:bookingId/contract',
        builder: (_, state) => BookingContractScreen(
          bandId: int.parse(state.pathParameters['bandId']!),
          bookingId: int.parse(state.pathParameters['bookingId']!),
        ),
      ),
      GoRoute(
        path: '/bookings/:bandId/:bookingId/history',
        builder: (_, state) => BookingHistoryScreen(
          bandId: int.parse(state.pathParameters['bandId']!),
          bookingId: int.parse(state.pathParameters['bookingId']!),
        ),
      ),
      GoRoute(
        path: '/bookings/:bandId/:bookingId/payout',
        builder: (_, state) => BookingPayoutScreen(
          bandId: int.parse(state.pathParameters['bandId']!),
          bookingId: int.parse(state.pathParameters['bookingId']!),
        ),
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
      // Media — no bottom nav, pushed from More screen
      GoRoute(
        path: '/media',
        builder: (_, __) => const MediaScreen(),
      ),
      // Library — literal segment 'new' must precede the :chartId parameter
      // to prevent GoRouter from treating "new" as a chart ID.
      GoRoute(
        path: '/library/new',
        builder: (_, state) => CreateChartScreen(
          bandId: state.extra as int,
        ),
      ),
      GoRoute(
        path: '/library/:chartId',
        builder: (_, state) => ChartDetailScreen(
          bandId: state.extra as int,
          chartId: int.parse(state.pathParameters['chartId']!),
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
