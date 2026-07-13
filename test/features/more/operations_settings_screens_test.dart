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

void main() {
  testWidgets('Operations lists run-the-band rows; Personnel owner-gated',
      (tester) async {
    await tester.pumpWidget(_wrap(const OperationsScreen(), owner: true));
    await tester.pumpAndSettle();
    for (final label in [
      'Bookings',
      'Finances',
      'Rehearsals',
      'Personnel',
      'Media'
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Messages'), findsNothing);

    await tester.pumpWidget(_wrap(const OperationsScreen(), owner: false));
    await tester.pumpAndSettle();
    expect(find.text('Personnel'), findsNothing);
    expect(find.text('Bookings'), findsOneWidget);
  });

  testWidgets('Settings lists config rows; gating for owner and band count',
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

    await tester
        .pumpWidget(_wrap(const SettingsScreen(), owner: false, bands: 1));
    await tester.pumpAndSettle();
    expect(find.text('Switch Band'), findsNothing);
    expect(find.text('Band Settings'), findsNothing);
    expect(find.text('My Stats'), findsOneWidget);
  });
}
