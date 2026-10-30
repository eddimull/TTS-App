import 'package:flutter/cupertino.dart';

import '../../data/models/event_detail.dart';
import '../event_sections/timeline_section.dart';

/// Timeline tab: the full timeline, with the show time pinned in as a row.
class TimelineTab extends StatelessWidget {
  const TimelineTab({super.key, required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    return TimelineSection(
      entries: event.timeline,
      eventDate: event.parsedDate,
      showTime: event.time,
      eventDateStr: event.date,
    );
  }
}
