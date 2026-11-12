import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/widgets/write_off_sheet.dart';

class _FakeRepo extends BookingsRepository {
  _FakeRepo() : super(Dio());

  int calls = 0;
  bool? notifyClient;
  String? note;

  @override
  Future<Map<String, dynamic>> writeOffBalance(
    int bandId,
    int bookingId, {
    required bool notifyClient,
    String? note,
  }) async {
    calls++;
    this.notifyClient = notifyClient;
    this.note = note;
    return {'amount_due': '0.00', 'is_paid': true};
  }
}

const _booking = BookingDetail(
  id: 7,
  name: 'Gala',
  startDate: '2026-01-10',
  endDate: '2026-01-10',
  eventCount: 1,
  isMultiEvent: false,
  isPaid: false,
  contacts: [],
  events: [],
  price: '11250.00',
  amountPaid: '11200.00',
  amountDue: '50.00',
);

Future<_FakeRepo> _pump(WidgetTester tester, {VoidCallback? onSaved}) async {
  final repo = _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bookingsRepositoryProvider.overrideWithValue(repo)],
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: WriteOffSheet(
              bandId: 1,
              booking: _booking,
              onSaved: onSaved ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  return repo;
}

void main() {
  testWidgets('states the amount and keeps amount paid', (tester) async {
    await _pump(tester);

    expect(find.text(r'Write Off $50.00'), findsOneWidget);
    expect(find.textContaining(r'Amount paid stays $11,200.00'), findsOneWidget);
  });

  testWidgets('is silent toward the client by default', (tester) async {
    var saved = false;
    final repo = await _pump(tester, onSaved: () => saved = true);

    expect(tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value, isFalse);
    await tester.enterText(find.byType(CupertinoTextField), 'Short on final check');
    await tester.tap(find.text('Write Off'));
    await tester.pump();

    expect(repo.calls, 1);
    expect(repo.notifyClient, isFalse);
    expect(repo.note, 'Short on final check');
    expect(saved, isTrue);
  });

  testWidgets('notifies the client when switched on', (tester) async {
    final repo = await _pump(tester);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pump();
    expect(find.textContaining('Emails the contacts'), findsOneWidget);

    await tester.tap(find.text('Write Off'));
    await tester.pump();

    expect(repo.notifyClient, isTrue);
  });
}
