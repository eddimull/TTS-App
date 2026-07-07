import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/pusher_connection.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
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
}
