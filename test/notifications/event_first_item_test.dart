import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/notifications/data/event_first_item.dart';

void main() {
  test('resolveFirstItem picks earliest parseable entry with its time', () {
    final t = resolveFirstItem(const [
      EventTimelineEntry(title: 'Show', time: '2026-06-14T19:00:00'),
      EventTimelineEntry(title: 'Load In', time: '2026-06-14T14:00:00'),
      EventTimelineEntry(title: 'No Time', time: null),
    ]);
    expect(t, isNotNull);
    expect(t!.title, 'Load In');
    expect(t.time, DateTime(2026, 6, 14, 14, 0));
  });

  test('null when no parseable entries', () {
    expect(resolveFirstItem(const [EventTimelineEntry(title: 'x', time: null)]), isNull);
    expect(resolveFirstItem(const []), isNull);
  });
}
