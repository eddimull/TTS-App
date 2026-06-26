import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/band_revenue.dart';
import 'models/finance_booking.dart';
import 'models/finance_trends.dart';

class FinancesRepository {
  FinancesRepository(this._dio);

  final Dio _dio;

  /// Fetches bookings with an outstanding balance for [bandId].
  /// Pass [year] to scope results to a specific calendar year.
  Future<List<FinanceBooking>> fetchUnpaid(int bandId, {int? year}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandFinancesUnpaid(bandId),
      queryParameters: year != null ? {'year': year.toString()} : null,
    );
    final rawList = response.data!['bookings'] as List<dynamic>;
    return rawList
        .cast<Map<String, dynamic>>()
        .map(FinanceBooking.fromJson)
        .toList();
  }

  /// Fetches fully paid bookings for [bandId].
  /// Pass [year] to scope results to a specific calendar year.
  Future<List<FinanceBooking>> fetchPaid(int bandId, {int? year}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandFinancesPaid(bandId),
      queryParameters: year != null ? {'year': year.toString()} : null,
    );
    final rawList = response.data!['bookings'] as List<dynamic>;
    return rawList
        .cast<Map<String, dynamic>>()
        .map(FinanceBooking.fromJson)
        .toList();
  }

  /// Fetches total recorded revenue grouped by year for [bandId], newest first.
  Future<BandRevenue> fetchRevenue(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandFinancesRevenue(bandId),
    );
    return BandRevenue.fromJson(response.data!);
  }

  /// Fetches per-month finance trends for [bandId] and [year]. When
  /// [snapshotDate] (YYYY-MM-DD) is set, the primary series is as-of that date;
  /// [compareWithCurrent] (only meaningful with a snapshot) also returns the
  /// current series for comparison.
  Future<FinanceTrends> fetchTrends(
    int bandId, {
    required int year,
    String? snapshotDate,
    bool compareWithCurrent = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandFinancesTrends(bandId),
      queryParameters: {
        'year': year.toString(),
        if (snapshotDate != null) 'snapshot_date': snapshotDate,
        if (compareWithCurrent) 'compare_with_current': '1',
      },
    );
    return FinanceTrends.fromJson(response.data!);
  }
}

final financesRepositoryProvider = Provider<FinancesRepository>((ref) {
  return FinancesRepository(ref.watch(apiClientProvider).dio);
});
