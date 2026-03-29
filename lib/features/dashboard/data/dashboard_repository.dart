import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../events/data/models/event_summary.dart';
import 'models/upcoming_chart.dart';

class DashboardRepository {
  DashboardRepository(this._dio);

  final Dio _dio;

  /// Fetches the dashboard payload — upcoming events and charts.
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileDashboard,
    );

    final data = response.data!;

    final rawEvents = data['events'] as List<dynamic>? ?? [];
    final events = rawEvents
        .cast<Map<String, dynamic>>()
        .map(EventSummary.fromJson)
        .toList();

    final rawCharts = data['upcoming_charts'] as List<dynamic>? ?? [];
    final upcomingCharts = rawCharts
        .cast<Map<String, dynamic>>()
        .map(UpcomingChart.fromJson)
        .toList();

    return (events: events, upcomingCharts: upcomingCharts);
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(apiClientProvider).dio);
});
