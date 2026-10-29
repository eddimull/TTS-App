import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/events/data/event_tabs.dart';
import 'package:tts_bandmate/features/events/providers/event_tab_storage.dart';

void main() {
  test('nothing stored by default', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = EventTabStorage(await SharedPreferences.getInstance());
    expect(storage.lastTab, isNull);
  });

  test('saved tab is read back under event_last_tab', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = EventTabStorage(prefs);
    await storage.saveLastTab(EventTab.notes);
    expect(storage.lastTab, 'notes');
    expect(prefs.getString('event_last_tab'), 'notes');
  });

  test('remembered tab feeds resolveInitialTab', () async {
    SharedPreferences.setMockInitialValues({'event_last_tab': 'music'});
    final storage = EventTabStorage(await SharedPreferences.getInstance());
    expect(resolveInitialTab(storage.lastTab, EventTab.values), EventTab.music);
    // Hidden on this event: fall back.
    expect(
      resolveInitialTab(storage.lastTab, [EventTab.overview, EventTab.notes]),
      EventTab.overview,
    );
  });
}
