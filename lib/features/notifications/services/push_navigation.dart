import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/config/router.dart' show isShellLocation;

/// Opens the route a tapped push points at so Back always has somewhere to go.
///
/// Tab destinations are reached with `go`, same as the in-app feed. Anything
/// else (booking/event detail, …) is a top-level route drawn over the tab
/// shell and must be `push`ed, so Back returns to the tabs. On a cold start
/// nothing sits under it yet — a plain `go` left the screen stranded with no
/// tab bar and no Back — so land on the dashboard first and push only once
/// the router has actually built it: `push` stacks on the router's current
/// configuration, which a `go` updates only after its redirect pass.
Future<void> openPushRoute(
  GoRouter router,
  String route, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final from = _location(router);
  if (isShellLocation(route)) {
    _report(router, route: route, from: from, action: 'go');
    router.go(route);
    return;
  }
  if (!_hasShell(router)) {
    router.go('/dashboard');
    if (!await _waitForShell(router, timeout)) {
      // The shell never came up (e.g. redirected to the band picker) — fall
      // back to opening the destination on its own.
      _report(router, route: route, from: from, action: 'fallback_go');
      router.go(route);
      return;
    }
    _report(router, route: route, from: from, action: 'go_dashboard_then_push');
  } else {
    _report(router, route: route, from: from, action: 'push');
  }
  unawaited(router.push(route));
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

// DIAGNOSTIC (temporary, see push_service._tapBreadcrumb): record the
// decision taken for a tap and, once the router next settles, where it
// actually landed.
void _report(GoRouter router, {required String route, required String from, required String action}) {
  void send(String landed) {
    unawaited(Sentry.captureMessage(
      'push.route $action → $landed',
      level: SentryLevel.info,
      withScope: (scope) => scope.setContexts('push_route', {
        'route': route,
        'from': from,
        'action': action,
        'landed': landed,
      }),
    ));
  }

  final delegate = router.routerDelegate;
  void once() {
    delegate.removeListener(once);
    send(_location(router));
  }

  delegate.addListener(once);
}

bool _hasShell(GoRouter router) => router
    .routerDelegate.currentConfiguration.matches
    .any((m) => m is ShellRouteMatch);

Future<bool> _waitForShell(GoRouter router, Duration timeout) {
  if (_hasShell(router)) return Future.value(true);
  final reached = Completer<bool>();
  void check() {
    if (_hasShell(router) && !reached.isCompleted) reached.complete(true);
  }

  router.routerDelegate.addListener(check);
  return reached.future
      .timeout(timeout, onTimeout: () => false)
      .whenComplete(() => router.routerDelegate.removeListener(check));
}
