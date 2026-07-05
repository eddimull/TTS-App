import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../data/models/booking_detail.dart';

/// Opens the new-booking form for [bandId] and, when the form pops with the
/// created [BookingDetail], forwards to that booking's detail screen so the
/// user can validate it (and continue to contacts/contract) instead of being
/// dropped back on the list.
Future<void> pushNewBookingForm(BuildContext context, int bandId) async {
  final result = await context.push<Object?>('/bookings/$bandId/new');
  if (result is BookingDetail && context.mounted) {
    context.push('/bookings/$bandId/${result.id}');
  }
}
