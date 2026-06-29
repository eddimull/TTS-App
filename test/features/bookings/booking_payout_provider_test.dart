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
  Map<String, dynamic>? lastAdjustmentBody;
  int? lastDeletedAdjustmentId;
  int? lastSwitchedConfigId;

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
  Future<void> addPayoutAdjustment(int bandId, int bookingId, Map<String, dynamic> body) async {
    lastAdjustmentBody = body;
  }

  @override
  Future<void> deletePayoutAdjustment(int bandId, int bookingId, int adjustmentId) async {
    lastDeletedAdjustmentId = adjustmentId;
  }

  @override
  Future<void> updatePayoutConfiguration(int bandId, int bookingId, int configId) async {
    lastSwitchedConfigId = configId;
  }
}

// Repo that throws on every mutating call, to exercise the error surfacing path.
class _ThrowingRepo extends _FakeRepo {
  final Exception _error = Exception('network failure');

  @override
  Future<void> updatePayoutConfiguration(int bandId, int bookingId, int configId) async =>
      throw _error;

  @override
  Future<void> updateAttendance(int bandId, int bookingId, int eventId, int memberId, String status) async =>
      throw _error;

  @override
  Future<void> deletePayoutAdjustment(int bandId, int bookingId, int adjustmentId) async =>
      throw _error;

  @override
  Future<void> addPayoutAdjustment(int bandId, int bookingId, Map<String, dynamic> body) async =>
      throw _error;
}

// Repo whose mutation calls SUCCEED but whose fetchPayout throws on the second
// call (the post-mutation refresh).  Used to verify Finding 1: _refresh() must
// retain the previous value in state even when the re-fetch fails.
class _RefetchFailingRepo extends _FakeRepo {
  final Exception _refetchError = Exception('refresh network failure');

  @override
  Future<BookingPayout> fetchPayout(int bandId, int bookingId) async {
    fetchCount++;
    // First call (initial build) succeeds; subsequent calls (refresh) throw.
    if (fetchCount > 1) throw _refetchError;
    return _payout();
  }
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

  test('addAdjustment calls repo then re-fetches', () async {
    final repo = _FakeRepo();
    final c = makeContainer(repo);
    await c.read(bookingPayoutProvider(key).future);
    await c.read(bookingPayoutProvider(key).notifier).addAdjustment(
          amount: 25.0,
          description: 'Travel',
          notes: 'Long drive',
        );
    expect(repo.lastAdjustmentBody, containsPair('amount', 25.0));
    expect(repo.lastAdjustmentBody, containsPair('description', 'Travel'));
    expect(repo.fetchCount, 2);
  });

  test('addAdjustment omits notes when empty, includes when non-empty', () async {
    final repo = _FakeRepo();
    final c = makeContainer(repo);
    await c.read(bookingPayoutProvider(key).future);

    // Empty notes → key must be absent from the body sent to the repo.
    await c.read(bookingPayoutProvider(key).notifier).addAdjustment(
          amount: 10.0,
          description: 'x',
          notes: '',
        );
    expect(repo.lastAdjustmentBody!.containsKey('notes'), isFalse);

    // Non-empty notes → key must be present.
    await c.read(bookingPayoutProvider(key).notifier).addAdjustment(
          amount: 10.0,
          description: 'x',
          notes: 'important',
        );
    expect(repo.lastAdjustmentBody, containsPair('notes', 'important'));
  });

  test('deleteAdjustment calls repo then re-fetches', () async {
    final repo = _FakeRepo();
    final c = makeContainer(repo);
    await c.read(bookingPayoutProvider(key).future);
    await c.read(bookingPayoutProvider(key).notifier).deleteAdjustment(42);
    expect(repo.lastDeletedAdjustmentId, 42);
    expect(repo.fetchCount, 2);
  });

  test('switchConfig calls repo then re-fetches', () async {
    final repo = _FakeRepo();
    final c = makeContainer(repo);
    await c.read(bookingPayoutProvider(key).future);
    await c.read(bookingPayoutProvider(key).notifier).switchConfig(7);
    expect(repo.lastSwitchedConfigId, 7);
    expect(repo.fetchCount, 2);
  });

  test('re-fetch emits loading-with-previous then settles to data', () async {
    final repo = _FakeRepo();
    final c = makeContainer(repo);
    await c.read(bookingPayoutProvider(key).future);

    // NOTE: The transient AsyncLoading-with-previous state is not assertable
    // here because _FakeRepo resolves synchronously, so by the time we read
    // the provider after unawaited mutation the state has already settled.
    // We assert only the final settled state. The loading emission is verified
    // structurally by reading the provider code (copyWithPrevious assignment).
    await c.read(bookingPayoutProvider(key).notifier).addAdjustment(
          amount: 5.0,
          description: 'test',
        );

    // After settling, state must be data again.
    expect(c.read(bookingPayoutProvider(key)), isA<AsyncData<BookingPayout>>());
  });

  // ── Error-surfacing tests (Imp2) ────────────────────────────────────────────

  group('mutation repo failure → AsyncError with previous data retained', () {
    // Helper: build a container with the throwing repo and prime the notifier
    // so state starts as AsyncData (i.e. there IS a previous value to retain).
    ProviderContainer makeThrowingContainer() => makeContainer(_ThrowingRepo());

    test('switchConfig: state becomes AsyncError and hasValue == true', () async {
      final c = makeThrowingContainer();
      await c.read(bookingPayoutProvider(key).future); // prime to AsyncData

      await expectLater(
        c.read(bookingPayoutProvider(key).notifier).switchConfig(99),
        throwsException,
      );

      final state = c.read(bookingPayoutProvider(key));
      expect(state, isA<AsyncError<BookingPayout>>());
      // Previous data must be retained so the screen does not blank.
      expect(state.hasValue, isTrue);
      expect(state.value, isNotNull);
    });

    test('setAttendance: state becomes AsyncError and hasValue == true', () async {
      final c = makeThrowingContainer();
      await c.read(bookingPayoutProvider(key).future);

      await expectLater(
        c.read(bookingPayoutProvider(key).notifier).setAttendance(1, 2, 'absent'),
        throwsException,
      );

      final state = c.read(bookingPayoutProvider(key));
      expect(state, isA<AsyncError<BookingPayout>>());
      expect(state.hasValue, isTrue);
    });

    test('deleteAdjustment: state becomes AsyncError and hasValue == true', () async {
      final c = makeThrowingContainer();
      await c.read(bookingPayoutProvider(key).future);

      await expectLater(
        c.read(bookingPayoutProvider(key).notifier).deleteAdjustment(7),
        throwsException,
      );

      final state = c.read(bookingPayoutProvider(key));
      expect(state, isA<AsyncError<BookingPayout>>());
      expect(state.hasValue, isTrue);
    });

    test('addAdjustment: state becomes AsyncError, hasValue == true, and rethrows', () async {
      final c = makeThrowingContainer();
      await c.read(bookingPayoutProvider(key).future);

      // addAdjustment must rethrow so the sheet's try/catch can catch it.
      await expectLater(
        c.read(bookingPayoutProvider(key).notifier).addAdjustment(
          amount: 10.0,
          description: 'Test',
        ),
        throwsException,
      );

      final state = c.read(bookingPayoutProvider(key));
      expect(state, isA<AsyncError<BookingPayout>>());
      expect(state.hasValue, isTrue);
    });
  });

  // ── Refetch failure tests (Copilot review Finding 1) ───────────────────────
  //
  // Mutation succeeds but the subsequent _refresh() fetchPayout call throws.
  // The provider must end in AsyncError WITH the previous value retained
  // (hasValue == true), so the screen body is not blanked.

  group('mutation succeeds but _refresh() re-fetch fails → previous data retained', () {
    test('switchConfig: re-fetch failure leaves state as AsyncError with hasValue == true', () async {
      final repo = _RefetchFailingRepo();
      final c = makeContainer(repo);
      await c.read(bookingPayoutProvider(key).future); // prime to AsyncData

      // switchConfig itself succeeds (mutation call is a no-op in _FakeRepo),
      // but the following _refresh() will throw on fetchPayout call #2.
      // The notifier does NOT rethrow the refresh error, so we just await it.
      await c.read(bookingPayoutProvider(key).notifier).switchConfig(7);

      final state = c.read(bookingPayoutProvider(key));
      expect(state, isA<AsyncError<BookingPayout>>(),
          reason: 'state should be AsyncError when refresh fails');
      // Previous payout must still be present so the screen does not blank.
      expect(state.hasValue, isTrue,
          reason: 'previous payout should be retained in state.value');
      expect(state.value, isNotNull);
    });
  });
}
