import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/config/app_config.dart';
import 'social_sign_in_service.dart';

class NativeSocialSignInService implements SocialSignInService {
  // google_sign_in v7 requires initialize() be called exactly once per app run.
  bool _googleInitialized = false;

  @override
  Future<SocialCredential?> signIn(SocialProvider provider) {
    return switch (provider) {
      SocialProvider.google => _google(),
      SocialProvider.apple => _apple(),
      SocialProvider.facebook => _facebook(),
    };
  }

  Future<SocialCredential?> _google() async {
    try {
      if (!_googleInitialized) {
        if (AppConfig.googleServerClientId.isEmpty) {
          throw StateError(
            'GOOGLE_SERVER_CLIENT_ID dart-define is not set — Google sign-in cannot '
            'return a usable idToken without it.',
          );
        }
        await GoogleSignIn.instance.initialize(
          serverClientId: AppConfig.googleServerClientId,
        );
        _googleInitialized = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        // Successful sign-in without a token = misconfiguration, not a cancel.
        throw StateError('Google sign-in succeeded without an ID token');
      }
      return SocialCredential(provider: SocialProvider.google, token: idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  Future<SocialCredential?> _apple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw StateError('Apple sign-in succeeded without an identity token');
      }
      return SocialCredential(provider: SocialProvider.apple, token: idToken);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }

  Future<SocialCredential?> _facebook() async {
    final result = await FacebookAuth.instance.login(
      permissions: const ['email', 'public_profile'],
    );
    switch (result.status) {
      case LoginStatus.success:
        return SocialCredential(
          provider: SocialProvider.facebook,
          token: result.accessToken!.tokenString,
        );
      case LoginStatus.cancelled:
        return null;
      default:
        throw StateError(result.message ?? 'Facebook sign-in failed');
    }
  }
}
