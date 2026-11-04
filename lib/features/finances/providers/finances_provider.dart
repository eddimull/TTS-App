import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/finances/payout_editor/providers/payout_flow_provider.dart' show isSelectedBandOwnerProvider;
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import '../data/finances_repository.dart';
import '../data/models/band_revenue.dart';
import '../data/models/finance_booking.dart';
import '../data/models/finance_trends.dart';
import '../data/models/payments_due.dart';

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

class _PaymentsDueNotifier extends AsyncNotifier<PaymentsDue> {
  _PaymentsDueNotifier(this._bandId);
  final int _bandId;

  @override
  Future<PaymentsDue> build() =>
      ref.watch(financesRepositoryProvider).fetchDue(_bandId);

  Future<void> refresh() async {
    state = await AsyncValue.guard(
        () => ref.read(financesRepositoryProvider).fetchDue(_bandId));
  }
}

final paymentsDueProvider =
    AsyncNotifierProvider.family<_PaymentsDueNotifier, PaymentsDue, int>(
  (arg) => _PaymentsDueNotifier(arg),
);

/// How many payments are overdue on the selected band, for the owner's menu dot
/// and Operations count. Zero for non-owners, who can't load payments due, and
/// while loading or on failure: a badge should never get in the way of home.
final selectedBandOverdueCountProvider = Provider<int>((ref) {
  final bandId = ref.watch(selectedBandProvider).value;
  if (bandId == null || !ref.watch(isSelectedBandOwnerProvider)) return 0;
  return ref.watch(paymentsDueProvider(bandId)).value?.overdue.count ?? 0;
});

class _UnpaidServicesNotifier extends AsyncNotifier<List<FinanceBooking>> {
  _UnpaidServicesNotifier(this._params);
  final FinancesParams _params;

  @override
  Future<List<FinanceBooking>> build() async {
    return ref.watch(financesRepositoryProvider).fetchUnpaid(_params.bandId, year: _params.year);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(financesRepositoryProvider).fetchUnpaid(_params.bandId, year: _params.year));
  }
}

final unpaidServicesProvider = AsyncNotifierProvider.family<
    _UnpaidServicesNotifier, List<FinanceBooking>, FinancesParams>(
  (arg) => _UnpaidServicesNotifier(arg),
);

class _PaidServicesNotifier extends AsyncNotifier<List<FinanceBooking>> {
  _PaidServicesNotifier(this._params);
  final FinancesParams _params;

  @override
  Future<List<FinanceBooking>> build() async {
    return ref.watch(financesRepositoryProvider).fetchPaid(_params.bandId, year: _params.year);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(financesRepositoryProvider).fetchPaid(_params.bandId, year: _params.year));
  }
}

final paidServicesProvider = AsyncNotifierProvider.family<
    _PaidServicesNotifier, List<FinanceBooking>, FinancesParams>(
  (arg) => _PaidServicesNotifier(arg),
);

class _RevenueNotifier extends AsyncNotifier<BandRevenue> {
  _RevenueNotifier(this._bandId);
  final int _bandId;

  @override
  Future<BandRevenue> build() async {
    return ref.watch(financesRepositoryProvider).fetchRevenue(_bandId);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(financesRepositoryProvider).fetchRevenue(_bandId));
  }
}

final revenueProvider =
    AsyncNotifierProvider.family<_RevenueNotifier, BandRevenue, int>(
  (arg) => _RevenueNotifier(arg),
);

class TrendsParams {
  const TrendsParams({
    required this.bandId,
    required this.year,
    required this.snapshotDate,
    required this.compareWithCurrent,
  });

  final int bandId;
  final int year;
  final String? snapshotDate;
  final bool compareWithCurrent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrendsParams &&
          runtimeType == other.runtimeType &&
          bandId == other.bandId &&
          year == other.year &&
          snapshotDate == other.snapshotDate &&
          compareWithCurrent == other.compareWithCurrent;

  @override
  int get hashCode =>
      Object.hash(bandId, year, snapshotDate, compareWithCurrent);
}

class _TrendsNotifier extends AsyncNotifier<FinanceTrends> {
  _TrendsNotifier(this._params);
  final TrendsParams _params;

  Future<FinanceTrends> _fetch() =>
      ref.read(financesRepositoryProvider).fetchTrends(
            _params.bandId,
            year: _params.year,
            snapshotDate: _params.snapshotDate,
            compareWithCurrent: _params.compareWithCurrent,
          );

  @override
  Future<FinanceTrends> build() => _fetch();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }
}

final trendsProvider =
    AsyncNotifierProvider.family<_TrendsNotifier, FinanceTrends, TrendsParams>(
  (arg) => _TrendsNotifier(arg),
);
