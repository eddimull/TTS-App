import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A successful GET response kept on disk so the screen that asked for it can
/// still render when the server is unreachable.
class CachedApiResponse {
  const CachedApiResponse({
    required this.statusCode,
    required this.body,
    required this.cachedAt,
  });

  final int statusCode;

  /// The decoded JSON body — a `Map` or a `List`, exactly what Dio would have
  /// handed the repository, so cached data goes back through the same
  /// `fromJson` path as a live response.
  final Object? body;

  final DateTime cachedAt;
}

/// `SharedPreferences`-backed store of the last successful response for each
/// GET endpoint, mirroring `BookingsCacheStorage`.
///
/// This is what lets the app keep *showing* things offline: rather than
/// teaching thirty-odd repositories to cache themselves, the API client writes
/// every successful GET here and replays it when a later request can't reach
/// the server.
///
/// Bounded on purpose. `SharedPreferences` is read into memory at startup, so
/// the cache is capped both per entry and in total, evicting the
/// least-recently-written key first.
class ApiResponseCache {
  ApiResponseCache(
    this._prefs, {
    this.maxEntries = 64,
    this.maxEntryBytes = 192 * 1024,
  });

  final SharedPreferences _prefs;

  /// Maximum number of cached endpoints.
  final int maxEntries;

  /// Responses larger than this are not cached — a single huge payload would
  /// otherwise dominate the startup read.
  final int maxEntryBytes;

  static const String _entryPrefix = 'api_cache:';
  static const String _indexKey = 'api_cache_index';

  /// Cache key for [options]: method, path, query and the band the request was
  /// scoped to. The band is part of the key because nearly every response is
  /// band-scoped and the same path serves different data per band.
  ///
  /// [bandId] is passed in rather than read off the `X-Band-ID` header so the
  /// key doesn't depend on which interceptor has run yet — a request rejected
  /// before the auth interceptor attaches headers must still hash to the same
  /// key as the response that populated the cache.
  static String keyFor(RequestOptions options, {String? bandId}) {
    final uri = options.uri;
    return '${options.method}|${uri.path}|${uri.query}|${bandId ?? ''}';
  }

  CachedApiResponse? read(String key) {
    final raw = _prefs.getString('$_entryPrefix$key');
    if (raw == null) return null;
    try {
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      return CachedApiResponse(
        statusCode: (entry['status'] as num).toInt(),
        body: jsonDecode(entry['body'] as String),
        cachedAt: DateTime.fromMillisecondsSinceEpoch(
          (entry['at'] as num).toInt(),
        ),
      );
    } catch (_) {
      // Malformed blob (a format change, a truncated write) — drop it so
      // subsequent reads don't keep failing on it.
      _remove(key);
      return null;
    }
  }

  /// Stores [body] under [key]. Bodies that aren't JSON-encodable, or that
  /// exceed [maxEntryBytes], are silently skipped: caching is an optimization,
  /// never a reason to fail a request that already succeeded.
  void write(String key, {required int statusCode, required Object? body}) {
    final String encodedBody;
    try {
      encodedBody = jsonEncode(body);
    } catch (_) {
      return;
    }
    if (encodedBody.length > maxEntryBytes) return;

    final entry = jsonEncode({
      'status': statusCode,
      'at': DateTime.now().millisecondsSinceEpoch,
      'body': encodedBody,
    });

    _prefs.setString('$_entryPrefix$key', entry);
    _touch(key);
  }

  /// Drops every cached response. Called on logout so the next account on this
  /// device can't be shown the previous one's data.
  void clear() {
    for (final key in _index()) {
      _prefs.remove('$_entryPrefix$key');
    }
    _prefs.remove(_indexKey);
  }

  // ── Index / eviction ─────────────────────────────────────────────────────

  List<String> _index() {
    final raw = _prefs.getStringList(_indexKey);
    return raw == null ? <String>[] : List<String>.from(raw);
  }

  /// Moves [key] to the end of the write-ordered index and evicts from the
  /// front until the cache is back within [maxEntries].
  void _touch(String key) {
    final index = _index()
      ..remove(key)
      ..add(key);

    while (index.length > maxEntries) {
      _prefs.remove('$_entryPrefix${index.removeAt(0)}');
    }

    _prefs.setStringList(_indexKey, index);
  }

  void _remove(String key) {
    _prefs.remove('$_entryPrefix$key');
    _prefs.setStringList(_indexKey, _index()..remove(key));
  }

  @visibleForTesting
  int get entryCount => _index().length;
}

/// Resolved at startup in `main.dart` (mirrors `bookingsCacheStorageProvider`)
/// so the API client's interceptor can read and write synchronously.
///
/// Null by default rather than throwing: a null cache disables offline replay
/// but leaves every other behaviour intact, which is what unit tests that
/// build an `ApiClient` against a stub adapter want.
final apiResponseCacheProvider = Provider<ApiResponseCache?>((ref) => null);
