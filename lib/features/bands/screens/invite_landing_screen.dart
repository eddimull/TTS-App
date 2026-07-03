import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/bands_provider.dart';
import '../providers/pending_invite_provider.dart';

/// Landing screen for `/invite/:key`. Reached from a scanned QR / shared link.
///
/// If the user is already authenticated, it joins the band immediately and
/// routes to the dashboard. Otherwise it stashes the key in
/// [pendingInviteKeyProvider] and sends the user to /welcome to sign in; the
/// router listener consumes the key and joins once auth completes.
class InviteLandingScreen extends ConsumerStatefulWidget {
  const InviteLandingScreen({super.key, required this.inviteKey});

  final String inviteKey;

  @override
  ConsumerState<InviteLandingScreen> createState() =>
      _InviteLandingScreenState();
}

class _InviteLandingScreenState extends ConsumerState<InviteLandingScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    // Defer to after first frame so navigation is safe.
    WidgetsBinding.instance.addPostFrameCallback((_) => _handle());
  }

  Future<void> _handle() async {
    final authState = ref.read(authProvider).value;
    final isAuthed = authState is AuthAuthenticated;

    if (!isAuthed) {
      // Stash and let the user authenticate; the router listener finishes join.
      ref.read(pendingInviteKeyProvider.notifier).set(widget.inviteKey);
      if (mounted) context.go('/welcome');
      return;
    }

    try {
      await ref.read(bandsProvider.notifier).joinBand(widget.inviteKey);
      // joinBand → refreshBands → router guard routes to the new band.
      if (mounted) context.go('/dashboard');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'That invite is invalid or expired.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Center(
        child: _error == null
            ? const CupertinoActivityIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    CupertinoButton.filled(
                      onPressed: () => context.go('/dashboard'),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
