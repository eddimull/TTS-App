import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/booking_contact.dart';
import 'models/booking_detail.dart';
import 'models/booking_history_entry.dart';
import 'models/booking_summary.dart';
import 'models/contact_library_item.dart';
import 'models/event_type.dart';

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

  Future<BookingDetail> createBooking(
      int bandId, Map<String, dynamic> body) async {
    final response =
        await _dio.post(ApiEndpoints.mobileBandBookings(bandId), data: body);
    return BookingDetail.fromJson(response.data['booking']);
  }

  Future<BookingDetail> updateBooking(
      int bandId, int bookingId, Map<String, dynamic> body) async {
    final response = await _dio.patch(
        ApiEndpoints.mobileBookingById(bandId, bookingId),
        data: body);
    return BookingDetail.fromJson(response.data['booking']);
  }

  Future<void> deleteBooking(int bandId, int bookingId) async {
    await _dio.delete(ApiEndpoints.mobileBookingById(bandId, bookingId));
  }

  Future<BookingDetail> cancelBooking(int bandId, int bookingId) async {
    final response = await _dio
        .post(ApiEndpoints.mobileCancelBooking(bandId, bookingId));
    return BookingDetail.fromJson(response.data['booking']);
  }

  Future<List<ContactLibraryItem>> getContactLibrary(int bandId,
      {String? query}) async {
    final response = await _dio.get(
      ApiEndpoints.mobileBandContacts(bandId),
      queryParameters:
          query != null && query.isNotEmpty ? {'q': query} : null,
    );
    final list = response.data['contacts'] as List<dynamic>;
    return list
        .map((e) =>
            ContactLibraryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<BookingContact>> addContact(
      int bandId, int bookingId, Map<String, dynamic> body) async {
    final response = await _dio.post(
        ApiEndpoints.mobileBookingContacts(bandId, bookingId),
        data: body);
    final list = response.data['contacts'] as List<dynamic>;
    return list
        .map((e) => BookingContact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<BookingContact>> updateContact(
      int bandId, int bookingId, int bcId, Map<String, dynamic> body) async {
    final response = await _dio.patch(
        ApiEndpoints.mobileBookingContact(bandId, bookingId, bcId),
        data: body);
    final list = response.data['contacts'] as List<dynamic>;
    return list
        .map((e) => BookingContact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeContact(int bandId, int bookingId, int bcId) async {
    await _dio.delete(
        ApiEndpoints.mobileBookingContact(bandId, bookingId, bcId));
  }

  Future<Map<String, dynamic>> addPayment(
      int bandId, int bookingId, Map<String, dynamic> body) async {
    final response = await _dio.post(
        ApiEndpoints.mobileBookingPayments(bandId, bookingId),
        data: body);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deletePayment(
      int bandId, int bookingId, int paymentId) async {
    final response = await _dio.delete(
        ApiEndpoints.mobileBookingPayment(bandId, bookingId, paymentId));
    return response.data as Map<String, dynamic>;
  }

  Future<BookingDetail> uploadContract(
      int bandId, int bookingId, List<int> pdfBytes, String filename) async {
    final formData = FormData.fromMap({
      'pdf': MultipartFile.fromBytes(
        pdfBytes,
        filename: filename,
        contentType: DioMediaType('application', 'pdf'),
      ),
    });
    final response = await _dio.post(
        ApiEndpoints.mobileBookingContractUpload(bandId, bookingId),
        data: formData);
    return BookingDetail.fromJson(response.data['booking']);
  }

  Future<BookingDetail> sendContract(
      int bandId, int bookingId, int signerId, {int? ccId}) async {
    final body = <String, dynamic>{'signer_id': signerId};
    if (ccId != null) body['cc_id'] = ccId;
    final response = await _dio.post(
        ApiEndpoints.mobileBookingContractSend(bandId, bookingId),
        data: body);
    return BookingDetail.fromJson(response.data['booking']);
  }

  Future<List<BookingHistoryEntry>> getHistory(
      int bandId, int bookingId) async {
    final response = await _dio
        .get(ApiEndpoints.mobileBookingHistory(bandId, bookingId));
    final list = response.data['history'] as List<dynamic>;
    return list
        .map((e) =>
            BookingHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<EventType>> getEventTypes() async {
    final response = await _dio.get(ApiEndpoints.mobileEventTypes);
    final list = response.data['event_types'] as List<dynamic>;
    return list
        .map((e) => EventType.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  return BookingsRepository(ref.watch(apiClientProvider).dio);
});
