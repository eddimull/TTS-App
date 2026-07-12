import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderOrFamily` (the parameter type of `ref.invalidate`) is not
// re-exported from the main `flutter_riverpod` barrel in riverpod 3.3.1 —
// only from `misc.dart`. Needed for the invalidator seam's public signature.
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../core/network/pusher_connection.dart';
import '../../features/bookings/data/bookings_cache_storage.dart';
import '../../features/bookings/providers/booking_payout_provider.dart';
import '../../features/bookings/providers/bookings_provider.dart';
import '../../features/bookings/providers/bookings_window_provider.dart';
import '../../features/chat/providers/conversations_provider.dart';
import '../../features/chat/widgets/comments_section.dart';
import '../../features/dashboard/providers/dashboard_provider.dart';
import '../../features/library/providers/library_provider.dart';
import '../../features/media/providers/media_provider.dart';
import '../../features/search/providers/music_provider.dart';
import '../../features/events/providers/events_provider.dart';
import '../../features/personnel/providers/rosters_provider.dart';
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
      return [
        bandEventsProvider,
        eventDetailProvider,
        eventSubsProvider,
        dashboardProvider,
      ];
    case 'roster':
      return [
        bandEventsProvider,
        eventDetailProvider,
        eventSubsProvider,
        dashboardProvider,
        rostersProvider,
        rosterDetailProvider,
      ];
    case 'rehearsal':
      return [
        schedulesProvider,
        rehearsalDetailProvider,
        rehearsalDetailByKeyProvider,
        dashboardProvider,
      ];
    case 'payments':
    case 'payout':
    case 'payout_adjustment':
    case 'band_payout_config':
      return [
        bookingDetailProvider,
        bookingPayoutProvider,
      ];
    case 'media_file':
      return [mediaListProvider];
    case 'song':
      return [songsProvider, libraryProvider];
    case 'charts':
    case 'chart_uploads':
      return [chartsProvider, libraryProvider, chartDetailProvider];
    case 'message':
      return [chatConversationsProvider, topicThreadProvider];
    default:
      return const [];
  }
}

/// Wire model name → disk caches to drop *before* the model's providers are
/// invalidated. A plain invalidation re-runs a provider's `build()`, but a
/// provider that warm-paints from a disk cache (currently only
/// [bookingsWindowProvider]) would repaint the now-stale pre-signal snapshot
/// and only correct it on its background revalidate — a visible flash of old
/// data. Clearing the cache first forces the cold path (fresh fetch), matching
/// what [CacheInvalidator] does on local mutations.
///
/// Each clearer receives the notifier's [Ref] so it can resolve the cache
/// provider. Keep in sync with [invalidationTargetsFor]: a model that gains a
/// disk-backed target gains a clearer here.
List<void Function(Ref)> cacheClearersFor(String model) {
  switch (model) {
    case 'bookings':
      return [(ref) => ref.read(bookingsCacheStorageProvider).clear()];
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
  'roster',
  'payments',
  'payout',
  'payout_adjustment',
  'band_payout_config',
  'media_file',
  'song',
  'charts',
  'chart_uploads',
  'message',
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
  int _generation = 0;
  bool _disposed = false;

  @override
  int? build() {
    ref.onDispose(_teardown);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.listen(selectedBandProvider, (previous, next) {
      _resubscribe(next.value);
    }, fireImmediately: true);
    return null;
  }

  /// Serializes concurrent calls (band-change listener + resume) with a
  /// generation counter: only the newest in-flight call is allowed to write
  /// `_unsubscribe`/`state`. A stale call that resolves late immediately
  /// tears down whatever it just subscribed instead of leaking or clobbering
  /// the winner. Also bails out (without writing `state`) if the provider
  /// has been disposed in the meantime, since a post-dispose `state =`
  /// write throws.
  Future<void> _resubscribe(int? bandId) async {
    final gen = ++_generation;

    final old = _unsubscribe;
    _unsubscribe = null;
    try {
      await old?.call();
    } catch (e) {
      debugPrint('bandRealtime: unsubscribe failed: $e');
    }
    if (_disposed || gen != _generation) return;

    state = null;
    if (bandId == null) return;

    final binder = ref.read(bandChannelBinderProvider);
    final Future<void> Function()? unsubscribe;
    try {
      unsubscribe = await binder('private-band.$bandId', _onSignal);
    } catch (e) {
      // Realtime is best-effort and _resubscribe is fire-and-forget (band
      // listener + resume): a failed subscribe must log, not surface as an
      // unhandled zone error. The next band switch or resume retries.
      debugPrint('bandRealtime: subscribe to band $bandId failed: $e');
      return;
    }
    if (_disposed || gen != _generation) {
      // A newer call has already taken over (or the provider was disposed)
      // while we were awaiting the binder — tear down our own subscription
      // immediately instead of storing it or touching state.
      try {
        await unsubscribe?.call();
      } catch (e) {
        debugPrint('bandRealtime: stale unsubscribe failed: $e');
      }
      return;
    }

    _unsubscribe = unsubscribe;
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
    // Drop any disk caches whose providers warm-paint stale data, before the
    // invalidation re-runs their build() — otherwise the cached provider
    // repaints pre-signal data and only corrects on background revalidate.
    // Clearing is a best-effort optimization: a failure here must never
    // suppress the invalidation, which is what actually refreshes the UI.
    for (final model in _pendingModels) {
      for (final clear in cacheClearersFor(model)) {
        try {
          clear(ref);
        } catch (e) {
          debugPrint('bandRealtime: cache clear for "$model" failed: $e');
        }
      }
    }
    _pendingModels.clear();
    targets.forEach(invalidate);
  }

  /// The socket dies while backgrounded; signals are pure invalidation, so
  /// instead of replaying we refetch everything band-scoped once and
  /// resubscribe (spec: Resilience).
  void _onResume() {
    if (_disposed) return;
    final bandId = state;
    if (bandId == null) return;
    _pendingModels.addAll(_allRegisteredModels);
    _flushTimer ??= Timer(ref.read(bandRealtimeDebounceProvider), _flush);
    _resubscribe(bandId);
  }

  void _teardown() {
    _disposed = true;
    _generation++;
    _lifecycle?.dispose();
    _flushTimer?.cancel();
    final unsubscribe = _unsubscribe;
    _unsubscribe = null;
    try {
      unsubscribe?.call().catchError((Object e) {
        debugPrint('bandRealtime: teardown unsubscribe failed: $e');
      });
    } catch (e) {
      debugPrint('bandRealtime: teardown unsubscribe failed: $e');
    }
  }
}

final bandRealtimeProvider = NotifierProvider<BandRealtimeNotifier, int?>(
  BandRealtimeNotifier.new,
);
