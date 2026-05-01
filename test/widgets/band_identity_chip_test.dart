import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/shared/widgets/band_identity_chip.dart';

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;

  @override
  Future<AuthState> build() async => _fixed;
}

Widget _wrap(Widget child, {required AuthState auth}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(() => _FixedAuthNotifier(auth)),
    ],
    child: CupertinoApp(home: CupertinoPageScaffold(child: child)),
  );
}

void main() {
  testWidgets('renders band name for non-personal band', (tester) async {
    const band = BandSummary(
      id: 10, name: 'The Rocking Eds', isOwner: true, isPersonal: false,
    );
    await tester.pumpWidget(_wrap(
      const BandIdentityChip(band: band),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [band],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('The Rocking Eds'), findsOneWidget);
    expect(find.text('Personal'), findsNothing);
  });

  testWidgets('renders "Personal" label for personal band', (tester) async {
    const band = BandSummary(
      id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true,
    );
    await tester.pumpWidget(_wrap(
      const BandIdentityChip(band: band),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [band],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text("Eddie's Band"), findsNothing);
  });

  testWidgets('renders band initials when no logoUrl', (tester) async {
    const band = BandSummary(
      id: 10, name: 'Acme', isOwner: true, isPersonal: false,
    );
    await tester.pumpWidget(_wrap(
      const BandIdentityChip(band: band),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [band],
      ),
    ));
    await tester.pumpAndSettle();
    // First letter of band name should appear in the avatar fallback.
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('renders user initials for personal band when no avatarUrl', (tester) async {
    const band = BandSummary(
      id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true,
    );
    await tester.pumpWidget(_wrap(
      const BandIdentityChip(band: band),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie Mullins', email: 'e@e.com'),
        bands: [band],
      ),
    ));
    await tester.pumpAndSettle();
    // First letter of user's name in the fallback (when avatarUrl is null).
    expect(find.text('E'), findsOneWidget);
  });

  testWidgets('falls back to "?" when name is empty', (tester) async {
    const band = BandSummary(
      id: 10, name: '', isOwner: true, isPersonal: false,
    );
    await tester.pumpWidget(_wrap(
      const BandIdentityChip(band: band),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: '', email: 'e@e.com'),
        bands: [band],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('?'), findsOneWidget);
  });
}
