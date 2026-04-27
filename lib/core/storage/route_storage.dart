import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Keys {
  static const String lastRoute = 'last_route';
  static const String lastRouteTimestamp = 'last_route_timestamp';
}

class RouteStorage {
  RouteStorage(this._prefs);

  final SharedPreferences _prefs;

  String? readLastRoute() => _prefs.getString(_Keys.lastRoute);

  DateTime? readLastRouteTimestamp() {
    final ms = _prefs.getString(_Keys.lastRouteTimestamp);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(ms));
  }

  Future<void> writeLastRoute(String path) async {
    await _prefs.setString(_Keys.lastRoute, path);
    await _prefs.setString(
      _Keys.lastRouteTimestamp,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  Future<void> clearLastRoute() async {
    await _prefs.remove(_Keys.lastRoute);
    await _prefs.remove(_Keys.lastRouteTimestamp);
  }
}

final routeStorageProvider = FutureProvider<RouteStorage>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return RouteStorage(prefs);
});
