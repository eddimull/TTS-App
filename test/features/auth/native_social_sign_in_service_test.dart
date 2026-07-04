import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/native_social_sign_in_service.dart';
import 'package:tts_bandmate/features/auth/data/social_sign_in_service.dart';

void main() {
  test(
      'signIn(google) throws StateError when GOOGLE_SERVER_CLIENT_ID is unset',
      () {
    // AppConfig.googleServerClientId defaults to '' when the dart-define
    // isn't provided (as in this host test run), so the empty-check guard
    // added in _google() should fire before any GoogleSignIn plugin call.
    final service = NativeSocialSignInService();

    expect(
      () => service.signIn(SocialProvider.google),
      throwsA(isA<StateError>()),
    );
  });
}
