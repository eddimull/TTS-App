import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory filter state for the merged Library screen.
///
/// Bands are stored as a *hidden* set — the default state hides nothing.
/// Resets on app restart (no persistence). Mirrors the dashboard's
/// `CalendarFilterState`, minus the event-types axis.
class LibraryFilterState {
  const LibraryFilterState({this.hiddenBandIds = const {}});

  /// Band ids the user has chosen to hide on the Library list.
  final Set<int> hiddenBandIds;

  bool get isActive => hiddenBandIds.isNotEmpty;
  int get activeCount => hiddenBandIds.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryFilterState &&
          const SetEquality<int>().equals(hiddenBandIds, other.hiddenBandIds);

  @override
  int get hashCode => const SetEquality<int>().hash(hiddenBandIds);

  LibraryFilterState copyWith({Set<int>? hiddenBandIds}) =>
      LibraryFilterState(hiddenBandIds: hiddenBandIds ?? this.hiddenBandIds);
}

class LibraryFilterNotifier extends Notifier<LibraryFilterState> {
  @override
  LibraryFilterState build() => const LibraryFilterState();

  void toggleBand(int bandId) {
    final next = Set<int>.from(state.hiddenBandIds);
    if (!next.add(bandId)) next.remove(bandId);
    state = state.copyWith(hiddenBandIds: next);
  }

  void clear() => state = const LibraryFilterState();
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilterState>(
  LibraryFilterNotifier.new,
);
