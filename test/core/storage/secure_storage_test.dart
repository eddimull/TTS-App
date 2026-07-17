import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';

/// Simulates the iOS keychain semantics that broke auth in 1.17.1+27 when the
/// accessibility level changed to first_unlock (see darwin plugin
/// FlutterSecureStorage.swift):
/// - items keep the accessibility they were written with;
/// - read/containsKey queries FILTER on the instance's accessibility (an item
///   written under a different level is invisible), unless the instance has
///   no accessibility, in which case the query matches any item;
/// - SecItemAdd rejects a duplicate key regardless of accessibility
///   (errSecDuplicateItem — this is what made login fail);
/// - delete ignores accessibility (performDelete strips it from the query).
class FakeKeychain {
  final Map<String, ({String value, String? accessibility})> items = {};
}

class FakeFlutterSecureStorage extends FlutterSecureStorage {
  FakeFlutterSecureStorage(this.keychain, this.accessibility) : super();

  final FakeKeychain keychain;
  final String? accessibility;

  bool _visible(({String value, String? accessibility})? item) =>
      item != null &&
      (accessibility == null || item.accessibility == accessibility);

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final item = keychain.items[key];
    return _visible(item) ? item!.value : null;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final existing = keychain.items[key];
    if (existing != null && !_visible(existing)) {
      // containsKey (filtered) said "absent" → plugin calls SecItemAdd, which
      // collides with the invisible item under the same key.
      throw PlatformException(
          code: 'Unexpected security result code',
          message: 'errSecDuplicateItem (-25299)');
    }
    keychain.items[key] = (value: value!, accessibility: accessibility);
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    keychain.items.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    keychain.items.clear();
  }
}

void main() {
  late FakeKeychain keychain;
  late SecureStorage storage;

  setUp(() {
    keychain = FakeKeychain();
    storage = SecureStorage(
      FakeFlutterSecureStorage(keychain, 'first_unlock'),
      anyAccessibilityStorage: FakeFlutterSecureStorage(keychain, null),
    );
  });

  group('accessibility migration (iOS first_unlock switch)', () {
    test('login succeeds over a leftover item with the old accessibility', () async {
      // Token stored by a build that used the default when_unlocked level.
      keychain.items['auth_token'] =
          (value: 'old-token', accessibility: 'unlocked');

      // Without delete-before-write this throws errSecDuplicateItem — the
      // 1.17.1+27 "cannot authenticate" bug.
      await storage.writeToken('new-token');

      expect(await storage.readToken(), 'new-token');
      expect(keychain.items['auth_token']?.accessibility, 'first_unlock');
    });

    test('read finds an old-accessibility item and migrates it', () async {
      keychain.items['auth_token'] =
          (value: 'old-token', accessibility: 'unlocked');

      expect(await storage.readToken(), 'old-token');
      // Item rewritten under the new level so plain reads work from now on.
      expect(keychain.items['auth_token']?.accessibility, 'first_unlock');
      expect(await storage.readToken(), 'old-token');
    });

    test('read returns null when nothing is stored', () async {
      expect(await storage.readToken(), isNull);
    });

    test('all keys round-trip and migrate, not just the token', () async {
      keychain.items['selected_band_id'] =
          (value: '7', accessibility: 'unlocked');
      expect(await storage.readBandId(), '7');
      expect(keychain.items['selected_band_id']?.accessibility, 'first_unlock');

      await storage.writeUser('{"id":1}');
      expect(await storage.readUser(), '{"id":1}');
    });

    test('delete removes the item regardless of stored accessibility',
        () async {
      keychain.items['auth_token'] =
          (value: 'old-token', accessibility: 'unlocked');
      await storage.deleteToken();
      expect(keychain.items.containsKey('auth_token'), isFalse);
    });
  });

  group('without a fallback instance (Android and friends)', () {
    test('plain round-trip works', () async {
      final plain = SecureStorage(FakeFlutterSecureStorage(keychain, null));
      await plain.writeToken('t');
      expect(await plain.readToken(), 't');
      await plain.deleteToken();
      expect(await plain.readToken(), isNull);
    });
  });
}
