import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderOrFamily` (the parameter type of `ref.invalidate`) is not
// re-exported from the main `flutter_riverpod` barrel in riverpod 3.3.1 —
// only from `misc.dart`. Needed for the invalidator seam's public signature.
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../core/network/pusher_connection.dart';
import '../../features/bookings/providers/bookings_provider.dart';
import '../../features/bookings/providers/bookings_window_provider.dart';
import '../../features/dashboard/providers/dashboard_provider.dart';
import '../../features/events/providers/events_provider.dart';
import '../../features/rehearsals/providers/rehearsals_provider.dart';
import 'selected_band_provider.dart';

/// Wire event name — must match BandDataChanged::broadcastAs() on the backend.
const String bandDataChangedEvent = 'band.data-changed';

typedef BandChannelBinder = Future<Future<void> Function()?> Function(
    String channelName, PusherJsonHandler onEvent);

/// Production binder: subscribe through the shared PusherConnection.
/// Overridden in tests to capture the handler.
final bandChannelBinderProvider = Provider<BandChannelBinder>((ref) {
  return (channel, onEvent) =>
      ref.read(pusherConnectionProvider).subscribe(channel, onEvent);
});

/// Debounce window for coalescing signal bursts (e.g. a roster sync touching
/// twenty events) into one refetch per provider. Overridden to zero in tests.
final bandRealtimeDebounceProvider =
    Provider<Duration>((_) => const Duration(milliseconds: 300));

/// Indirection over ref.invalidate so tests can observe which providers a
/// signal invalidates without faking HTTP for every feature repository.
final providerInvalidatorProvider =
    Provider<void Function(ProviderOrFamily)>((ref) => ref.invalidate);

/// Wire model name (backend: Str::snake(class_basename)) → providers to
/// invalidate. Invalidating a family invalidates every member — precise
/// parent-keyed invalidation is deliberately deferred (spec: v1).
List<ProviderOrFamily> invalidationTargetsFor(String model) {
  switch (model) {
    case 'bookings':
      return [
        bandBookingsProvider,
        bookingDetailProvider,
        bookingsWindowProvider,
        bookingDateStatusesProvider,
        bookingDateInfoProvider,
        bookingHistoryProvider,
        dashboardProvider,
      ];
    case 'events':
    case 'event_member':
    case 'roster':
      return [
        bandEventsProvider,
        eventDetailProvider,
        eventSubsProvider,
        dashboardProvider,
      ];
    case 'rehearsal':
      return [
        schedulesProvider,
        rehearsalDetailProvider,
        rehearsalDetailByKeyProvider,
        dashboardProvider,
      ];
    default:
      return const [];
  }
}

/// All models the registry knows — used for the blanket invalidation after an
/// app-resume reconnect, when signals may have been missed.
const List<String> _allRegisteredModels = [
  'bookings',
  'events',
  'rehearsal',
];

/// Subscribes to the selected band's realtime channel and turns thin
/// `band.data-changed` signals into Riverpod invalidations. State is the
/// currently subscribed band id (null = not subscribed).
///
/// Must be watch()ed by an always-mounted widget (AppScaffold) to stay alive.
class BandRealtimeNotifier extends Notifier<int?> {
  Future<void> Function()? _unsubscribe;
  Timer? _flushTimer;
  final Set<String> _pendingModels = {};
  AppLifecycleListener? _lifecycle;

  @override
  int? build() {
    ref.onDispose(_teardown);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.listen(selectedBandProvider, (previous, next) {
      _resubscribe(next.value);
    }, fireImmediately: true);
    return null;
  }

  Future<void> _resubscribe(int? bandId) async {
    await _unsubscribe?.call();
    _unsubscribe = null;
    state = null;
    if (bandId == null) return;

    final binder = ref.read(bandChannelBinderProvider);
    _unsubscribe = await binder('private-band.$bandId', _onSignal);
    if (_unsubscribe != null) state = bandId;
  }

  void _onSignal(String eventName, Map<String, dynamic> data) {
    if (eventName != bandDataChangedEvent) return;
    final model = data['model'];
    if (model is! String || invalidationTargetsFor(model).isEmpty) return;

    _pendingModels.add(model);
    _flushTimer ??= Timer(ref.read(bandRealtimeDebounceProvider), _flush);
  }

  void _flush() {
    _flushTimer = null;
    final invalidate = ref.read(providerInvalidatorProvider);
    final targets = <ProviderOrFamily>{
      for (final model in _pendingModels) ...invalidationTargetsFor(model),
    };
    _pendingModels.clear();
    targets.forEach(invalidate);
  }

  /// The socket dies while backgrounded; signals are pure invalidation, so
  /// instead of replaying we refetch everything band-scoped once and
  /// resubscribe (spec: Resilience).
  void _onResume() {
    final bandId = state;
    if (bandId == null) return;
    _pendingModels.addAll(_allRegisteredModels);
    _flushTimer ??= Timer(ref.read(bandRealtimeDebounceProvider), _flush);
    _resubscribe(bandId);
  }

  void _teardown() {
    _lifecycle?.dispose();
    _flushTimer?.cancel();
    _unsubscribe?.call();
  }
}

final bandRealtimeProvider = NotifierProvider<BandRealtimeNotifier, int?>(
  BandRealtimeNotifier.new,
);
