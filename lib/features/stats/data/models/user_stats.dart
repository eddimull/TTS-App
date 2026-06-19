// Models for the user stats endpoint (`GET /api/mobile/me/stats`).
//
// Monetary values arrive as strings (e.g. "1234.56"); miles/hours arrive as
// numbers and may be null. We keep money as parsed doubles for display and
// expose the raw figures the UI needs.

class UserStats {
  const UserStats({
    required this.payments,
    required this.travel,
    required this.locations,
  });

  final PaymentStats payments;
  final TravelStats travel;
  final List<PerformanceLocation> locations;

  factory UserStats.fromJson(Map<String, dynamic> json) {
    final locationsJson = (json['locations'] as List<dynamic>? ?? []);
    return UserStats(
      payments: PaymentStats.fromJson(json['payments'] as Map<String, dynamic>? ?? const {}),
      travel: TravelStats.fromJson(json['travel'] as Map<String, dynamic>? ?? const {}),
      locations: locationsJson
          .map((l) => PerformanceLocation.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }

  /// True when the user has no earnings and no events — drives the empty state.
  bool get isEmpty => payments.bookingCount == 0 && travel.eventCount == 0;
}

// ── Payments ────────────────────────────────────────────────────────────────

class PaymentStats {
  const PaymentStats({
    required this.totalEarnings,
    required this.bookingCount,
    required this.upcomingEarnings,
    required this.upcomingBookingCount,
    required this.byYear,
    required this.byBand,
    required this.bookingsByYear,
  });

  final double totalEarnings;
  final int bookingCount;

  /// Projected earnings from gigs that haven't happened yet (date today or later).
  final double upcomingEarnings;
  final int upcomingBookingCount;

  final List<YearEarnings> byYear;
  final List<BandEarnings> byBand;
  final List<BookingsYear> bookingsByYear;

  factory PaymentStats.fromJson(Map<String, dynamic> json) {
    return PaymentStats(
      totalEarnings: _money(json['total_earnings']),
      bookingCount: (json['booking_count'] as num?)?.toInt() ?? 0,
      upcomingEarnings: _money(json['upcoming_earnings']),
      upcomingBookingCount: (json['upcoming_booking_count'] as num?)?.toInt() ?? 0,
      byYear: (json['by_year'] as List<dynamic>? ?? [])
          .map((e) => YearEarnings.fromJson(e as Map<String, dynamic>))
          .toList(),
      byBand: (json['by_band'] as List<dynamic>? ?? [])
          .map((e) => BandEarnings.fromJson(e as Map<String, dynamic>))
          .toList(),
      bookingsByYear: (json['bookings_by_year'] as List<dynamic>? ?? [])
          .map((e) => BookingsYear.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class YearEarnings {
  const YearEarnings({required this.year, required this.total});

  final int year;
  final double total;

  factory YearEarnings.fromJson(Map<String, dynamic> json) => YearEarnings(
        year: (json['year'] as num).toInt(),
        total: _money(json['total']),
      );
}

class BandEarnings {
  const BandEarnings({
    required this.bandId,
    required this.bandName,
    required this.total,
    required this.bookingCount,
  });

  final int bandId;
  final String bandName;
  final double total;
  final int bookingCount;

  factory BandEarnings.fromJson(Map<String, dynamic> json) => BandEarnings(
        bandId: (json['band_id'] as num).toInt(),
        bandName: json['band_name'] as String? ?? 'Unknown',
        total: _money(json['total']),
        bookingCount: (json['booking_count'] as num?)?.toInt() ?? 0,
      );
}

class BookingsYear {
  const BookingsYear({
    required this.year,
    required this.yearTotal,
    required this.bookingCount,
    required this.upcomingTotal,
    required this.upcomingBookingCount,
    required this.bookings,
  });

  final int year;
  final double yearTotal;
  final int bookingCount;

  /// Projected share from gigs in this year that haven't happened yet.
  final double upcomingTotal;
  final int upcomingBookingCount;

  final List<BookingRow> bookings;

  factory BookingsYear.fromJson(Map<String, dynamic> json) => BookingsYear(
        year: (json['year'] as num).toInt(),
        yearTotal: _money(json['year_total']),
        bookingCount: (json['booking_count'] as num?)?.toInt() ?? 0,
        upcomingTotal: _money(json['upcoming_total']),
        upcomingBookingCount: (json['upcoming_booking_count'] as num?)?.toInt() ?? 0,
        bookings: (json['bookings'] as List<dynamic>? ?? [])
            .map((e) => BookingRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class BookingRow {
  const BookingRow({
    required this.id,
    required this.bookingName,
    required this.bandName,
    required this.venueName,
    required this.venueAddress,
    required this.date,
    required this.status,
    required this.isUpcoming,
    required this.totalPrice,
    required this.userShare,
  });

  final int id;
  final String bookingName;
  final String bandName;
  final String venueName;
  final String? venueAddress;
  final String date;
  final String status;

  /// True when this gig's date is today or later (hasn't happened yet).
  final bool isUpcoming;

  final double totalPrice;
  final double userShare;

  factory BookingRow.fromJson(Map<String, dynamic> json) => BookingRow(
        id: (json['id'] as num).toInt(),
        bookingName: json['booking_name'] as String? ?? 'Untitled',
        bandName: json['band_name'] as String? ?? '',
        venueName: json['venue_name'] as String? ?? 'TBD',
        venueAddress: json['venue_address'] as String?,
        date: json['date'] as String? ?? '',
        status: json['status'] as String? ?? '',
        isUpcoming: json['is_upcoming'] as bool? ?? false,
        totalPrice: _money(json['total_price']),
        userShare: _money(json['user_share']),
      );
}

// ── Travel ──────────────────────────────────────────────────────────────────

class TravelStats {
  const TravelStats({
    required this.totalMiles,
    required this.totalMinutes,
    required this.totalHours,
    required this.eventCount,
    required this.byYear,
  });

  final double totalMiles;
  final int totalMinutes;
  final double totalHours;
  final int eventCount;
  final List<TravelYear> byYear;

  factory TravelStats.fromJson(Map<String, dynamic> json) => TravelStats(
        totalMiles: (json['total_miles'] as num?)?.toDouble() ?? 0,
        totalMinutes: (json['total_minutes'] as num?)?.toInt() ?? 0,
        totalHours: (json['total_hours'] as num?)?.toDouble() ?? 0,
        eventCount: (json['event_count'] as num?)?.toInt() ?? 0,
        byYear: (json['by_year'] as List<dynamic>? ?? [])
            .map((e) => TravelYear.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TravelYear {
  const TravelYear({
    required this.year,
    required this.totalMiles,
    required this.totalHours,
    required this.eventCount,
    required this.events,
  });

  final int year;
  final double totalMiles;
  final double totalHours;
  final int eventCount;
  final List<TravelEventRow> events;

  factory TravelYear.fromJson(Map<String, dynamic> json) => TravelYear(
        year: (json['year'] as num).toInt(),
        totalMiles: (json['total_miles'] as num?)?.toDouble() ?? 0,
        totalHours: (json['total_hours'] as num?)?.toDouble() ?? 0,
        eventCount: (json['event_count'] as num?)?.toInt() ?? 0,
        events: (json['events'] as List<dynamic>? ?? [])
            .map((e) => TravelEventRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TravelEventRow {
  const TravelEventRow({
    required this.date,
    required this.title,
    required this.bandName,
    required this.venueName,
    required this.venueAddress,
    required this.miles,
    required this.hours,
  });

  final String date;
  final String title;
  final String bandName;
  final String venueName;
  final String? venueAddress;
  final double? miles;
  final double? hours;

  factory TravelEventRow.fromJson(Map<String, dynamic> json) => TravelEventRow(
        date: json['date'] as String? ?? '',
        title: json['title'] as String? ?? '',
        bandName: json['band_name'] as String? ?? '',
        venueName: json['venue_name'] as String? ?? 'TBD',
        venueAddress: json['venue_address'] as String?,
        miles: (json['miles'] as num?)?.toDouble(),
        hours: (json['hours'] as num?)?.toDouble(),
      );
}

// ── Locations ───────────────────────────────────────────────────────────────

class PerformanceLocation {
  const PerformanceLocation({
    required this.title,
    required this.venueName,
    required this.venueAddress,
    required this.date,
    required this.fullAddress,
    required this.lat,
    required this.lng,
  });

  final String title;
  final String venueName;
  final String? venueAddress;
  final String date;
  final String fullAddress;
  final double? lat;
  final double? lng;

  bool get hasCoordinates => lat != null && lng != null;

  factory PerformanceLocation.fromJson(Map<String, dynamic> json) => PerformanceLocation(
        title: json['title'] as String? ?? '',
        venueName: json['venue_name'] as String? ?? '',
        venueAddress: json['venue_address'] as String?,
        date: json['date'] as String? ?? '',
        fullAddress: json['full_address'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );
}

/// Parse a money string like "1234.56" (or a number) to a double.
double _money(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
