import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/pusher_connection.dart';
import 'package:tts_bandmate/features/bookings/providers/booking_payout_provider.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/features/personnel/providers/rosters_provider.dart';
import 'package:tts_bandmate/shared/providers/band_realtime_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class FakeSelectedBand extends SelectedBandNotifier {
  FakeSelectedBand(this.initial);
  final int? initial;

  @override
  Future<int?> build() async => initial;

  void set(int? id) => state = AsyncValue.data(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> subscribedChannels;
  late List<String> unsubscribedChannels;
  late PusherJsonHandler? capturedHandler;
  late List<ProviderOrFamily> invalidated;
  late FakeSelectedBand fakeBand;

  ProviderContainer makeContainer({int? bandId = 7}) {
    subscribedChannels = [];
    unsubscribedChannels = [];
    capturedHandler = null;
    invalidated = [];
    fakeBand = FakeSelectedBand(bandId);
    final container = ProviderContainer(overrides: [
      selectedBandProvider.overrideWith(() => fakeBand),
      bandRealtimeDebounceProvider.overrideWithValue(Duration.zero),
      providerInvalidatorProvider.overrideWithValue((p) => invalidated.add(p)),
      bandChannelBinderProvider.overrideWithValue((channel, onEvent) async {
        subscribedChannels.add(channel);
        capturedHandler = onEvent;
        return () async => unsubscribedChannels.add(channel);
      }),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// Activates the provider and lets the async subscribe settle.
  Future<void> activate(ProviderContainer c) async {
    c.read(bandRealtimeProvider);
    await c.read(selectedBandProvider.future);
    await Future<void>.delayed(Duration.zero);
  }

  test('subscribes to the selected band channel', () async {
    final c = makeContainer();
    await activate(c);

    expect(subscribedChannels, ['private-band.7']);
    expect(c.read(bandRealtimeProvider), 7);
  });

  test('does not subscribe when no band is selected', () async {
    final c = makeContainer(bandId: null);
    await activate(c);

    expect(subscribedChannels, isEmpty);
    expect(c.read(bandRealtimeProvider), isNull);
  });

  test('resubscribes when the band changes', () async {
    final c = makeContainer();
    await activate(c);

    fakeBand.set(9);
    await Future<void>.delayed(Duration.zero);

    expect(unsubscribedChannels, ['private-band.7']);
    expect(subscribedChannels, ['private-band.7', 'private-band.9']);
    expect(c.read(bandRealtimeProvider), 9);
  });

  test('a burst of signals for one model invalidates its targets once', () async {
    final c = makeContainer();
    await activate(c);

    for (var i = 0; i < 3; i++) {
      capturedHandler!('band.data-changed',
          {'model': 'bookings', 'id': i, 'action': 'updated'});
    }
    await Future<void>.delayed(Duration.zero);

    expect(invalidated, containsAll(<ProviderOrFamily>[
      bandBookingsProvider,
      bookingDetailProvider,
      dashboardProvider,
    ]));
    expect(invalidated.length, invalidated.toSet().length,
        reason: 'burst must be debounced into one invalidation per target');
  });

  test('unknown models and foreign event names are ignored', () async {
    final c = makeContainer();
    await activate(c);

    capturedHandler!('band.data-changed', {'model': 'mystery', 'id': 1, 'action': 'created'});
    capturedHandler!('some.other.event', {'model': 'bookings', 'id': 1, 'action': 'created'});
    await Future<void>.delayed(Duration.zero);

    expect(invalidated, isEmpty);
  });

  test('registry maps events, rehearsal, and event_member', () {
    expect(invalidationTargetsFor('events'), contains(bandEventsProvider));
    expect(invalidationTargetsFor('event_member'), contains(eventDetailProvider));
    expect(invalidationTargetsFor('rehearsal'), isNotEmpty);
    expect(invalidationTargetsFor('unknown'), isEmpty);
  });

  test('registry maps payments/payout signals to booking payout providers',
      () {
    expect(invalidationTargetsFor('payments'), contains(bookingPayoutProvider));
    expect(invalidationTargetsFor('payout_adjustment'), isNotEmpty);
  });

  test('roster signals invalidate personnel providers in addition to events',
      () {
    final targets = invalidationTargetsFor('roster');
    expect(targets, contains(bandEventsProvider));
    expect(targets, contains(rostersProvider));
    expect(targets, contains(rosterDetailProvider));
  });

  test('rapid band switch during in-flight subscribe does not leak', () async {
    // A binder whose future we control by hand, per call, so the race
    // window inside _resubscribe (the await between "null out the old
    // unsubscribe" and "store the new one") is genuinely exercised rather
    // than settled-before-the-next-action.
    final calls = <String>[];
    final completers = <String, Completer<Future<void> Function()?>>{};
    final unsubscribed = <String>[];

    fakeBand = FakeSelectedBand(7);
    final container = ProviderContainer(overrides: [
      selectedBandProvider.overrideWith(() => fakeBand),
      bandRealtimeDebounceProvider.overrideWithValue(Duration.zero),
      providerInvalidatorProvider.overrideWithValue((p) {}),
      bandChannelBinderProvider.overrideWithValue((channel, onEvent) {
        calls.add(channel);
        final completer = Completer<Future<void> Function()?>();
        completers[channel] = completer;
        return completer.future;
      }),
    ]);
    addTearDown(container.dispose);

    container.read(bandRealtimeProvider);
    await container.read(selectedBandProvider.future);
    // First _resubscribe (band 7) is now awaiting the binder future.
    expect(calls, ['private-band.7']);

    // Switch bands before call 1 (band 7) resolves — this fires a second,
    // concurrent _resubscribe(9) from the ref.listen callback.
    fakeBand.set(9);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['private-band.7', 'private-band.9']);

    // Resolve call 2 (band 9) FIRST, then call 1 (band 7) — the classic
    // "loser resolves last" interleaving that used to overwrite the
    // winner's state and leak the loser's subscription.
    completers['private-band.9']!
        .complete(() async => unsubscribed.add('private-band.9'));
    await Future<void>.delayed(Duration.zero);

    completers['private-band.7']!
        .complete(() async => unsubscribed.add('private-band.7'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // The stale band-7 subscription must have been torn down immediately
    // (no leak) instead of being stored or left dangling.
    expect(unsubscribed, contains('private-band.7'));
    // The winner (band 9, the newest generation) owns state.
    expect(container.read(bandRealtimeProvider), 9);
    // Both calls were genuinely made (order recorded), confirming the
    // interleaving happened rather than being short-circuited.
    expect(calls, ['private-band.7', 'private-band.9']);
  });

  test('dispose during in-flight subscribe does not throw', () async {
    final completers = <String, Completer<Future<void> Function()?>>{};
    final unsubscribed = <String>[];

    fakeBand = FakeSelectedBand(7);
    final container = ProviderContainer(overrides: [
      selectedBandProvider.overrideWith(() => fakeBand),
      bandRealtimeDebounceProvider.overrideWithValue(Duration.zero),
      providerInvalidatorProvider.overrideWithValue((p) {}),
      bandChannelBinderProvider.overrideWithValue((channel, onEvent) {
        final completer = Completer<Future<void> Function()?>();
        completers[channel] = completer;
        return completer.future;
      }),
    ]);

    container.read(bandRealtimeProvider);
    await container.read(selectedBandProvider.future);

    // Dispose the container while _resubscribe is still awaiting the
    // binder future — the in-flight continuation must not write `state`
    // after disposal (that throws in Riverpod).
    container.dispose();

    // Now let the stale subscribe resolve — this must not surface an
    // exception (a post-dispose `state =` write would throw synchronously
    // inside the continuation, which `flutter test` reports as a failure).
    completers['private-band.7']!
        .complete(() async => unsubscribed.add('private-band.7'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // The late subscription must still be torn down (no leak) even though
    // the provider is gone.
    expect(unsubscribed, contains('private-band.7'));
  });

  test('throwing binder is swallowed (fire-and-forget resubscribe), state stays null',
      () async {
    final band = FakeSelectedBand(7);
    final container = ProviderContainer(overrides: [
      selectedBandProvider.overrideWith(() => band),
      bandRealtimeDebounceProvider.overrideWithValue(Duration.zero),
      providerInvalidatorProvider.overrideWithValue((p) {}),
      bandChannelBinderProvider.overrideWithValue(
        (channel, onEvent) async => throw StateError('socket init failed'),
      ),
    ]);
    addTearDown(container.dispose);

    container.read(bandRealtimeProvider);
    await container.read(selectedBandProvider.future);
    // Let the failed subscribe settle: the error must be caught inside
    // _resubscribe (fire-and-forget call site), not become an unhandled
    // zone error that fails this test.
    await Future<void>.delayed(Duration.zero);

    expect(container.read(bandRealtimeProvider), isNull);
  });
}
