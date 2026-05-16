import 'booking_detail.dart';

enum DepositType { percent, amount }

class ResolvedDeposit {
  const ResolvedDeposit({
    required this.depositAmount,
    required this.remainingAmount,
  });

  final String depositAmount;
  final String remainingAmount;
}

class Deposit {
  static ResolvedDeposit resolve(BookingDetail booking) {
    final price = double.tryParse(booking.price ?? '') ?? 0;
    if (price <= 0) {
      return const ResolvedDeposit(depositAmount: '0.00', remainingAmount: '0.00');
    }

    double depositDollars;
    if (booking.expectedDepositAmount != null) {
      depositDollars = double.tryParse(booking.expectedDepositAmount!) ?? 0;
    } else {
      final value = double.tryParse(booking.depositValue) ?? 0;
      depositDollars = booking.depositType == 'amount'
          ? value
          : price * (value / 100);
    }

    return ResolvedDeposit(
      depositAmount: depositDollars.toStringAsFixed(2),
      remainingAmount: (price - depositDollars).toStringAsFixed(2),
    );
  }
}
