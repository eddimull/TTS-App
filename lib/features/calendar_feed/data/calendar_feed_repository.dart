import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/calendar_feed.dart';

class CalendarFeedRepository {
  CalendarFeedRepository(this._dio);

  final Dio _dio;

  /// Fetch the user's calendar subscription URLs, minting the token on the
  /// backend on first call.
  Future<CalendarFeed> getCalendarFeed() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileCalendarFeed,
    );
    return CalendarFeed.fromJson(response.data!);
  }

  /// Rotate the token, invalidating any previously shared feed URL, and return
  /// the new URLs.
  Future<CalendarFeed> resetCalendarFeed() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileCalendarFeedReset,
    );
    return CalendarFeed.fromJson(response.data!);
  }
}
