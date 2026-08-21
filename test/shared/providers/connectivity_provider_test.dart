import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/reachability.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';

/// Drives transport changes by hand. Reports Wi-Fi by default — the state a
/// device has on a joined-but-dead network, which is exactly the case the
/// plugin alone cannot distinguish from a working one.
class _FakeConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> current = [ConnectivityResult.wifi];

  void emit(List<ConnectivityResult> results) {
    current = results;
    _controller.add(results);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;
}

void main() {
  late _FakeConnectivity connectivity;
  late Reachability reachability;
  late ProviderContainer container;

  setUp(() {
    connectivity = _FakeConnectivity();
    reachability = Reachability();
    container = ProviderContainer(
      overrides: [
        connectivityPluginProvider.overrideWithValue(connectivity),
        reachabilityProvider.overrideWithValue(reachability),
      ],
    );
    addTearDown(container.dispose);
  });

  /// Collects everything `connectivityProvider` emits for the lifetime of the
  /// test, so assertions can look at the sequence rather than a snapshot.
  List<bool> listenToConnectivity() {
    final seen = <bool>[];
    container.listen<AsyncValue<bool>>(
      connectivityProvider,
      (_, next) {
        final value = next.value;
        if (value != null) seen.add(value);
      },
      fireImmediately: true,
    );
    return seen;
  }

  test('reports online on a working network', () async {
    final seen = listenToConnectivity();
    await container.read(transportProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(seen.last, isTrue);
  });

  test('reports offline on Wi-Fi that cannot reach the server', () async {
    final seen = listenToConnectivity();
    await container.read(transportProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(seen.last, isTrue, reason: 'the radio is up');

    // What a failed API request does.
    reachability.recordFailure();
    await Future<void>.delayed(Duration.zero);

    expect(seen.last, isFalse,
        reason: 'the banner must tell the truth about a dead upstream, even '
            'though connectivity_plus still reports Wi-Fi');
  });

  test('losing the radio reports offline without waiting for a request',
      () async {
    final seen = listenToConnectivity();
    await container.read(transportProvider.future);
    await Future<void>.delayed(Duration.zero);

    connectivity.emit([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);

    expect(seen.last, isFalse);
  });

  test('comes back online once the server answers again', () async {
    final seen = listenToConnectivity();
    await container.read(transportProvider.future);
    await Future<void>.delayed(Duration.zero);

    reachability.recordFailure();
    await Future<void>.delayed(Duration.zero);
    expect(seen.last, isFalse);

    reachability.recordSuccess();
    await Future<void>.delayed(Duration.zero);

    expect(seen.last, isTrue);
  });
}
