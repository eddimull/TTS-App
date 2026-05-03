import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/library/widgets/create_chart_sheet.dart';
import 'package:tts_bandmate/shared/providers/personal_band_provider.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com', avatarUrl: null);
const _bandA = BandSummary(id: 1, name: 'Band A', isOwner: true);
const _bandB = BandSummary(id: 2, name: 'Band B', isOwner: false);
const _personal = BandSummary(
  id: 99,
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

class _StubPersonalBandNotifier extends PersonalBandNotifier {
  _StubPersonalBandNotifier({required this.willSucceed});
  final bool willSucceed;

  @override
  Future<BandSummary> ensureExists() async {
    if (!willSucceed) {
      throw StateError('boom');
    }
    return _personal;
  }
}

Widget _harness({
  required List<BandSummary> bands,
  required void Function(BandSummary) onBandSelected,
  bool personalSucceeds = true,
}) =>
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _StubAuthNotifier(bands)),
        personalBandProvider.overrideWith(
            () => _StubPersonalBandNotifier(willSucceed: personalSucceeds)),
      ],
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: CreateChartSheet(onBandSelected: onBandSelected),
        ),
      ),
    );

void main() {
  testWidgets('multi-band: shows real bands and Personal row', (tester) async {
    await tester.pumpWidget(_harness(
      bands: const [_bandA, _bandB],
      onBandSelected: (_) {},
    ));
    await tester.pump();

    expect(find.text('Band A'), findsOneWidget);
    expect(find.text('Band B'), findsOneWidget);
    expect(find.text('Personal library'), findsOneWidget);
  });

  testWidgets('tapping a band invokes onBandSelected with that band',
      (tester) async {
    BandSummary? picked;
    await tester.pumpWidget(_harness(
      bands: const [_bandA, _bandB],
      onBandSelected: (b) => picked = b,
    ));
    await tester.pump();

    await tester.tap(find.text('Band B'));
    await tester.pump();
    expect(picked?.id, _bandB.id);
  });

  testWidgets('tapping Personal calls ensureExists then onBandSelected',
      (tester) async {
    BandSummary? picked;
    await tester.pumpWidget(_harness(
      bands: const [_bandA],
      onBandSelected: (b) => picked = b,
    ));
    await tester.pump();

    await tester.tap(find.text('Personal library'));
    await tester.pump(); // start ensureExists
    await tester.pump(const Duration(milliseconds: 50)); // resolve

    expect(picked?.id, _personal.id);
    expect(picked?.isPersonal, true);
  });

  testWidgets('personal failure shows error and keeps sheet open',
      (tester) async {
    await tester.pumpWidget(_harness(
      bands: const [_bandA],
      onBandSelected: (_) => fail('should not be called'),
      personalSucceeds: false,
    ));
    await tester.pump();

    await tester.tap(find.text('Personal library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining("Couldn't"), findsOneWidget);
    // Sheet still rendered.
    expect(find.text('Band A'), findsOneWidget);
  });
}
