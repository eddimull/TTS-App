import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Keys {
  static const String bookingsMovedDismissed = 'hint_bookings_moved_dismissed';
}

/// One-time UI hints, persisted so a dismissal sticks across launches.
class HintStorage {
  HintStorage(this._prefs);
  final SharedPreferences _prefs;

  bool get bookingsMovedDismissed =>
      _prefs.getBool(_Keys.bookingsMovedDismissed) ?? false;

  Future<void> dismissBookingsMoved() =>
      _prefs.setBool(_Keys.bookingsMovedDismissed, true);
}

final hintStorageProvider = FutureProvider<HintStorage>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return HintStorage(prefs);
});
