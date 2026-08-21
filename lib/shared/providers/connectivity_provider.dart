import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/reachability.dart';

/// Seam over the plugin so tests can drive transport changes.
final connectivityPluginProvider =
    Provider<Connectivity>((_) => Connectivity());

bool _hasTransport(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);

/// Whether the device is attached to *a* network (Wi-Fi, cellular, ethernet).
///
/// This is a statement about the radio, not about the internet: joined Wi-Fi
/// with a dead upstream, or a captive portal that hasn't been clicked through,
/// reports `true` here. Seeded with `checkConnectivity()` because
/// `onConnectivityChanged` only emits on *changes* — without the seed a device
/// that was already offline at launch would look connected until it moved.
final transportProvider = StreamProvider<bool>((ref) async* {
  final connectivity = ref.watch(connectivityPluginProvider);
  yield _hasTransport(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(_hasTransport);
});

/// Whether the app can actually reach its API. `true` = online.
///
/// Combines the device transport with what real API traffic has observed (see
/// [Reachability]), so the offline banner is telling the truth on a network
/// that is connected but going nowhere — the case where the app used to sit on
/// an endless spinner with no explanation.
final connectivityProvider = StreamProvider<bool>((ref) {
  final reachability = ref.watch(reachabilityProvider);
  final controller = StreamController<bool>();

  var hasTransport = true;

  void emit() {
    if (controller.isClosed) return;
    controller.add(hasTransport && reachability.isOnline);
  }

  reachability.addListener(emit);

  ref.listen<AsyncValue<bool>>(transportProvider, (previous, next) {
    final value = next.value;
    if (value == null) return;
    final changed = value != hasTransport;
    hasTransport = value;
    reachability.recordTransportChange(hasTransport: value);

    // Joining a network says nothing about whether it works, so the banner
    // can't just clear itself. Ask the server directly instead of leaving the
    // user staring at a stale "no connection" until they happen to tap
    // something.
    if (changed && value && reachability.isOffline) {
      unawaited(ref.read(apiClientProvider).probeReachability());
    }

    emit();
  }, fireImmediately: true);

  ref.onDispose(() {
    reachability.removeListener(emit);
    controller.close();
  });

  return controller.stream;
});
