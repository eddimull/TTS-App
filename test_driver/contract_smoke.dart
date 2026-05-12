// App entrypoint for the flutter_driver contract smoke test.
//
// This boots the real BandmateApp with the same fake SecureStorage / route
// storage overrides as the existing integration_test. The driver extension
// is enabled so the test_driver host can connect.

import 'package:flutter/widgets.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tts_bandmate/app.dart';
import 'package:tts_bandmate/core/config/router.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';

class _MemorySecureStorage extends SecureStorage {
  _MemorySecureStorage() : super(const FlutterSecureStorage());

  final Map<String, String?> _map = {};

  @override
  Future<String?> readToken() async => _map['auth_token'];
  @override
  Future<void> writeToken(String token) async => _map['auth_token'] = token;
  @override
  Future<void> deleteToken() async => _map.remove('auth_token');

  @override
  Future<String?> readBandId() async => _map['selected_band_id'];
  @override
  Future<void> writeBandId(String bandId) async =>
      _map['selected_band_id'] = bandId;
  @override
  Future<void> deleteBandId() async => _map.remove('selected_band_id');

  @override
  Future<String?> readUser() async => _map['current_user_json'];
  @override
  Future<void> writeUser(String userJson) async =>
      _map['current_user_json'] = userJson;

  @override
  Future<void> clear() async => _map.clear();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  enableFlutterDriverExtension();

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final routeStorage = RouteStorage(prefs);
  final storage = _MemorySecureStorage();

  runApp(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        routeStorageProvider.overrideWith((_) async => routeStorage),
        initialLocationProvider.overrideWithValue('/login'),
      ],
      child: const BandmateApp(),
    ),
  );
}
