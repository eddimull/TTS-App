import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_cache_storage.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/data/models/contract_term.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/bookings/providers/contract_editor_provider.dart';
import 'package:tts_bandmate/features/bookings/widgets/contract/contract_editor.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

// Reproduction for the "auto-refresh messes up the workflow" report on the
// contract editor's Buyer name override (signer) field:
//
//  1. Every keystroke rebuilds the editor, which constructs a brand-new
//     TextEditingController with the selection forced to the end of the text,
//     so typing in the middle of the field throws the cursor to the end.
//  2. The 500ms debounced autosave invalidates bookingDetailProvider, which
//     the editor notifier's build() depends on. The editor (and the hosting
//     BookingContractScreen) flash back to a loading spinner and re-seed from
//     the server payload, dropping any keystrokes typed while the save was in
//     flight.

const _key = (bandId: 7, bookingId: 42);

BookingDetail _detail() => const BookingDetail(
      id: 42,
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
      band: BandSummary(id: 7, name: 'Band', isOwner: true),
    );

// ── Widget-level: cursor jump ────────────────────────────────────────────────

class _ReadyEditor extends ContractEditorNotifier {
  _ReadyEditor() : super(_key);

  @override
  Future<ContractEditorState> build() async => const ContractEditorState(
        terms: [],
        unsavedChanges: false,
        buyerNameOverride: 'Acme Corp',
      );

  // Keep the widget test free of network: edits still update state (and
  // therefore rebuild the editor) but never hit a repository.
  @override
  Future<void> save({bool force = false}) async {}
}

// ── Provider-level: autosave refresh ─────────────────────────────────────────

Map<String, dynamic> _bookingJson(String? override) => {
      'booking': {
        'id': 42,
        'name': 'Test Booking',
        'date': '2026-06-01',
        'status': 'draft',
        'contacts': <Map<String, dynamic>>[],
        'events': <Map<String, dynamic>>[],
        'contract': {
          'id': 1,
          'custom_terms': <Map<String, dynamic>>[],
          'buyer_name_override': override,
        },
      },
    };

/// Minimal repository: `getBookingDetailRaw` serves whatever the "server"
/// currently holds; `saveContractTerms` stores the override and waits on
/// [saveGate] so the test can inject a keystroke while the save is in flight.
class _ServerRepo implements BookingsRepository {
  String? stored;
  int fetchCount = 0;
  Completer<void> saveGate = Completer<void>();

  @override
  Future<({BookingDetail parsed, Map<String, dynamic> raw})>
      getBookingDetailRaw(int bandId, int bookingId) async {
    fetchCount++;
    final data = _bookingJson(stored);
    return (parsed: BookingsRepository.parseBookingDetail(data), raw: data);
  }

  @override
  Future<BookingDetail> saveContractTerms(
    int bandId,
    int bookingId,
    List<ContractTerm> terms, {
    String? buyerNameOverride,
  }) async {
    stored = buyerNameOverride;
    await saveGate.future;
    return BookingsRepository.parseBookingDetail(_bookingJson(stored));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 7;
}

class _NoopDashboardNotifier extends DashboardNotifier {
  @override
  Future<DashboardState> build() async => DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: DateTime(2026),
        loadedTo: DateTime(2026, 4, 1),
      );

  @override
  Future<void> refresh() async {}
}

class _NoopBookingsCache implements BookingsCacheStorage {
  @override
  void clear() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'typing in the middle of the Buyer name override keeps the cursor in place',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contractEditorProvider(_key).overrideWith(() => _ReadyEditor()),
        ],
        child: CupertinoApp(home: ContractEditor(booking: _detail())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The override field sits below the fixed header in a lazy sliver list;
    // scroll until it is built. Terms are empty, so it is the only text field.
    await tester.scrollUntilVisible(
      find.text('Buyer name override (optional)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    final field = find.byType(CupertinoTextField);
    expect(field, findsOneWidget);
    expect(tester.widget<CupertinoTextField>(field).controller!.text,
        'Acme Corp');

    // Focus the field, then act like the IME inserting an "X" after "Acme"
    // (cursor sitting at offset 4 → 5 after the insert).
    await tester.showKeyboard(field);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'AcmeX Corp',
      selection: TextSelection.collapsed(offset: 5),
    ));
    await tester.pump();

    final controller = tester.widget<CupertinoTextField>(field).controller!;
    expect(controller.text, 'AcmeX Corp');
    // The rebuild replaced the controller and forced the caret to the end
    // (offset 10). The user's caret should still be right after the "X".
    expect(controller.selection.baseOffset, 5);

    // Drain the editor's 500ms debounce timer so the test ends cleanly.
    await tester.pump(const Duration(milliseconds: 600));
  });

  test(
      'debounced autosave does not reload the editor or drop in-flight keystrokes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final repo = _ServerRepo()..stored = 'Ac';

    final container = ProviderContainer(overrides: [
      apiCacheStorageProvider.overrideWithValue(storage),
      bookingsCacheStorageProvider.overrideWithValue(_NoopBookingsCache()),
      dashboardProvider.overrideWith(_NoopDashboardNotifier.new),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWithValue(const AsyncValue.data(true)),
      bookingsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await container.read(selectedBandProvider.future);

    // Keep the autoDispose editor alive and record every state it emits.
    final seen = <AsyncValue<ContractEditorState>>[];
    final sub = container.listen(
      contractEditorProvider(_key),
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
    addTearDown(sub.close);
    // Mirror the hosting BookingContractScreen, which watches the detail.
    final detailSeen = <AsyncValue<BookingDetail>>[];
    final detailSub = container.listen(
      bookingDetailProvider(_key),
      (_, next) => detailSeen.add(next),
    );
    addTearDown(detailSub.close);
    await container.read(contractEditorProvider(_key).future);
    await _flush();
    expect(repo.fetchCount, 1);
    seen.clear();
    detailSeen.clear();

    final notifier = container.read(contractEditorProvider(_key).notifier);

    // Keystroke 1 lands, debounce fires → save starts (held open by the gate).
    notifier.updateBuyerNameOverride('Acm');
    final saving = notifier.save();
    await _flush();
    expect(repo.stored, 'Acm');

    // Keystroke 2 lands while the save is still in flight.
    notifier.updateBuyerNameOverride('Acme');
    expect(container.read(contractEditorProvider(_key)).value?.buyerNameOverride,
        'Acme');

    // Server responds; save() finishes and invalidates bookingDetailProvider.
    repo.saveGate.complete();
    await saving;
    await _flush();
    await container.read(contractEditorProvider(_key).future);
    await _flush();

    // The keystroke typed during the save must survive.
    expect(
      container.read(contractEditorProvider(_key)).value?.buyerNameOverride,
      'Acme',
      reason: 'keystroke typed during the in-flight save was dropped',
    );
    // Autosave must be a background write — it should not tear the editor
    // down into a loading state (which the hosting screen renders as a
    // full-screen spinner, dismissing the keyboard).
    expect(seen.any((s) => s.isLoading), isFalse,
        reason: 'editor re-entered loading after autosave: $seen');
    // The booking detail may refresh in the background so the next visit
    // sees the saved terms, but it must never pass through loading (the
    // hosting screen renders that as a full-screen spinner).
    expect(detailSeen.any((s) => s.isLoading), isFalse,
        reason: 'booking detail re-entered loading after autosave: $detailSeen');
    expect(repo.fetchCount, 2,
        reason: 'autosave should refresh the detail cache in the background');
    expect(
      container.read(bookingDetailProvider(_key)).value?.contract?.buyerNameOverride,
      'Acm',
    );
  });
}
