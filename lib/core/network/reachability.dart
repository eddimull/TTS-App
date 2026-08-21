import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether the app can actually reach its API, and short-circuits
/// requests while it can't.
///
/// `connectivity_plus` answers a different question — "is this device attached
/// to a network?" — and answers `true` for the case that prompted this class:
/// Wi-Fi that is joined but has no working upstream (a dead router, a hotel
/// captive portal, a coffee shop that needs a click-through). On such a
/// network every request stalls until it times out, which is what made the app
/// look frozen behind an infinite spinner.
///
/// The only reliable evidence of reachability is a request that actually
/// completed, so that's what this tracks. It behaves like a circuit breaker:
///
/// - **closed** (online): everything goes to the wire.
/// - **open** (offline, within [retryAfter] of the last attempt): requests are
///   rejected immediately, so a screen renders its offline/cached state at
///   once instead of after a timeout.
/// - **half-open** (offline, [retryAfter] elapsed): the next request is let
///   through to test the water. Concurrent requests behind it still
///   short-circuit, so exactly one probe goes out per window.
///
/// Any completed round trip — including a 4xx/5xx, which proves the server
/// answered — closes the circuit again.
class Reachability extends ChangeNotifier {
  Reachability({
    this.retryAfter = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How long the circuit stays open before letting a single request through.
  final Duration retryAfter;

  final DateTime Function() _clock;

  bool _online = true;
  DateTime? _lastAttemptAt;

  /// Optimistic until proven otherwise: a fresh install on a good network must
  /// not pay a probe before its first screen loads.
  bool get isOnline => _online;

  bool get isOffline => !_online;

  /// True when a request should be rejected outright rather than attempted.
  bool shouldShortCircuit() {
    if (_online) return false;
    final lastAttempt = _lastAttemptAt;
    if (lastAttempt == null) return false; // half-open — let one through
    return _clock().difference(lastAttempt) < retryAfter;
  }

  /// Called just before a request goes to the wire. Closes the half-open
  /// window so siblings firing in the same instant don't all become probes.
  void recordAttempt() => _lastAttemptAt = _clock();

  /// A round trip completed (any status code) — the server is reachable.
  void recordSuccess() {
    _lastAttemptAt = null;
    if (_online) return;
    _online = true;
    notifyListeners();
  }

  /// A request failed without ever reaching the server.
  void recordFailure() {
    _lastAttemptAt = _clock();
    if (!_online) return;
    _online = false;
    notifyListeners();
  }

  /// The device's network transport changed.
  ///
  /// Losing the transport entirely is conclusive — go offline without waiting
  /// for a request to fail. Gaining one is not: the new network may be just as
  /// dead as the old one. It does clear the backoff window, so the very next
  /// request (or the reachability probe the connectivity provider fires) gets
  /// an immediate attempt instead of waiting out [retryAfter].
  void recordTransportChange({required bool hasTransport}) {
    if (!hasTransport) {
      recordFailure();
      return;
    }
    _lastAttemptAt = null;
  }

  @visibleForTesting
  void reset() {
    _online = true;
    _lastAttemptAt = null;
  }
}

/// App-wide reachability state.
///
/// Deliberately independent of `apiClientProvider`: that provider is rebuilt
/// whenever the selected band changes, and the circuit must survive those
/// rebuilds.
final reachabilityProvider = Provider<Reachability>((ref) {
  final reachability = Reachability();
  ref.onDispose(reachability.dispose);
  return reachability;
});
