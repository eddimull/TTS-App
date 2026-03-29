import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/booking_detail.dart';
import 'models/booking_summary.dart';

class BookingsRepository {
  BookingsRepository(this._dio);

  final Dio _dio;

  /// Fetches the list of bookings for [bandId].
  ///
  /// Optional [status] filters by booking status (e.g. "confirmed", "pending").
  /// When [upcomingOnly] is true, only bookings on or after today are returned.
  Future<List<BookingSummary>> getBandBookings(
    int bandId, {
    String? status,
    bool upcomingOnly = false,
  }) async {
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (upcomingOnly) queryParams['upcoming'] = '1';

    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandBookings(bandId),
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final data = response.data!;
    final rawList = data['bookings'] as List<dynamic>;
    return rawList
        .cast<Map<String, dynamic>>()
        .map(BookingSummary.fromJson)
        .toList();
  }

  /// Fetches the full detail for the booking identified by [bookingId].
  Future<BookingDetail> getBookingDetail(int bandId, int bookingId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBookingDetail(bandId, bookingId),
    );

    final data = response.data!;
    return BookingDetail.fromJson(data['booking'] as Map<String, dynamic>);
  }
}

final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  return BookingsRepository(ref.watch(apiClientProvider).dio);
});
