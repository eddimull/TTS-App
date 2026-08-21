import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One cached API payload plus the moment it was stored.
class CachedEntry {
  const CachedEntry({required this.savedAt, required this.payload});

  final DateTime savedAt;
  final Map<String, dynamic> payload;
}

/// `SharedPreferences`-backed store of raw API JSON payloads for offline
/// viewing. Generalizes `BookingsCacheStorage`: raw JSON is stored (models
/// have no `toJson`) so cached data re-enters through the same
/// `Model.fromJson` path as a live response.
///
/// Callers pass band-scoped keys (`<bandId>:<logical-name>`); the storage
/// prefixes them with a versioned namespace so [clearAll] can drop every
/// cache entry without touching unrelated preferences.
class ApiCacheStorage {
  ApiCacheStorage(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefix = 'api_cache_v1:';

  /// Returns the cached entry, or null if absent or unparseable. A malformed
  /// blob is cleared so subsequent reads don't keep failing.
  CachedEntry? read(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return CachedEntry(
        savedAt: DateTime.fromMillisecondsSinceEpoch(
            (decoded['savedAt'] as num).toInt()),
        payload: decoded['payload'] as Map<String, dynamic>,
      );
    } catch (_) {
      _prefs.remove('$_prefix$key');
      return null;
    }
  }

  void write(String key, Map<String, dynamic> payload) {
    _prefs.setString(
      '$_prefix$key',
      jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'payload': payload,
      }),
    );
  }

  /// Drops one entry — used after a local mutation so the next rebuild takes
  /// the cold path instead of warm-painting pre-mutation data.
  void remove(String key) {
    _prefs.remove('$_prefix$key');
  }

  /// Drops every cached payload. Called on logout so a different user
  /// signing in on this device never sees the previous user's data.
  void clearAll() {
    for (final k
        in _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      _prefs.remove(k);
    }
  }
}

/// Resolved at startup in `main.dart` (mirrors `bookingsCacheStorageProvider`).
/// The override supplies a pre-resolved instance so synchronous `read()`
/// works inside provider `build()` methods.
final apiCacheStorageProvider = Provider<ApiCacheStorage>((ref) {
  throw UnimplementedError(
    'apiCacheStorageProvider must be overridden in main()',
  );
});
