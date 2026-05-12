import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/bookings/providers/bookings_provider.dart';
import '../../features/bookings/providers/bookings_window_provider.dart';
import '../../features/dashboard/providers/dashboard_provider.dart';
import '../../features/events/providers/events_provider.dart';
import '../../features/rehearsals/providers/rehearsals_provider.dart';

/// Single source of truth for cache invalidation after server-side mutations.
///
/// Any time a write succeeds against the API, the calling code should invoke
/// the matching `on…Changed` method here. The invalidator owns the mapping
/// from a logical event ("a booking was created") to the set of providers
/// whose cached data is now stale.
///
/// Centralizing this mapping means a new screen that watches an existing
/// provider gets correct refresh behavior for free, and adding a new cache
/// dependency only requires updating this file.
class CacheInvalidator {
  CacheInvalidator(this._ref);

  final Ref _ref;

  // ── Bookings ────────────────────────────────────────────────────────────────

  /// Call after creating or updating a booking. Pass [bookingId] when editing
  /// an existing booking so its detail cache is refreshed too.
  void onBookingChanged({required int bandId, int? bookingId}) {
    _invalidateBookingCollections(bandId);
    if (bookingId != null) {
      _ref.invalidate(
        bookingDetailProvider((bandId: bandId, bookingId: bookingId)),
      );
    }
  }

  /// Call after deleting a booking. The detail provider is also invalidated
  /// in case any screen still references it during navigation teardown.
  void onBookingDeleted({required int bandId, required int bookingId}) {
    _invalidateBookingCollections(bandId);
    _ref.invalidate(
      bookingDetailProvider((bandId: bandId, bookingId: bookingId)),
    );
  }

  /// Call when something *inside* a booking changes (payment, contact,
  /// contract) but not the booking's identity in the lists. The list
  /// providers are still refreshed because per-booking summary fields
  /// (e.g. amount paid) appear in list rows.
  void onBookingDetailChanged({required int bandId, required int bookingId}) {
    _ref.invalidate(
      bookingDetailProvider((bandId: bandId, bookingId: bookingId)),
    );
    _invalidateBookingCollections(bandId);
  }

  /// Call after editing the contact library (adding/removing a saved contact).
  void onContactLibraryChanged({required int bandId}) {
    _ref.invalidate(contactLibraryProvider);
  }

  /// Call after adding, removing, or updating an event under a booking.
  /// Refreshes the booking's detail cache and the band's bookings list
  /// (the list subtitle / event count depend on the events).
  void onBookingEventsChanged({required int bandId, required int bookingId}) {
    _ref.invalidate(
      bookingDetailProvider((bandId: bandId, bookingId: bookingId)),
    );
    _invalidateBookingCollections(bandId);
  }

  void _invalidateBookingCollections(int bandId) {
    // Family-root invalidation — drops every cached parameterization.
    // Cheaper than enumerating every (status, year, upcomingOnly) tuple any
    // screen may have queried.
    _ref.invalidate(bandBookingsProvider);
    _ref.invalidate(bookingsWindowProvider);
    _ref.invalidate(bookingDateInfoProvider(bandId));
    _ref.invalidate(bookingDateStatusesProvider(bandId));
    // Dashboard surfaces upcoming events/charts derived from band data.
    _ref.read(dashboardProvider.notifier).refresh();
  }

  // ── Band identity (name, logo, address) ─────────────────────────────────────

  /// Call after the band's display info (name, logo, etc.) changes.
  ///
  /// Returns the future from [AuthNotifier.refreshBands] so callers may
  /// `await` if they need the new data before navigating.
  Future<void> onBandIdentityChanged() {
    return _ref.read(authProvider.notifier).refreshBands();
  }

  // ── Events ──────────────────────────────────────────────────────────────────

  void onEventChanged({required String eventKey}) {
    _ref.invalidate(eventDetailProvider(eventKey));
    _ref.read(dashboardProvider.notifier).refresh();
  }

  // ── Rehearsals ──────────────────────────────────────────────────────────────

  void onRehearsalChanged({int? rehearsalId, String? eventKey}) {
    if (rehearsalId != null) {
      _ref.invalidate(rehearsalDetailProvider(rehearsalId));
    }
    if (eventKey != null) {
      _ref.invalidate(rehearsalDetailByKeyProvider(eventKey));
    }
  }
}

/// Provider for [CacheInvalidator]. Mutation sites read this and call the
/// matching `on…Changed` method after a successful repo call.
final cacheInvalidatorProvider = Provider<CacheInvalidator>(
  CacheInvalidator.new,
);
