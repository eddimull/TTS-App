import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../events/data/models/event_summary.dart';

/// In-memory filter state for the dashboard calendar.
///
/// Bands and event types are stored as *hidden* sets — the default state hides
/// nothing. Resets on app restart (no persistence).
class CalendarFilterState {
  const CalendarFilterState({
    this.hiddenBandIds = const {},
    this.hiddenEventTypes = const {},
  });

  /// Band ids the user has chosen to hide.
  final Set<int> hiddenBandIds;

  /// Event sources the user has chosen to hide. Values are
  /// `'booking'`, `'rehearsal'`, or `'band_event'`.
  final Set<String> hiddenEventTypes;

  bool get isActive =>
      hiddenBandIds.isNotEmpty || hiddenEventTypes.isNotEmpty;

  int get activeCount => hiddenBandIds.length + hiddenEventTypes.length;

  bool isEventVisible(EventSummary event) {
    final band = event.band;
    if (band != null && hiddenBandIds.contains(band.id)) return false;
    if (hiddenEventTypes.contains(event.eventSource)) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarFilterState &&
          const SetEquality<int>().equals(hiddenBandIds, other.hiddenBandIds) &&
          const SetEquality<String>()
              .equals(hiddenEventTypes, other.hiddenEventTypes);

  @override
  int get hashCode => Object.hash(
        const SetEquality<int>().hash(hiddenBandIds),
        const SetEquality<String>().hash(hiddenEventTypes),
      );

  CalendarFilterState copyWith({
    Set<int>? hiddenBandIds,
    Set<String>? hiddenEventTypes,
  }) =>
      CalendarFilterState(
        hiddenBandIds: hiddenBandIds ?? this.hiddenBandIds,
        hiddenEventTypes: hiddenEventTypes ?? this.hiddenEventTypes,
      );
}

class CalendarFilterNotifier extends Notifier<CalendarFilterState> {
  @override
  CalendarFilterState build() => const CalendarFilterState();

  void toggleBand(int bandId) {
    final next = Set<int>.from(state.hiddenBandIds);
    if (!next.add(bandId)) next.remove(bandId);
    state = state.copyWith(hiddenBandIds: next);
  }

  void toggleEventType(String source) {
    final next = Set<String>.from(state.hiddenEventTypes);
    if (!next.add(source)) next.remove(source);
    state = state.copyWith(hiddenEventTypes: next);
  }

  void clear() => state = const CalendarFilterState();
}

final calendarFilterProvider =
    NotifierProvider<CalendarFilterNotifier, CalendarFilterState>(
  CalendarFilterNotifier.new,
);
