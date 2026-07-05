import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/providers/contract_editor_provider.dart';
import 'package:tts_bandmate/features/bookings/widgets/contract/contract_editor.dart';

// The contract editor's Send button is disabled until the booking has
// contacts. The empty-contacts warning must offer a direct route to the
// contacts screen instead of leaving the user to find it by memory.

BookingDetail _detail() => const BookingDetail(
      id: 1,
      name: 'Test Booking',
      startDate: '2026-06-01',
      endDate: '2026-06-01',
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      status: 'draft',
      contractOption: 'default',
      contacts: [],
      events: [],
      band: BandSummary(id: 1, name: 'Band', isOwner: true),
    );

class _ReadyEditor extends ContractEditorNotifier {
  _ReadyEditor() : super((bandId: 1, bookingId: 1));

  @override
  Future<ContractEditorState> build() async {
    return const ContractEditorState(terms: [], unsavedChanges: false);
  }

  @override
  Future<void> save({bool force = false}) async {}
}

void main() {
  testWidgets(
      'empty-contacts warning links straight to the contacts screen',
      (tester) async {
    final detail = _detail();
    const key = (bandId: 1, bookingId: 1);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => ContractEditor(booking: detail),
        ),
        GoRoute(
          path: '/bookings/:bandId/:bookingId/contacts',
          builder: (_, __) => const CupertinoPageScaffold(
            child: Center(child: Text('CONTACTS SCREEN')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contractEditorProvider(key).overrideWith(() => _ReadyEditor()),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Warning present, with an actionable button. It sits at the bottom of
    // the editor's CustomScrollView, so scroll until it is built.
    await tester.scrollUntilVisible(
      find.textContaining('Add contacts to this booking'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
        find.textContaining('Add contacts to this booking'), findsOneWidget);

    await tester.ensureVisible(find.text('Add contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add contacts'));
    await tester.pumpAndSettle();

    expect(find.text('CONTACTS SCREEN'), findsOneWidget);
  });
}
