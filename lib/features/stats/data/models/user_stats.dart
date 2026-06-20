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
  bool get isEmpty =>
      payments.bookingCount == 0 &&
      payments.upcomingBookingCount == 0 &&
      travel.eventCount == 0;
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

  /// Per-year earned vs upcoming, sorted ascending, derived from every booking
  /// row (so future-only years appear with earned == 0).
  List<YearBreakdown> get yearBreakdown {
    final earned = <int, double>{};
    final upcoming = <int, double>{};
    for (final yearGroup in bookingsByYear) {
      for (final b in yearGroup.bookings) {
        // Parse year from the booking date string; skip undated bookings.
        final y = _yearFromDate(b.date);
        if (y == null) continue;
        if (b.isUpcoming) {
          upcoming[y] = (upcoming[y] ?? 0) + b.userShare;
        } else {
          earned[y] = (earned[y] ?? 0) + b.userShare;
        }
      }
    }
    final years = {...earned.keys, ...upcoming.keys}.toList()..sort();
    return years
        .map((y) => YearBreakdown(
              year: y,
              earned: earned[y] ?? 0,
              upcoming: upcoming[y] ?? 0,
            ))
        .toList();
  }

  /// Per-band earned vs upcoming, sorted by total descending, derived from every
  /// booking row (so upcoming-only bands appear with earned == 0).
  List<BandBreakdown> get bandBreakdown {
    final earned = <int, double>{};
    final upcoming = <int, double>{};
    final names = <int, String>{};
    for (final yearGroup in bookingsByYear) {
      for (final b in yearGroup.bookings) {
        // The API always sends a real band_id; a missing one decodes to the
        // sentinel 0. Bucket those by name (not drop them) so no money silently
        // vanishes from the chart. Capture the first non-empty name we see for a
        // band and keep it — don't let a later empty-name row overwrite it.
        if (b.bandName.isNotEmpty) {
          names[b.bandId] ??= b.bandName;
        }
        if (b.isUpcoming) {
          upcoming[b.bandId] = (upcoming[b.bandId] ?? 0) + b.userShare;
        } else {
          earned[b.bandId] = (earned[b.bandId] ?? 0) + b.userShare;
        }
      }
    }
    final bands = {...earned.keys, ...upcoming.keys}
        .map((id) => BandBreakdown(
              bandId: id,
              bandName: names[id] ?? 'Unknown',
              earned: earned[id] ?? 0,
              upcoming: upcoming[id] ?? 0,
            ))
        .toList();
    bands.sort((a, b) => b.total.compareTo(a.total));
    return bands;
  }
}

/// A year's earnings split into earned (played) and upcoming (booked) shares.
class YearBreakdown {
  const YearBreakdown({required this.year, required this.earned, required this.upcoming});

  final int year;
  final double earned;
  final double upcoming;

  double get total => earned + upcoming;
}

/// A band's earnings split into earned (played) and upcoming (booked) shares.
class BandBreakdown {
  const BandBreakdown({
    required this.bandId,
    required this.bandName,
    required this.earned,
    required this.upcoming,
  });

  final int bandId;
  final String bandName;
  final double earned;
  final double upcoming;

  double get total => earned + upcoming;
}

class YearEarnings {
  const YearEarnings({required this.year, required this.total});

  final int year;
  final double total;

  factory YearEarnings.fromJson(Map<String, dynamic> json) => YearEarnings(
        // by_year is built only from earned (past-dated) bookings, so year is
        // always present here — parse strictly rather than masking a bad
        // payload as year "0".
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

  /// Null for bookings with no events yet (no gig date), which are grouped
  /// under a year-less bucket and shown as "TBD".
  final int? year;
  final double yearTotal;
  final int bookingCount;

  /// Projected share from gigs in this year that haven't happened yet.
  final double upcomingTotal;
  final int upcomingBookingCount;

  final List<BookingRow> bookings;

  factory BookingsYear.fromJson(Map<String, dynamic> json) => BookingsYear(
        year: (json['year'] as num?)?.toInt(),
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
    required this.bandId,
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
  final int bandId;
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
        bandId: (json['band_id'] as num?)?.toInt() ?? 0,
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
        // Travel stats only count past events, so year is always present.
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

/// Extract a 4-digit year from a date string like "2025-01-15"; returns null
/// for empty or malformed strings (undated bookings).
int? _yearFromDate(String date) {
  if (date.length < 4) return null;
  return int.tryParse(date.substring(0, 4));
}
