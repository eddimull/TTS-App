import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys used in secure storage.
class _Keys {
  static const String authToken = 'auth_token';
  static const String selectedBandId = 'selected_band_id';
  static const String currentUserJson = 'current_user_json';
}

/// Wraps [FlutterSecureStorage] with iOS keychain-accessibility migration.
///
/// The app moved the iOS accessibility level from the default `when_unlocked`
/// to `first_unlock` (so background token reads stop failing with
/// errSecInteractionNotAllowed, −25308). On iOS the plugin puts the
/// accessibility level in EVERY keychain query, which makes items written
/// under the old level invisible to reads — and, because keychain uniqueness
/// ignores accessibility, makes writes collide with the invisible item and
/// fail with errSecDuplicateItem. That combination locked existing installs
/// out of logging in entirely (1.17.1+27).
///
/// Two counter-measures, both no-ops on a clean install:
/// - every write deletes the key first (the plugin's delete strips the
///   accessibility filter, so it removes items written under ANY level),
///   then adds fresh under the new level;
/// - a read miss retries via [_anyAccessibility] — an instance constructed
///   WITHOUT an accessibility level, whose queries therefore match any item —
///   and migrates what it finds to the new level.
class SecureStorage {
  SecureStorage(this._storage, {FlutterSecureStorage? anyAccessibilityStorage})
      : _anyAccessibility = anyAccessibilityStorage;

  final FlutterSecureStorage _storage;

  /// iOS-only fallback whose keychain queries omit `kSecAttrAccessible`; used
  /// to find and migrate items stored before the first_unlock switch. Null on
  /// platforms without keychain accessibility semantics.
  final FlutterSecureStorage? _anyAccessibility;

  Future<String?> _read(String key) async {
    final value = await _storage.read(key: key);
    if (value != null) return value;
    final fallback = _anyAccessibility;
    if (fallback == null) return null;
    final legacy = await fallback.read(key: key);
    if (legacy == null) return null;
    await _write(key, legacy); // rewrite under the new accessibility level
    return legacy;
  }

  Future<void> _write(String key, String value) async {
    await _storage.delete(key: key);
    await _storage.write(key: key, value: value);
  }

  Future<void> _delete(String key) => _storage.delete(key: key);

  // ── Token ──────────────────────────────────────────────────────────────────

  Future<String?> readToken() => _read(_Keys.authToken);

  Future<void> writeToken(String token) => _write(_Keys.authToken, token);

  Future<void> deleteToken() => _delete(_Keys.authToken);

  // ── Band ID ────────────────────────────────────────────────────────────────

  Future<String?> readBandId() => _read(_Keys.selectedBandId);

  Future<void> writeBandId(String bandId) =>
      _write(_Keys.selectedBandId, bandId);

  Future<void> deleteBandId() => _delete(_Keys.selectedBandId);

  // ── User JSON ──────────────────────────────────────────────────────────────

  Future<String?> readUser() => _read(_Keys.currentUserJson);

  Future<void> writeUser(String userJson) =>
      _write(_Keys.currentUserJson, userJson);

  // ── Bulk ───────────────────────────────────────────────────────────────────

  Future<void> clear() => _storage.deleteAll();
}

final secureStorageProvider = Provider<SecureStorage>((ref) {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // first_unlock (not the default when_unlocked): the token is read while
    // the app is backgrounded — Pusher channel re-auth, background pushes —
    // and when_unlocked makes those reads fail with errSecInteractionNotAllowed
    // (-25308) once the device locks (BANDMATE-APP-9).
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  // Accessibility-agnostic instance (accessibility: null omits
  // kSecAttrAccessible from queries) so pre-first_unlock items can be found
  // and migrated. See the SecureStorage doc comment.
  const anyAccessibility = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: null),
  );
  final needsMigration =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  return SecureStorage(
    storage,
    anyAccessibilityStorage: needsMigration ? anyAccessibility : null,
  );
});
