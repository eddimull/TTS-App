import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/bands/data/invite_key.dart';
import '../config/router.dart';

/// Pure mapper: turn an incoming deep-link [uri] into the in-app route to
/// navigate to, or null if the app doesn't handle it. Kept free of platform
/// channels so it is unit-testable.
String? inviteRouteForUri(Uri uri) {
  final key = extractInviteKey(uri.toString());
  // extractInviteKey returns the whole string for non-invite inputs, so re-check
  // that this URI actually points at the invite path before routing.
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final idx = segments.indexOf('invite');
  final isInvitePath = idx != -1 && idx + 1 < segments.length;
  if (!isInvitePath || key == null) return null;
  return '/invite/$key';
}

/// Listens for app-launch and runtime deep links and forwards recognized ones
/// to [_onRoute] (wired to GoRouter.go).
class DeepLinkService {
  DeepLinkService(this._appLinks, this._onRoute);

  final AppLinks _appLinks;
  final void Function(String route) _onRoute;
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  /// Subscribe to incoming deep links while the app is running. A cold-start
  /// link (the one the app was launched with, if any) arrives via this
  /// stream's initial replay — app_links' `uriLinkStream` replays the initial
  /// link to the first listener on `onListen`, so there is no need to also
  /// call `getInitialLink()` (doing so would deliver the same cold-start link
  /// twice).
  ///
  /// Safe to call more than once; subsequent calls are no-ops so we never
  /// double-subscribe.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) => debugPrint('[DeepLink] stream error: $e'),
    );
  }

  void _handle(Uri uri) {
    final route = inviteRouteForUri(uri);
    if (route != null) _onRoute(route);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

/// App-wide deep-link service, wired to push recognized links into the router.
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final router = ref.watch(routerProvider);
  final service = DeepLinkService(AppLinks(), (route) => router.go(route));
  ref.onDispose(service.dispose);
  return service;
});
