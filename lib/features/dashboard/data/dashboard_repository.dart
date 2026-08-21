import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../events/data/models/event_summary.dart';
import 'models/upcoming_chart.dart';

class DashboardRepository {
  DashboardRepository(this._dio);

  final Dio _dio;

  /// Parses the dashboard payload. Shared by live fetches and the offline
  /// cache so both go through identical decoding.
  static ({List<EventSummary> events, List<UpcomingChart> upcomingCharts})
      parseDashboard(Map<String, dynamic> data) {
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

  /// Fetches the dashboard payload — upcoming events and charts.
  /// [to] (yyyy-MM-dd, exclusive) bounds the forward window; events beyond it
  /// are fetched lazily via [loadNewerEvents].
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard({String? to}) async {
    final result = await getDashboardRaw(to: to);
    return (events: result.events, upcomingCharts: result.upcomingCharts);
  }

  /// Like [getDashboard] but also returns the raw response JSON so callers
  /// can persist it verbatim (the models have no `toJson`).
  Future<
      ({
        List<EventSummary> events,
        List<UpcomingChart> upcomingCharts,
        Map<String, dynamic> raw
      })> getDashboardRaw({String? to}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileDashboard,
      queryParameters: {if (to != null) 'to': to},
    );

    final data = response.data!;
    final parsed = parseDashboard(data);
    return (
      events: parsed.events,
      upcomingCharts: parsed.upcomingCharts,
      raw: data
    );
  }

  /// Fetches an older 30-day window of events for the calendar's lazy
  /// back-fetch. [beforeDate] is an ISO-8601 date string; the server returns
  /// events in [beforeDate - 30d, beforeDate).
  Future<List<EventSummary>> loadOlderEvents(String beforeDate) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileDashboardLoadOlder,
      queryParameters: {'before_date': beforeDate},
    );

    final rawEvents = response.data?['events'] as List<dynamic>? ?? [];
    return rawEvents
        .cast<Map<String, dynamic>>()
        .map(EventSummary.fromJson)
        .toList();
  }

  /// Fetches a future window of events for the calendar's lazy forward-fetch.
  /// Both bounds are yyyy-MM-dd strings; the window is [afterDate, beforeDate).
  Future<List<EventSummary>> loadNewerEvents(
      String afterDate, String beforeDate) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileDashboardLoadNewer,
      queryParameters: {'after_date': afterDate, 'before_date': beforeDate},
    );

    final rawEvents = response.data?['events'] as List<dynamic>? ?? [];
    return rawEvents
        .cast<Map<String, dynamic>>()
        .map(EventSummary.fromJson)
        .toList();
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(apiClientProvider).dio);
});
