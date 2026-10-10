import 'dart:async';

import 'package:go_router/go_router.dart';

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
  if (isShellLocation(route)) {
    router.go(route);
    return;
  }
  if (!_hasShell(router)) {
    router.go('/dashboard');
    if (!await _waitForShell(router, timeout)) {
      // The shell never came up (e.g. redirected to the band picker) — fall
      // back to opening the destination on its own.
      router.go(route);
      return;
    }
  }
  unawaited(router.push(route));
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
