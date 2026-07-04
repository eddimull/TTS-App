import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

import '../data/social_sign_in_service.dart';
import '../providers/auth_provider.dart';
import '../providers/social_sign_in_provider.dart';

/// "or continue with" divider + provider buttons. Native mobile only:
/// renders nothing on web/desktop. Apple shows only on iOS (App Store
/// policy requires it there; it isn't configured elsewhere).
class SocialLoginButtons extends ConsumerStatefulWidget {
  const SocialLoginButtons({super.key});

  @override
  ConsumerState<SocialLoginButtons> createState() =>
      _SocialLoginButtonsState();
}

class _SocialLoginButtonsState extends ConsumerState<SocialLoginButtons> {
  SocialProvider? _busy;
  String? _error;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<void> _signIn(SocialProvider provider) async {
    setState(() {
      _busy = provider;
      _error = null;
    });

    final before = ref.read(authProvider).value;
    await ref.read(authProvider.notifier).socialLogin(provider);
    if (!mounted) return;

    // socialLogin leaves state as the exact same instance on user-cancel
    // (`if (credential == null) return;`), so identical() cleanly
    // distinguishes "this attempt produced a new state" from "nothing
    // happened" — otherwise a cancel after a prior failure would
    // re-display that prior attempt's stale error.
    final after = ref.read(authProvider).value;
    setState(() {
      _busy = null;
      if (!identical(before, after) &&
          after is AuthUnauthenticated &&
          after.errorMessage != null) {
        _error = after.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();

    final facebookLoginEnabled = ref.watch(facebookLoginEnabledProvider);

    final providers = [
      SocialProvider.google,
      if (defaultTargetPlatform == TargetPlatform.iOS) SocialProvider.apple,
      if (facebookLoginEnabled) SocialProvider.facebook,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
              child: Container(
                  height: 0.5,
                  color: CupertinoColors.separator.resolveFrom(context))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('or continue with',
                style: TextStyle(fontSize: 13, color: context.secondaryText)),
          ),
          Expanded(
              child: Container(
                  height: 0.5,
                  color: CupertinoColors.separator.resolveFrom(context))),
        ]),
        const SizedBox(height: 16),
        for (final provider in providers) ...[
          _SocialButton(
            provider: provider,
            busy: _busy == provider,
            enabled: _busy == null,
            onPressed: () => _signIn(provider),
          ),
          const SizedBox(height: 10),
        ],
        if (_error != null) ...[
          const SizedBox(height: 2),
          Text(
            _error!,
            style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.systemRed.resolveFrom(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.provider,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final SocialProvider provider;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (provider) {
      SocialProvider.google => (
          CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          CupertinoColors.label.resolveFrom(context),
          CupertinoIcons.globe,
        ),
      SocialProvider.apple => (
          CupertinoColors.label.resolveFrom(context),
          CupertinoColors.systemBackground.resolveFrom(context),
          CupertinoIcons.device_phone_portrait,
        ),
      SocialProvider.facebook => (
          const Color(0xFF1877F2),
          CupertinoColors.white,
          CupertinoIcons.f_cursive,
        ),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Continue with ${provider.label}',
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 12),
        color: background,
        borderRadius: BorderRadius.circular(10),
        onPressed: enabled ? onPressed : null,
        child: busy
            ? CupertinoActivityIndicator(color: foreground)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: 8),
                  Text('Continue with ${provider.label}',
                      style: TextStyle(fontSize: 15, color: foreground)),
                ],
              ),
      ),
    );
  }
}
