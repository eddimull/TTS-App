import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys used in secure storage.
class _Keys {
  static const String authToken = 'auth_token';
  static const String selectedBandId = 'selected_band_id';
  static const String currentUserJson = 'current_user_json';
}

class SecureStorage {
  SecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  // ── Token ──────────────────────────────────────────────────────────────────

  Future<String?> readToken() => _storage.read(key: _Keys.authToken);

  Future<void> writeToken(String token) =>
      _storage.write(key: _Keys.authToken, value: token);

  Future<void> deleteToken() => _storage.delete(key: _Keys.authToken);

  // ── Band ID ────────────────────────────────────────────────────────────────

  Future<String?> readBandId() => _storage.read(key: _Keys.selectedBandId);

  Future<void> writeBandId(String bandId) =>
      _storage.write(key: _Keys.selectedBandId, value: bandId);

  Future<void> deleteBandId() => _storage.delete(key: _Keys.selectedBandId);

  // ── User JSON ──────────────────────────────────────────────────────────────

  Future<String?> readUser() => _storage.read(key: _Keys.currentUserJson);

  Future<void> writeUser(String userJson) =>
      _storage.write(key: _Keys.currentUserJson, value: userJson);

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
  return SecureStorage(storage);
});
