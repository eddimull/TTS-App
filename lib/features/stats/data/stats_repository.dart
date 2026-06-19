import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/user_stats.dart';

class StatsRepository {
  StatsRepository(this._dio);

  final Dio _dio;

  /// Fetch the user's personal stats (earnings, travel, performance locations)
  /// across all their bands.
  Future<UserStats> getStats() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileStats,
    );
    final data = response.data!;
    return UserStats.fromJson(data['stats'] as Map<String, dynamic>);
  }
}
