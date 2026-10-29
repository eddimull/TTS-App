import 'models/event_detail.dart';

/// Tabs on the event detail screen, in display order.
enum EventTab {
  overview('Overview'),
  timeline('Timeline'),
  music('Music'),
  notes('Notes');

  const EventTab(this.label);
  final String label;
}

/// Tabs worth showing for [event]. Overview and Notes are always present;
/// Timeline needs timeline entries; Music needs anything performance related
/// (notes, songs, charts, wedding dances) or a running live session.
List<EventTab> visibleTabs(EventDetail event) {
  final perf = event.performance;
  final hasMusic = (perf != null &&
          ((perf.notes?.isNotEmpty ?? false) ||
              perf.songs.isNotEmpty ||
              perf.charts.isNotEmpty)) ||
      (event.wedding?.dances.isNotEmpty ?? false) ||
      event.liveSessionId != null;

  return [
    EventTab.overview,
    if (event.timeline.isNotEmpty) EventTab.timeline,
    if (hasMusic) EventTab.music,
    EventTab.notes,
  ];
}

/// Tab to open on: the remembered one ([stored], an [EventTab.name]) when it
/// is visible on this event, otherwise Overview.
EventTab resolveInitialTab(String? stored, List<EventTab> visible) {
  for (final tab in visible) {
    if (tab.name == stored) return tab;
  }
  return EventTab.overview;
}
