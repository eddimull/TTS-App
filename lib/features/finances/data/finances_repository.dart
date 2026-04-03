import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/finance_booking.dart';

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
}

final financesRepositoryProvider = Provider<FinancesRepository>((ref) {
  return FinancesRepository(ref.watch(apiClientProvider).dio);
});
