import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serializable snapshot of the initial bookings window. Stores raw API JSON
/// maps (the summary models have no `toJson`) so cached data goes back through
/// the same `BookingSummary.fromJson` path as a live response.
class BookingsWindowCache {
  const BookingsWindowCache({
    required this.from,
    required this.to,
    required this.cachedAt,
    required this.rawBookings,
  });

  final DateTime from;
  final DateTime to;
  final DateTime cachedAt;
  final List<Map<String, dynamic>> rawBookings;

  Map<String, dynamic> toJson() => {
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
        'cachedAt': cachedAt.millisecondsSinceEpoch,
        'bookings': rawBookings,
      };

  factory BookingsWindowCache.fromJson(Map<String, dynamic> json) {
    return BookingsWindowCache(
      from: DateTime.fromMillisecondsSinceEpoch((json['from'] as num).toInt()),
      to: DateTime.fromMillisecondsSinceEpoch((json['to'] as num).toInt()),
      cachedAt:
          DateTime.fromMillisecondsSinceEpoch((json['cachedAt'] as num).toInt()),
      rawBookings: (json['bookings'] as List<dynamic>)
          .cast<Map<String, dynamic>>(),
    );
  }
}

/// `SharedPreferences`-backed store for the initial bookings window. Mirrors
/// `RouteStorage`. Only the initial 3-back/9-ahead window is persisted;
/// loadEarlier/loadLater slices are not.
class BookingsCacheStorage {
  BookingsCacheStorage(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'bookings_window_cache';

  /// Returns the cached window, or null if absent or unparseable. A malformed
  /// blob is cleared so subsequent reads don't keep failing.
  BookingsWindowCache? read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return BookingsWindowCache.fromJson(decoded);
    } catch (_) {
      _prefs.remove(_key);
      return null;
    }
  }

  void write(BookingsWindowCache cache) {
    _prefs.setString(_key, jsonEncode(cache.toJson()));
  }

  void clear() {
    _prefs.remove(_key);
  }
}

/// Resolved at startup in `main.dart` (mirrors `routeStorageProvider`). The
/// async default is overridden with a pre-resolved instance so synchronous
/// `read()` works inside the window provider's `build()`.
final bookingsCacheStorageProvider = Provider<BookingsCacheStorage>((ref) {
  throw UnimplementedError(
    'bookingsCacheStorageProvider must be overridden in main()',
  );
});
