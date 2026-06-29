import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_payout.dart';
import 'package:tts_bandmate/features/bookings/providers/booking_payout_provider.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';

class _FakeCacheInvalidator extends CacheInvalidator {
  _FakeCacheInvalidator(super.ref);

  @override
  void onBookingDetailChanged({required int bandId, required int bookingId, String? contractEnvelopeId}) {
    // no-op in tests — avoids pulling in bookingsCacheStorageProvider
  }
}

class _FakeRepo extends BookingsRepository {
  _FakeRepo() : super(Dio());
  int fetchCount = 0;
  String? lastAttendance;

  BookingPayout _payout() => BookingPayout.fromJson({
        'payout': {'id': 1, 'base_amount': '100.00', 'adjusted_amount': '100.00', 'payout_config_id': 1},
        'config': {'id': 1, 'name': 'C', 'is_active': true},
        'result': {'band_cut': 0.0, 'distributable_amount': 100.0, 'member_payouts': [], 'payment_group_payouts': []},
        'adjustments': [], 'events': [], 'available_configs': [],
      });

  @override
  Future<BookingPayout> fetchPayout(int bandId, int bookingId) async {
    fetchCount++;
    return _payout();
  }

  @override
  Future<void> updateAttendance(int bandId, int bookingId, int eventId, int memberId, String status) async {
    lastAttendance = status;
  }

  @override
  Future<void> addPayoutAdjustment(int bandId, int bookingId, Map<String, dynamic> body) async {}
}

void main() {
  ProviderContainer makeContainer(_FakeRepo repo) {
    final c = ProviderContainer(overrides: [
      bookingsRepositoryProvider.overrideWithValue(repo),
      cacheInvalidatorProvider.overrideWith((ref) => _FakeCacheInvalidator(ref)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  const key = (bandId: 1, bookingId: 2);

  test('build fetches the payout once', () async {
    final repo = _FakeRepo();
    final c = makeContainer(repo);
    final payout = await c.read(bookingPayoutProvider(key).future);
    expect(payout.distributable, 100.0);
    expect(repo.fetchCount, 1);
  });

  test('setAttendance calls repo then re-fetches', () async {
    final repo = _FakeRepo();
    final c = makeContainer(repo);
    await c.read(bookingPayoutProvider(key).future);
    await c.read(bookingPayoutProvider(key).notifier).setAttendance(3, 5, 'absent');
    expect(repo.lastAttendance, 'absent');
    expect(repo.fetchCount, 2); // initial build + post-mutation refetch
  });
}
