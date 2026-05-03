import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_status.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_filter_provider.dart';
import 'package:tts_bandmate/features/bookings/widgets/bookings_filter_sheet.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com', avatarUrl: null);
const _bandA = BandSummary(id: 1, name: 'Band A', isOwner: true);
const _bandB = BandSummary(id: 2, name: 'Band B', isOwner: false);

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._bands);
  final List<BandSummary> _bands;
  @override
  Future<AuthState> build() async =>
      AuthAuthenticated(user: _user, bands: _bands);
}

Widget _harness(ProviderContainer container, List<BandSummary> bands) =>
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: BookingsFilterSheet(bands: bands),
        ),
      ),
    );

ProviderContainer _container(List<BandSummary> bands) {
  final c = ProviderContainer(overrides: [
    authProvider.overrideWith(() => _StubAuthNotifier(bands)),
  ]);
  return c;
}

void main() {
  testWidgets('renders all four status pills and one cell per band',
      (tester) async {
    final container = _container(const [_bandA, _bandB]);
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container, const [_bandA, _bandB]));
    await tester.pump();

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Band A'), findsOneWidget);
    expect(find.text('Band B'), findsOneWidget);
  });

  testWidgets('tapping a status pill updates the provider', (tester) async {
    final container = _container(const [_bandA]);
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container, const [_bandA]));
    await tester.pump();

    expect(container.read(bookingsFilterProvider).status, BookingStatus.all);

    await tester.tap(find.text('Confirmed'));
    await tester.pump();

    expect(container.read(bookingsFilterProvider).status,
        BookingStatus.confirmed);
  });

  testWidgets('tapping a band toggles it in bookingsFilterProvider',
      (tester) async {
    final container = _container(const [_bandA, _bandB]);
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container, const [_bandA, _bandB]));
    await tester.pump();

    expect(container.read(bookingsFilterProvider).hiddenBandIds, isEmpty);

    await tester.tap(find.text('Band A'));
    await tester.pump();

    expect(container.read(bookingsFilterProvider).hiddenBandIds, {1});
  });

  testWidgets('"Clear All" only visible when isActive', (tester) async {
    final container = _container(const [_bandA]);
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container, const [_bandA]));
    await tester.pump();

    expect(find.text('Clear All'), findsNothing);

    container.read(bookingsFilterProvider.notifier).toggleBand(1);
    await tester.pump();

    expect(find.text('Clear All'), findsOneWidget);
  });

  testWidgets('"Clear All" tap resets state', (tester) async {
    final container = _container(const [_bandA]);
    addTearDown(container.dispose);
    container.read(bookingsFilterProvider.notifier)
        .setStatus(BookingStatus.pending);
    container.read(bookingsFilterProvider.notifier).toggleBand(1);

    await tester.pumpWidget(_harness(container, const [_bandA]));
    await tester.pump();

    await tester.tap(find.text('Clear All'));
    await tester.pump();

    final s = container.read(bookingsFilterProvider);
    expect(s.status, BookingStatus.all);
    expect(s.hiddenBandIds, isEmpty);
  });
}
