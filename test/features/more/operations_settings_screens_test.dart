import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/more/screens/operations_screen.dart';
import 'package:tts_bandmate/features/more/screens/settings_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

class _FakeBand extends SelectedBandNotifier {
  _FakeBand(this._id);
  final int? _id;
  @override
  Future<int?> build() async => _id;
}

AuthState _authed({required bool owner, int bands = 2}) => AuthAuthenticated(
      user: const AuthUser(id: 1, name: 'Eddie', email: 'e@x.com'),
      bands: [
        for (var i = 1; i <= bands; i++)
          BandSummary(id: i, name: 'Band $i', isOwner: i == 1 ? owner : false),
      ],
    );

Widget _wrap(Widget child, {required bool owner, int bands = 2}) =>
    ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => _FakeAuth(_authed(owner: owner, bands: bands))),
        selectedBandProvider.overrideWith(() => _FakeBand(1)),
      ],
      child: CupertinoApp(home: child),
    );

// Repo idiom: one scenario per testWidgets, each with its own fresh
// ProviderScope + overrides. Re-pumping a second tree with changed
// overrides inside one test reuses cached provider state, so gating
// changes never take effect.
void main() {
  testWidgets('Operations lists run-the-band rows for an owner',
      (tester) async {
    await tester.pumpWidget(_wrap(const OperationsScreen(), owner: true));
    await tester.pumpAndSettle();
    for (final label in [
      'Bookings',
      'Finances',
      'Rehearsals',
      'Song list',
      'Personnel',
      'Media',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Messages'), findsNothing);
  });

  testWidgets('Operations hides Personnel for a non-owner', (tester) async {
    await tester.pumpWidget(_wrap(const OperationsScreen(), owner: false));
    await tester.pumpAndSettle();
    expect(find.text('Personnel'), findsNothing);
    expect(find.text('Bookings'), findsOneWidget);
  });

  testWidgets('Settings lists config rows for an owner with multiple bands',
      (tester) async {
    await tester.pumpWidget(_wrap(const SettingsScreen(), owner: true));
    await tester.pumpAndSettle();
    for (final label in [
      'Switch Band',
      'Band Settings',
      'My Stats',
      'Add to Calendar',
      'Account',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets(
      'Settings hides Switch Band and Band Settings for single-band non-owner',
      (tester) async {
    await tester
        .pumpWidget(_wrap(const SettingsScreen(), owner: false, bands: 1));
    await tester.pumpAndSettle();
    expect(find.text('Switch Band'), findsNothing);
    expect(find.text('Band Settings'), findsNothing);
    expect(find.text('My Stats'), findsOneWidget);
  });
}
