import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/finances_repository.dart';
import '../data/models/finance_booking.dart';

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
