import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/finances_repository.dart';
import '../data/models/finance_booking.dart';

// ── Params ────────────────────────────────────────────────────────────────────

/// Arguments for the finances family providers.
class FinancesParams {
  const FinancesParams({required this.bandId, required this.year});

  final int bandId;
  final int year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancesParams &&
          runtimeType == other.runtimeType &&
          bandId == other.bandId &&
          year == other.year;

  @override
  int get hashCode => Object.hash(bandId, year);
}

// ── Unpaid bookings ───────────────────────────────────────────────────────────

class _UnpaidServicesNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<FinanceBooking>, FinancesParams> {
  @override
  Future<List<FinanceBooking>> build(FinancesParams arg) async {
    final repo = ref.watch(financesRepositoryProvider);
    return repo.fetchUnpaid(arg.bandId, year: arg.year);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      final repo = ref.read(financesRepositoryProvider);
      return repo.fetchUnpaid(arg.bandId, year: arg.year);
    });
  }
}

/// Provides the list of unpaid [FinanceBooking]s for a given band and year.
///
/// Usage:
/// ```dart
/// final bookings = ref.watch(
///   unpaidServicesProvider(FinancesParams(bandId: 42, year: 2026)),
/// );
/// ```
final unpaidServicesProvider = AutoDisposeAsyncNotifierProviderFamily<
    _UnpaidServicesNotifier, List<FinanceBooking>, FinancesParams>(
  _UnpaidServicesNotifier.new,
);

// ── Paid bookings ─────────────────────────────────────────────────────────────

class _PaidServicesNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<FinanceBooking>, FinancesParams> {
  @override
  Future<List<FinanceBooking>> build(FinancesParams arg) async {
    final repo = ref.watch(financesRepositoryProvider);
    return repo.fetchPaid(arg.bandId, year: arg.year);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      final repo = ref.read(financesRepositoryProvider);
      return repo.fetchPaid(arg.bandId, year: arg.year);
    });
  }
}

/// Provides the list of paid [FinanceBooking]s for a given band and year.
///
/// Usage:
/// ```dart
/// final bookings = ref.watch(
///   paidServicesProvider(FinancesParams(bandId: 42, year: 2026)),
/// );
/// ```
final paidServicesProvider = AutoDisposeAsyncNotifierProviderFamily<
    _PaidServicesNotifier, List<FinanceBooking>, FinancesParams>(
  _PaidServicesNotifier.new,
);
