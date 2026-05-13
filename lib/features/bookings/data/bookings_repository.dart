import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import '../../events/data/models/event_detail.dart';
import 'models/booking_contact.dart';
import 'models/booking_detail.dart';
import 'models/booking_history_entry.dart';
import 'models/booking_summary.dart';
import 'models/contact_library_item.dart';
import 'models/contract_history_entry.dart';
import 'models/contract_term.dart';
import 'models/event_draft.dart';
import 'models/event_type.dart';

class BookingsRepository {
  BookingsRepository(this._dio);

  final Dio _dio;

  /// Fetches the list of bookings for [bandId].
  ///
  /// Optional [status] filters by booking status (e.g. "confirmed", "pending").
  /// When [upcomingOnly] is true, only bookings on or after today are returned.
  /// When [year] is provided, only bookings in that calendar year are returned.
  Future<List<BookingSummary>> getBandBookings(
    int bandId, {
    String? status,
    bool upcomingOnly = false,
    int? year,
  }) async {
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (upcomingOnly) queryParams['upcoming'] = '1';
    if (year != null) queryParams['year'] = year.toString();

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

  /// Fetches bookings across all bands the authenticated user belongs to
  /// (owners + members only — subs are excluded server-side because bookings
  /// carry money/contract info subs shouldn't see).
  ///
  /// Used by the multi-band Bookings tab. Filters mirror [getBandBookings].
  /// [from] / [to] narrow to a date range (inclusive); pass either or both
  /// in `YYYY-MM-DD` form on the wire.
  Future<List<BookingSummary>> getAllUserBookings({
    String? status,
    bool upcomingOnly = false,
    int? year,
    DateTime? from,
    DateTime? to,
  }) async {
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (upcomingOnly) queryParams['upcoming'] = '1';
    if (year != null) queryParams['year'] = year.toString();
    if (from != null) queryParams['from'] = _formatDate(from);
    if (to != null) queryParams['to'] = _formatDate(to);

    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileMeBookings,
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final data = response.data!;
    final rawList = data['bookings'] as List<dynamic>;
    return rawList
        .cast<Map<String, dynamic>>()
        .map(BookingSummary.fromJson)
        .toList();
  }

  /// Formats [d] as `YYYY-MM-DD`. Time-of-day is dropped.
  static String _formatDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// Fetches the full detail for the booking identified by [bookingId].
  Future<BookingDetail> getBookingDetail(int bandId, int bookingId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBookingDetail(bandId, bookingId),
    );

    final data = response.data!;
    return BookingDetail.fromJson(data['booking'] as Map<String, dynamic>);
  }

  /// Create a new booking with at least one initial event.
  ///
  /// Booking-level fields go to the top-level payload keys; the initial
  /// event(s) ride in an `events:` array. Each event is serialized by
  /// [EventDraft.toJson].
  Future<BookingDetail> createBooking(
    int bandId, {
    required String name,
    required int eventTypeId,
    String? price,
    String? status,
    String? contractOption,
    String? notes,
    required List<EventDraft> events,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'event_type_id': eventTypeId,
      if (price != null) 'price': price,
      if (status != null) 'status': status,
      if (contractOption != null) 'contract_option': contractOption,
      if (notes != null) 'notes': notes,
      'events': events.map((e) => e.toJson()).toList(),
    };

    final response =
        await _dio.post(ApiEndpoints.mobileBandBookings(bandId), data: body);
    return BookingDetail.fromJson(response.data['booking']);
  }

  /// Update booking-level fields only. Date / venue / time fields are
  /// **prohibited** by the backend (Chunk 3 of the bookings/events
  /// redesign) — those live on events. To mutate an event, use
  /// [EventsRepository.updateEvent]; to add or remove events use
  /// [addEventToBooking] / [removeEventFromBooking].
  Future<BookingDetail> updateBooking(
    int bandId,
    int bookingId, {
    String? name,
    int? eventTypeId,
    String? price,
    String? status,
    String? contractOption,
    String? notes,
    String? depositType,
    String? depositValue,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (eventTypeId != null) 'event_type_id': eventTypeId,
      if (price != null) 'price': price,
      if (status != null) 'status': status,
      if (contractOption != null) 'contract_option': contractOption,
      if (notes != null) 'notes': notes,
      if (depositType != null) 'deposit_type': depositType,
      if (depositValue != null) 'deposit_value': depositValue,
    };

    final response = await _dio.patch(
        ApiEndpoints.mobileBookingById(bandId, bookingId),
        data: body);
    return BookingDetail.fromJson(response.data['booking']);
  }

  /// Create a new event under an existing booking.
  Future<EventDetail> addEventToBooking(
    int bandId,
    int bookingId,
    EventDraft draft,
  ) async {
    final response = await _dio.post(
      ApiEndpoints.mobileBookingEvents(bandId, bookingId),
      data: draft.toJson(),
    );
    return EventDetail.fromJson(response.data['event']);
  }

  /// Delete an event from a booking. The backend rejects with HTTP 422
  /// when this would leave the booking with zero events; that surfaces
  /// as a [DioException] for the UI to handle.
  Future<void> removeEventFromBooking(
    int bandId,
    int bookingId,
    int eventId,
  ) async {
    await _dio.delete(
      ApiEndpoints.mobileBookingEvent(bandId, bookingId, eventId),
    );
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

  /// Save the booking's contract custom terms.
  Future<BookingDetail> saveContractTerms(
    int bandId,
    int bookingId,
    List<ContractTerm> terms,
  ) async {
    final response = await _dio.post(
      ApiEndpoints.mobileBookingContractTerms(bandId, bookingId),
      data: {'custom_terms': terms.map((t) => t.toJson()).toList()},
    );
    return BookingDetail.fromJson(response.data['booking']);
  }

  /// Fetch the PandaDoc audit trail for the contract.
  ///
  /// The backend may shape the response as either
  /// `{"history": {"results": [...]}}` (PandaDoc's native pagination)
  /// or `{"history": [...]}` (already-flattened). We accept both.
  Future<List<ContractHistoryEntry>> fetchContractHistory(
    String envelopeId,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileContractHistory(envelopeId),
    );
    final raw = response.data!['history'];
    final list = raw is Map<String, dynamic>
        ? (raw['results'] as List<dynamic>? ?? const [])
        : (raw as List<dynamic>? ?? const []);
    return list
        .cast<Map<String, dynamic>>()
        .map(ContractHistoryEntry.fromJson)
        .toList();
  }

  /// Download the booking's contract PDF bytes.
  Future<Uint8List> downloadContractPdf(int bandId, int bookingId) async {
    final response = await _dio.get<List<int>>(
      ApiEndpoints.mobileBookingContractDownload(bandId, bookingId),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  /// Fetch a short-lived signed URL pointing at the contract view endpoint.
  /// Used on Flutter web where WebView cannot inject bearer headers.
  Future<String> fetchContractViewUrl(int bandId, int bookingId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBookingContractViewUrl(bandId, bookingId),
    );
    return response.data!['url'] as String;
  }
}

final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  return BookingsRepository(ref.watch(apiClientProvider).dio);
});
