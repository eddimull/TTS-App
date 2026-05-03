import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/library/data/library_repository.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';
import 'package:tts_bandmate/features/library/providers/library_filter_provider.dart';
import 'package:tts_bandmate/features/library/screens/library_screen.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com', avatarUrl: null);
const _bandA = BandSummary(id: 1, name: 'Band A', isOwner: true);
const _bandB = BandSummary(id: 2, name: 'Band B', isOwner: false);

Chart _chart({required int id, required String title, required BandSummary band}) =>
    Chart(
      id: id,
      bandId: band.id,
      title: title,
      composer: '',
      description: '',
      price: 0,
      isPublic: false,
      uploadsCount: 0,
      uploads: const [],
      band: ChartBand(
        id: band.id,
        name: band.name,
        isPersonal: band.isPersonal,
      ),
    );

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._bands);
  final List<BandSummary> _bands;
  @override
  Future<AuthState> build() async =>
      AuthAuthenticated(user: _user, bands: _bands);
}

class _FakeRepo implements LibraryRepository {
  _FakeRepo(this._charts);
  final List<Chart> _charts;
  @override
  Future<List<Chart>> getAllCharts() async => _charts;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

GoRouter _testRouter() => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
    ]);

Widget _harness({
  required List<BandSummary> bands,
  required List<Chart> charts,
}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier(bands)),
      libraryRepositoryProvider.overrideWithValue(_FakeRepo(charts)),
    ],
    child: CupertinoApp.router(routerConfig: _testRouter()),
  );
}

void main() {
  testWidgets('renders charts from multiple bands sorted alphabetically',
      (tester) async {
    final charts = [
      _chart(id: 1, title: 'Caravan', band: _bandA),
      _chart(id: 2, title: 'Body and Soul', band: _bandB),
      _chart(id: 3, title: 'Autumn Leaves', band: _bandA),
    ];

    await tester.pumpWidget(
      _harness(bands: const [_bandA, _bandB], charts: charts),
    );
    await tester.pumpAndSettle();

    expect(find.text('Autumn Leaves'), findsOneWidget);
    expect(find.text('Body and Soul'), findsOneWidget);
    expect(find.text('Caravan'), findsOneWidget);
  });

  testWidgets('filtering a band hides only that band\'s charts',
      (tester) async {
    final charts = [
      _chart(id: 1, title: 'Mine', band: _bandA),
      _chart(id: 2, title: 'Yours', band: _bandB),
    ];

    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier(const [_bandA, _bandB])),
      libraryRepositoryProvider.overrideWithValue(_FakeRepo(charts)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: CupertinoApp.router(routerConfig: _testRouter()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Yours'), findsOneWidget);

    // Hide Band A.
    container.read(libraryFilterProvider.notifier).toggleBand(_bandA.id);
    await tester.pumpAndSettle();

    expect(find.text('Mine'), findsNothing);
    expect(find.text('Yours'), findsOneWidget);
  });

  testWidgets('all-bands-hidden empty state shows Show all action',
      (tester) async {
    final charts = [_chart(id: 1, title: 'Mine', band: _bandA)];

    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier(const [_bandA])),
      libraryRepositoryProvider.overrideWithValue(_FakeRepo(charts)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: CupertinoApp.router(routerConfig: _testRouter()),
    ));
    await tester.pumpAndSettle();

    container.read(libraryFilterProvider.notifier).toggleBand(_bandA.id);
    await tester.pumpAndSettle();

    expect(find.textContaining('All bands hidden'), findsOneWidget);
    expect(find.text('Show all'), findsOneWidget);

    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();

    expect(container.read(libraryFilterProvider).isActive, false);
    expect(find.text('Mine'), findsOneWidget);
  });
}
