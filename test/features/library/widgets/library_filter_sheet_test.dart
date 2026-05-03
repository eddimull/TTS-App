import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/library/providers/library_filter_provider.dart';
import 'package:tts_bandmate/features/library/widgets/library_filter_sheet.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com', avatarUrl: null);

const _bandA = BandSummary(id: 1, name: 'Band A', isOwner: true);
const _bandB = BandSummary(id: 2, name: 'Band B', isOwner: false);
const _personal = BandSummary(
  id: 3,
  name: "Eddie's Band",
  isOwner: true,
  isPersonal: true,
);

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._bands);
  final List<BandSummary> _bands;
  @override
  Future<AuthState> build() async =>
      AuthAuthenticated(user: _user, bands: _bands);
}

Widget _harness({required List<BandSummary> bands}) => ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _StubAuthNotifier(bands)),
      ],
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: LibraryFilterSheet(bands: bands),
        ),
      ),
    );

void main() {
  testWidgets('renders one cell per provided band', (tester) async {
    await tester.pumpWidget(_harness(bands: const [_bandA, _bandB]));
    await tester.pump();
    expect(find.text('Band A'), findsOneWidget);
    expect(find.text('Band B'), findsOneWidget);
  });

  testWidgets('personal band renders with "Personal" label', (tester) async {
    await tester.pumpWidget(_harness(bands: const [_bandA, _personal]));
    await tester.pump();
    expect(find.text('Personal'), findsOneWidget);
    // Real band still shows its real name.
    expect(find.text('Band A'), findsOneWidget);
  });

  testWidgets('tapping a band toggles it in libraryFilterProvider',
      (tester) async {
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier(const [_bandA, _bandB])),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: CupertinoPageScaffold(
          child: LibraryFilterSheet(bands: [_bandA, _bandB]),
        ),
      ),
    ));
    await tester.pump();

    expect(container.read(libraryFilterProvider).hiddenBandIds, isEmpty);

    await tester.tap(find.text('Band A'));
    await tester.pump();

    expect(container.read(libraryFilterProvider).hiddenBandIds, {1});
  });

  testWidgets('"Clear All" only visible when isActive', (tester) async {
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier(const [_bandA])),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: CupertinoPageScaffold(
          child: LibraryFilterSheet(bands: [_bandA]),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Clear All'), findsNothing);

    container.read(libraryFilterProvider.notifier).toggleBand(1);
    await tester.pump();

    expect(find.text('Clear All'), findsOneWidget);
  });
}
