import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';

void main() {
  group('DashboardState.copyWith', () {
    test('defaults: empty, not loading older, start not reached', () {
      final from = DateTime(2026, 6, 1);
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: from,
      );

      expect(state.events, isEmpty);
      expect(state.loadedFrom, from);
      expect(state.isLoadingOlder, isFalse);
      expect(state.hasReachedStart, isFalse);
    });

    test('copyWith overrides only the named fields', () {
      final from = DateTime(2026, 6, 1);
      final earlier = DateTime(2026, 5, 2);
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: from,
      );

      final next = state.copyWith(
        loadedFrom: earlier,
        isLoadingOlder: true,
        hasReachedStart: true,
      );

      expect(next.loadedFrom, earlier);
      expect(next.isLoadingOlder, isTrue);
      expect(next.hasReachedStart, isTrue);
      expect(next.events, same(state.events));
      expect(next.upcomingCharts, same(state.upcomingCharts));
    });
  });
}
