import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the current connectivity state. `true` = online, `false` = offline.
///
/// Seeded with an initial `checkConnectivity()` so `.value` is correct from
/// startup — `onConnectivityChanged` alone only emits on CHANGE, which left
/// the state `null` (treated as online) until the first transition.
///
/// Known limitation: `connectivity_plus` reports link presence, not
/// reachability — a captive portal reads as online. The SWR layer's
/// keep-data-on-error policy covers that case.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  yield isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnline);
});
