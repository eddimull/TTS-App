import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connectivity_provider.dart';
import '../providers/selected_band_provider.dart';
import 'api_cache_storage.dart';

/// User-facing copy for offline failures. Shared by `ErrorView` and the
/// setlist screen so the message stays consistent app-wide.
const String kOfflineMessage =
    "You're offline. Check your connection and try again.";

/// Thrown when a fetch is skipped (or would be pointless) because the device
/// is offline and no cached data exists to fall back on.
class OfflineException implements Exception {
  const OfflineException();

  @override
  String toString() => kOfflineMessage;
}

/// True for errors caused by missing connectivity rather than the server.
///
/// Web-safe: no `dart:io` import — a wrapped `SocketException` is detected
/// via `toString()` because the concrete type only exists on IO platforms.
bool isOfflineError(Object e) {
  if (e is OfflineException) return true;
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      default:
        return e.error?.toString().contains('SocketException') ?? false;
    }
  }
  return false;
}

/// Stale-while-revalidate support for `AsyncNotifier`s, generalizing the
/// pattern proven in `BookingsWindowNotifier`:
///
/// - `build()` paints instantly from the disk cache when possible and
///   revalidates in a deferred background fetch;
/// - revalidation NEVER discards on-screen data — failures with data present
///   are silent;
/// - when offline, network attempts are skipped entirely (no timeout wait).
///
/// Notifiers with windowed/merged state (dashboard, bookings window) hand-roll
/// the same flow instead; this mixin serves the simple fetch-and-render ones.
mixin SwrSupport<T> on AsyncNotifier<T> {
  /// Band-scoped cache key, or null when no band is selected (skip caching).
  String? _swrKey(String name) {
    final bandId = ref.read(selectedBandProvider).value;
    if (bandId == null) return null;
    return '$bandId:$name';
  }

  /// Latest known connectivity. `null` (stream not yet emitted) is treated
  /// as online so we never wrongly skip a fetch.
  bool get _isOffline => ref.read(connectivityProvider).value == false;

  /// SWR build flow. [decode] parses a cached payload; [fetch] returns the
  /// fresh parsed value plus the raw response JSON to cache. Both must decode
  /// through the SAME `fromJson` path so cached and live data are identical.
  Future<T> swrBuild({
    required String name,
    required T Function(Map<String, dynamic> payload) decode,
    required Future<({T value, Map<String, dynamic> raw})> Function() fetch,
  }) async {
    final key = _swrKey(name);
    final cached = key == null ? null : ref.read(apiCacheStorageProvider).read(key);
    if (cached != null) {
      try {
        final decoded = decode(cached.payload);
        // Defer the background refresh until after the framework commits
        // this build's returned value — otherwise revalidate's `state = …`
        // lands first and is immediately overwritten by build's own result.
        // ignore: unawaited_futures
        Future<void>(() => swrRevalidate(name: name, fetch: fetch));
        return decoded;
      } catch (_) {
        // Corrupt/undecodable cached payload (e.g. a stale shape from before
        // a schema change): drop the bad entry and fall through to the cold
        // path below instead of permanently erroring. Do NOT schedule a
        // revalidate for this failed entry — the cold-path fetch already
        // covers it.
        ref.read(apiCacheStorageProvider).remove(key!);
      }
    }

    // Cold path. Offline with nothing cached: fail fast with a friendly
    // error instead of waiting out the connect timeout.
    if (_isOffline) throw const OfflineException();
    final result = await fetch();
    if (key != null) ref.read(apiCacheStorageProvider).write(key, result.raw);
    return result.value;
  }

  /// Background revalidation, also used as the non-destructive `refresh()`.
  /// Keeps existing data on ANY failure; only surfaces an error when there is
  /// nothing on screen. Never emits `AsyncLoading` when data is present.
  Future<void> swrRevalidate({
    required String name,
    required Future<({T value, Map<String, dynamic> raw})> Function() fetch,
  }) async {
    // The deferred `Future<void>(...)` scheduling in `swrBuild` can fire
    // after this notifier has been disposed (e.g. the screen navigated away
    // before the microtask ran) — guard at entry, before touching `state`.
    if (!ref.mounted) return;

    // Capture the band (and its cache key) BEFORE the fetch: if the user
    // switches bands mid-flight, band A's payload must never be written
    // under band B's key nor clobber band B's on-screen state.
    final keyAtStart = _swrKey(name);

    if (_isOffline && state.hasValue) return; // keep data, skip the attempt
    if (!state.hasValue) state = const AsyncValue.loading();
    try {
      if (_isOffline) throw const OfflineException();
      final result = await fetch();
      if (!ref.mounted) return;
      // Abort entirely — no cache write, no state assignment — if the
      // selected band changed while the fetch was in flight.
      if (_swrKey(name) != keyAtStart) return;
      if (keyAtStart != null) {
        ref.read(apiCacheStorageProvider).write(keyAtStart, result.raw);
      }
      state = AsyncData(result.value);
    } catch (e, st) {
      if (!ref.mounted) return;
      if (state.hasValue) return; // never discard on-screen data
      state = AsyncError(e, st);
    }
  }
}
