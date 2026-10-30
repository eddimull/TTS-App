import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/event_tabs.dart';

const String eventLastTabKey = 'event_last_tab';

/// Remembers the last event-screen tab on this phone (not per event, not
/// synced), so the screen opens where the user left off.
class EventTabStorage {
  EventTabStorage(this._prefs);
  final SharedPreferences _prefs;

  /// [EventTab.name] of the last tab used, or null if none yet.
  String? get lastTab => _prefs.getString(eventLastTabKey);

  Future<void> saveLastTab(EventTab tab) =>
      _prefs.setString(eventLastTabKey, tab.name);
}

final eventTabStorageProvider = FutureProvider<EventTabStorage>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return EventTabStorage(prefs);
});
