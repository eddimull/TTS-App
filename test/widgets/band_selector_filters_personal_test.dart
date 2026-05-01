import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/auth/screens/band_selector_screen.dart';

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override
  Future<AuthState> build() async => _fixed;
}

void main() {
  testWidgets('hides personal band from the band-selector list', (tester) async {
    const authState = AuthAuthenticated(
      user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
      bands: [
        BandSummary(id: 10, name: 'The Real Band', isOwner: true),
        BandSummary(id: 11, name: 'Side Project', isOwner: false),
        BandSummary(id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [authProvider.overrideWith(() => _FixedAuthNotifier(authState))],
      child: const CupertinoApp(home: BandSelectorScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('The Real Band'), findsOneWidget);
    expect(find.text('Side Project'), findsOneWidget);
    expect(find.text("Eddie's Band"), findsNothing,
        reason: 'Personal band must be hidden from the selector');
  });
}
