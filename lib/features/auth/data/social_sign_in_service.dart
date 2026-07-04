enum SocialProvider { google, apple, facebook }

extension SocialProviderLabel on SocialProvider {
  String get label => switch (this) {
        SocialProvider.google => 'Google',
        SocialProvider.apple => 'Apple',
        SocialProvider.facebook => 'Facebook',
      };
}

class SocialCredential {
  const SocialCredential({required this.provider, required this.token});

  final SocialProvider provider;

  /// Google/Apple: OIDC id_token. Facebook: access token.
  final String token;
}

/// Wraps the native provider SDKs so the auth notifier can be unit-tested
/// with a fake. Implementations return null when the user cancels the
/// native sheet and throw on real failures.
abstract class SocialSignInService {
  Future<SocialCredential?> signIn(SocialProvider provider);
}
