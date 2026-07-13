import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/band_selector_screen.dart';
import '../../features/auth/screens/sign_up_screen.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../features/auth/screens/path_selection_screen.dart';
import '../../features/bands/screens/create_band_screen.dart';
import '../../features/bands/screens/join_band_screen.dart';
import '../../features/bands/screens/invite_landing_screen.dart';
import '../../features/bands/providers/bands_provider.dart';
import '../../features/bands/providers/pending_invite_provider.dart';
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
import '../../features/auth/data/models/band_summary.dart';
import '../../features/library/screens/chart_detail_screen.dart';
import '../../features/library/screens/create_chart_screen.dart';
import '../../features/library/screens/library_tab_screen.dart';
import '../../features/media/screens/media_screen.dart';
import '../../features/songs/data/models/song.dart';
import '../../features/songs/screens/song_detail_screen.dart';
import '../../features/songs/screens/song_form_screen.dart';
import '../../features/songs/screens/song_list_screen.dart';
import '../../features/finances/screens/finances_screen.dart';
import '../../features/finances/payout_editor/screens/payout_configs_screen.dart';
import '../../features/finances/payout_editor/screens/payout_flow_editor_screen.dart';
import '../../features/more/screens/operations_screen.dart';
import '../../features/more/screens/settings_screen.dart';
import '../../features/band_settings/screens/band_settings_screen.dart';
import '../../features/personnel/screens/personnel_screen.dart';
import '../../features/account/screens/account_screen.dart';
import '../../features/calendar_feed/screens/calendar_feed_screen.dart';
import '../../features/chat/screens/conversation_thread_screen.dart';
import '../../features/chat/screens/messages_screen.dart';
import '../../features/chat/screens/new_message_screen.dart';
import '../../features/stats/screens/user_stats_screen.dart';
import '../../features/rehearsal_planner/screens/rehearsal_planner_screen.dart';
import '../../features/setlist/screens/live_session_screen.dart';
import '../../features/setlist_editor/screens/setlist_editor_screen.dart';
import '../../shared/providers/selected_band_provider.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../storage/route_storage.dart';

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

/// The shell route prefixes that are safe to persist as a last-route.
/// Pre-auth and deep-link-only paths are excluded.
const _kShellPrefixes = [
  '/dashboard',
  '/search',
  '/bookings',
  '/library',
  '/messages',
  '/operations',
  '/settings',
  '/band-settings',
  '/finances',
  '/personnel',
];

/// Initial location used when constructing the GoRouter. Defaults to `/welcome`.
/// `main.dart` overrides this with the user's last shell route (if recent)
/// after pre-resolving [routeStorageProvider], so cold-start restore happens
/// once at construction — never via the redirect callback.
final initialLocationProvider = Provider<String>((_) => '/welcome');

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  debugPrint('Initializing GoRouter');

  late final GoRouter router;
  router = GoRouter(
    initialLocation: ref.read(initialLocationProvider),
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

      final isWelcomeRoute = state.matchedLocation == '/welcome';
      final isLoginRoute = state.matchedLocation == '/login';
      final isSignupRoute = state.matchedLocation == '/signup';
      final isBandsRoute = state.matchedLocation == '/bands';
      final isBandsCreateRoute = state.matchedLocation == '/bands/create';
      final isBandsJoinRoute = state.matchedLocation == '/bands/join';
      // Account management must stay reachable for ANY authenticated user,
      // including one with zero bands — Apple App Review requires the account
      // deletion path to be accessible to a brand-new (band-less) account.
      final isAccountRoute = state.matchedLocation == '/account';
      final isInviteRoute = state.matchedLocation.startsWith('/invite/');

      // Not authenticated → land on the welcome/showcase screen. Login and
      // signup are reachable from there. Sending logged-out users to /welcome
      // (rather than straight to a login form) is what keeps the app's
      // non-account features visible without registration — App Review 5.1.1(v).
      if (authState == null || authState is AuthUnauthenticated) {
        final dest = (isWelcomeRoute ||
                isLoginRoute ||
                isSignupRoute ||
                isInviteRoute)
            ? null
            : '/welcome';
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
        // Account management is always allowed once authenticated, regardless
        // of band-selection state, so a band-less user can still reach the
        // account-deletion flow (Apple App Review requirement).
        if (isAccountRoute) {
          return null;
        }

        // An invite deep link must reach its landing screen even before a
        // band is selected — joining is what gives a zero-band user their
        // band. The landing screen navigates onward after the join.
        if (isInviteRoute) {
          return null;
        }

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
            final dest = (isBandsRoute || isBandsCreateRoute || isBandsJoinRoute)
                ? null
                : '/bands';
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
        // Clear the welcome/login screens if still showing one.
        if (isWelcomeRoute || isLoginRoute) {
          debugPrint('[Router] authenticated + valid band, on welcome/login → /dashboard');
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
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
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
      GoRoute(
        path: '/invite/:key',
        builder: (_, state) => InviteLandingScreen(
          inviteKey: state.pathParameters['key']!,
        ),
      ),
      // Legacy location from pre-1.13 saved routes and muscle memory.
      GoRoute(
        path: '/more',
        redirect: (_, __) => '/settings',
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
            builder: (_, __) => const LibraryTabScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/operations',
            builder: (_, __) => const OperationsScreen(),
          ),
          GoRoute(
            path: '/messages',
            builder: (_, __) => const MessagesScreen(),
          ),
          GoRoute(
            path: '/band-settings',
            builder: (_, __) => const BandSettingsScreen(),
          ),
          GoRoute(
            path: '/personnel',
            builder: (_, __) => const PersonnelScreen(),
          ),
          GoRoute(
            path: '/finances',
            builder: (_, __) => const FinancesScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/events/:key',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return EventDetailScreen(
            eventKey: state.pathParameters['key']!,
            parentBookingName: extra?['parentBookingName'] as String?,
            parentBookingId: extra?['parentBookingId'] as int?,
            parentBandId: extra?['parentBandId'] as int?,
          );
        },
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
      GoRoute(
        path: '/events/:key/setlist',
        builder: (_, state) => SetlistEditorScreen(
          eventKey: state.pathParameters['key']!,
        ),
      ),
      GoRoute(
        path: '/finances/payout-flow',
        builder: (_, __) => const PayoutConfigsScreen(),
      ),
      GoRoute(
        path: '/finances/payout-flow/:bandId/:configId',
        builder: (_, state) => PayoutFlowEditorScreen(
          bandId: int.parse(state.pathParameters['bandId']!),
          configId: int.parse(state.pathParameters['configId']!),
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
        path: '/bookings/:bandId/:bookingId/payout',
        builder: (_, state) => BookingPayoutScreen(
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
        path: '/rehearsals/:id/planner',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return RehearsalPlannerScreen(
            rehearsalId: int.parse(state.pathParameters['id']!),
            rehearsalLabel: extra?['rehearsalLabel'] as String?,
            existingNotes: extra?['existingNotes'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/rehearsals/:id',
        builder: (_, state) => RehearsalDetailScreen(
          rehearsalId: int.tryParse(state.pathParameters['id']!),
        ),
      ),
      // Account — no bottom nav, pushed from the dashboard avatar
      GoRoute(
        path: '/account',
        builder: (_, __) => const AccountScreen(),
      ),
      // Media — no bottom nav, pushed from Operations screen
      GoRoute(
        path: '/media',
        builder: (_, __) => const MediaScreen(),
      ),
      // Calendar subscription — no bottom nav, pushed from Settings screen
      GoRoute(
        path: '/calendar-feed',
        builder: (_, __) => const CalendarFeedScreen(),
      ),
      // Personal stats — no bottom nav, pushed from Settings screen
      GoRoute(
        path: '/stats',
        builder: (_, __) => const UserStatsScreen(),
      ),
      // Chat threads & new-DM picker — pushed over the Messages tab
      GoRoute(
        path: '/messages/new',
        builder: (_, __) => const NewMessageScreen(),
      ),
      GoRoute(
        path: '/conversations/:id',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ConversationThreadScreen(
            conversationId: int.parse(state.pathParameters['id']!),
            title: extra?['title'] as String?,
          );
        },
      ),
      // Library — literal segment 'new' must precede the :chartId parameter
      // to prevent GoRouter from treating "new" as a chart ID.
      GoRoute(
        path: '/library/new',
        builder: (_, state) => CreateChartScreen(
          band: state.extra as BandSummary,
        ),
      ),
      GoRoute(
        path: '/library/:chartId',
        builder: (_, state) => ChartDetailScreen(
          bandId: state.extra as int,
          chartId: int.parse(state.pathParameters['chartId']!),
        ),
      ),
      // Songs — standalone list pushed from the Operations screen (no bottom
      // nav, like /media). Literal segment 'new' must precede the :songId
      // parameter to prevent GoRouter from treating "new" as a song ID.
      GoRoute(
        path: '/songs',
        builder: (_, __) => const SongListScreen(standalone: true),
      ),
      GoRoute(
        path: '/songs/new',
        builder: (_, __) => const SongFormScreen(),
      ),
      GoRoute(
        path: '/songs/:songId/edit',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is Song) {
            return SongFormScreen(existing: extra);
          }
          // Deep link / restored navigation has no Song payload — fall back
          // to the detail screen, which loads from state and offers Edit.
          return SongDetailScreen(
            songId: int.parse(state.pathParameters['songId']!),
          );
        },
      ),
      GoRoute(
        path: '/songs/:songId',
        builder: (_, state) => SongDetailScreen(
          songId: int.parse(state.pathParameters['songId']!),
        ),
      ),
    ],
    errorBuilder: (context, state) => CupertinoPageScaffold(
      child: Center(
        child: Text('Page not found: ${state.error}'),
      ),
    ),
  );

  // Saving last-route via routerDelegate (not redirect) so writes can't be
  // echoed back as redirects. Restore happens once at construction via
  // initialLocationProvider — the redirect never reads RouteStorage.
  void onRouteChanged() {
    final path = router.routerDelegate.currentConfiguration.uri.path;
    // Excluded even though it matches the '/messages' prefix: cold-start
    // restore would otherwise boot straight into the New Message composer
    // with no escape (see _kRestorableShellPrefixes in main.dart).
    if (path == '/messages/new') return;
    if (!_kShellPrefixes.any((p) => path.startsWith(p))) return;
    ref.read(routeStorageProvider).value?.writeLastRoute(path);
  }

  router.routerDelegate.addListener(onRouteChanged);
  ref.onDispose(() => router.routerDelegate.removeListener(onRouteChanged));

  // When a user authenticates with a pending invite (captured while logged
  // out), join that band. Done via a listener — never inside redirect — so a
  // provider write can't be echoed back as a navigation.
  void consumePendingInvite() {
    final authState = ref.read(authProvider).value;
    if (authState is! AuthAuthenticated) return;
    final key = ref.read(pendingInviteKeyProvider.notifier).consume();
    if (key == null) return;
    // Fire-and-forget: joinBand refreshes auth bands; the router guard then
    // routes the freshly-joined user to their dashboard.
    ref.read(bandsProvider.notifier).joinBand(key).then((_) {
      router.go('/dashboard');
    }).catchError((_) {
      // Invalid/expired key after login — drop it; user lands wherever the
      // normal guard sends them (bands/dashboard). No hard failure.
    });
  }

  // Not captured/closed — a Provider's ref.listen is auto-disposed with the
  // provider, same as the _RouterRefreshNotifier listens above.
  ref.listen(authProvider, (_, __) => consumePendingInvite());

  return router;
});
