import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/balance_write_off.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contract.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/data/models/payment_due_state.dart';
import 'package:tts_bandmate/features/bookings/widgets/deposit_finance_row.dart';

PaymentDue _due(String owed, String dueDate, {String status = 'upcoming', String? since}) =>
    PaymentDue(owed: owed, dueDate: dueDate, status: status, overdueSince: since);

PaymentDueState _state({PaymentDue? deposit, PaymentDue? balance}) => PaymentDueState(
      eventDate: '2027-03-06',
      deposit: deposit ?? _due('0.00', '2026-11-25'),
      balance: balance ?? _due('750.00', '2027-02-27'),
    );

BookingDetail _booking({
  String? price = '1000.00',
  String depositType = 'percent',
  String depositValue = '25.00',
  String? expectedDepositAmount = '250.00',
  String amountDue = '750.00',
  bool isPaid = false,
  String? status = 'confirmed',
  String? contractOption = 'default',
  String? contractStatus,
  PaymentDueState? paymentDue,
  BalanceWriteOff? writeOff,
}) =>
    BookingDetail(
      id: 1,
      name: 'Test',
      startDate: '2027-03-06',
      endDate: '2027-03-06',
      eventCount: 1,
      isMultiEvent: false,
      isPaid: isPaid,
      contacts: const [],
      events: const [],
      price: price,
      amountDue: amountDue,
      status: status,
      contractOption: contractOption,
      contract: contractStatus == null
          ? null
          : BookingContract.fromJson({'id': 1, 'status': contractStatus}),
      depositType: depositType,
      depositValue: depositValue,
      expectedDepositAmount: expectedDepositAmount,
      paymentDue: paymentDue,
      writeOff: writeOff,
    );

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      CupertinoApp(home: CupertinoPageScaffold(child: child)),
    );

void main() {
  group('DepositFinanceRow', () {
    testWidgets('explains the rule before the contract is signed', (tester) async {
      await _pump(tester, DepositFinanceRow(booking: _booking()));

      expect(find.text('Deposit (25%)'), findsOneWidget);
      expect(find.text(r'$250.00'), findsOneWidget);
      expect(find.text('Due 3 weeks after signing'), findsOneWidget);
    });

    testWidgets('a flat deposit has no percent', (tester) async {
      await _pump(
        tester,
        DepositFinanceRow(
          booking: _booking(
            depositType: 'amount',
            depositValue: '300.00',
            expectedDepositAmount: '300.00',
          ),
        ),
      );

      expect(find.text('Deposit'), findsOneWidget);
      expect(find.text(r'$300.00'), findsOneWidget);
    });

    testWidgets('names what is left and when', (tester) async {
      await _pump(
        tester,
        DepositFinanceRow(
          booking: _booking(paymentDue: _state(deposit: _due('150.00', '2026-11-25'))),
        ),
      );

      expect(find.text(r'$150.00 still due by Nov 25, 2026'), findsOneWidget);
    });

    testWidgets('flags an overdue deposit', (tester) async {
      await _pump(
        tester,
        DepositFinanceRow(
          booking: _booking(
            paymentDue: _state(
              deposit: _due('250.00', '2026-10-12', status: 'overdue', since: '2026-10-12'),
            ),
          ),
        ),
      );

      expect(find.text(r'$250.00 overdue since Oct 12, 2026'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.exclamationmark_circle), findsOneWidget);
    });

    testWidgets('reads as paid once payments cover it', (tester) async {
      await _pump(tester, DepositFinanceRow(booking: _booking(paymentDue: _state())));

      expect(find.text('Deposit paid'), findsOneWidget);
      expect(find.textContaining('still due'), findsNothing);
    });

    testWidgets('renders nothing with no deposit, price or contract', (tester) async {
      for (final booking in [
        _booking(price: null, expectedDepositAmount: null),
        _booking(depositValue: '0.00', expectedDepositAmount: '0.00'),
        _booking(contractOption: 'none'),
      ]) {
        await _pump(tester, DepositFinanceRow(booking: booking));
        expect(find.textContaining('Deposit'), findsNothing);
      }
    });

    testWidgets('promises no due date on a cancelled or signed-but-unconfirmed booking',
        (tester) async {
      for (final booking in [
        _booking(status: 'cancelled'),
        _booking(status: 'pending', contractStatus: 'completed'),
      ]) {
        await _pump(tester, DepositFinanceRow(booking: booking));
        expect(find.text('Deposit (25%)'), findsOneWidget);
        expect(find.text('Due 3 weeks after signing'), findsNothing);
      }
    });
  });

  group('BalanceFinanceRow', () {
    Text valueText(WidgetTester tester) =>
        tester.widget<Text>(find.text(r'$750.00'));

    testWidgets('stays neutral with no due date yet', (tester) async {
      await _pump(tester, BalanceFinanceRow(booking: _booking()));

      expect(valueText(tester).style?.color, isNull);
    });

    testWidgets('says the rest is due by its date while the deposit is unpaid', (tester) async {
      await _pump(
        tester,
        BalanceFinanceRow(
          booking: _booking(paymentDue: _state(deposit: _due('250.00', '2026-11-25'))),
        ),
      );

      expect(find.text('Rest due by Feb 27, 2027'), findsOneWidget);
      expect(valueText(tester).style?.color, isNull);
    });

    testWidgets('says due by its date once the deposit is paid', (tester) async {
      await _pump(tester, BalanceFinanceRow(booking: _booking(paymentDue: _state())));

      expect(find.text('Due by Feb 27, 2027'), findsOneWidget);
    });

    testWidgets('says due, not rest due, when deposit and balance share a deadline',
        (tester) async {
      await _pump(
        tester,
        BalanceFinanceRow(
          booking: _booking(
            paymentDue: PaymentDueState(
              eventDate: '2027-03-06',
              merged: true,
              deposit: _due('250.00', '2027-02-27'),
              balance: _due('1000.00', '2027-02-27'),
            ),
          ),
        ),
      );

      expect(find.text('Due by Feb 27, 2027'), findsOneWidget);
    });

    testWidgets('reads due now, not overdue, in the last 7 days', (tester) async {
      await _pump(
        tester,
        BalanceFinanceRow(
          booking: _booking(
            paymentDue: _state(balance: _due('750.00', '2027-02-27', status: 'due_now')),
          ),
        ),
      );

      expect(find.text('Due now, show is Mar 6, 2027'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.exclamationmark_circle), findsNothing);
    });

    testWidgets('turns overdue after the show', (tester) async {
      await _pump(
        tester,
        BalanceFinanceRow(
          booking: _booking(
            paymentDue: _state(
              balance: _due('750.00', '2027-02-27', status: 'overdue', since: '2027-03-06'),
            ),
          ),
        ),
      );

      expect(find.text('Overdue since the Mar 6, 2027 show'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.exclamationmark_circle), findsOneWidget);
      expect(valueText(tester).style?.color, isNotNull);
    });

    testWidgets('shows no status when paid in full', (tester) async {
      await _pump(tester, BalanceFinanceRow(booking: _booking(amountDue: '0.00', isPaid: true)));

      expect(find.text(r'$0.00'), findsOneWidget);
      expect(find.textContaining('Due'), findsNothing);
    });
  });

  group('WriteOffFinanceRow', () {
    testWidgets('renders nothing without a write-off', (tester) async {
      await _pump(tester, WriteOffFinanceRow(booking: _booking()));

      expect(find.text('Written off'), findsNothing);
    });

    testWidgets('shows the amount, date, who and note', (tester) async {
      await _pump(
        tester,
        WriteOffFinanceRow(
          booking: _booking(
            amountDue: '0.00',
            isPaid: true,
            writeOff: const BalanceWriteOff(
              amount: '50.00',
              at: '2026-11-12T15:00:00Z',
              by: 'Eddie',
              note: 'Short on the final check',
            ),
          ),
        ),
      );

      expect(find.text('Written off'), findsOneWidget);
      expect(find.text('−\$50.00'), findsOneWidget);
      expect(find.text('Nov 12, 2026 by Eddie · Short on the final check'), findsOneWidget);
    });
  });

  group('BalanceWriteOff.tryFromJson', () {
    test('parses the backend payload', () {
      final w = BalanceWriteOff.tryFromJson({
        'amount': '50.00',
        'at': '2026-11-12T15:00:00Z',
        'by': 'Eddie',
        'note': '  ',
      })!;

      expect(w.amountValue, 50);
      expect(w.displayAmount, r'$50.00');
      expect(w.note, isNull);
    });

    test('treats null or malformed payloads as no write-off', () {
      expect(BalanceWriteOff.tryFromJson(null), isNull);
      expect(BalanceWriteOff.tryFromJson({'at': '2026-11-12'}), isNull);
    });

    test('BookingDetail reads write_off', () {
      final detail = BookingDetail.fromJson({
        'id': 1,
        'name': 'Test',
        'is_paid': true,
        'amount_due': '0.00',
        'write_off': {'amount': '50.00', 'at': null, 'by': null, 'note': null},
      });
      expect(detail.writeOff?.amount, '50.00');
      expect(BookingDetail.fromJson({'id': 1, 'name': 'Test'}).writeOff, isNull);
    });
  });

  group('PaymentDueState.tryFromJson', () {
    test('parses the backend payload', () {
      final state = PaymentDueState.tryFromJson({
        'event_date': '2027-03-06',
        'merged': false,
        'deposit': {'owed': '250.00', 'due_date': '2026-10-12', 'status': 'overdue', 'overdue_since': '2026-10-12'},
        'balance': {'owed': '750.00', 'due_date': '2027-02-27', 'status': 'upcoming', 'overdue_since': null},
      })!;

      expect(state.deposit.isOverdue, isTrue);
      expect(state.deposit.owedAmount, 250);
      expect(state.balance.dueDate, '2027-02-27');
    });

    test('treats null or malformed payloads as no state', () {
      expect(PaymentDueState.tryFromJson(null), isNull);
      expect(PaymentDueState.tryFromJson({'deposit': 'nope'}), isNull);
    });
  });
}
