class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://localhost:8710',
  );
  static const String pusherKey = String.fromEnvironment(
    'PUSHER_APP_KEY',
    defaultValue: '',
  );
  static const String pusherCluster = String.fromEnvironment(
    'PUSHER_APP_CLUSTER',
    defaultValue: 'mt1',
  );

  static const String googlePlacesApiKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
    defaultValue: '',
  );

  /// Google OAuth *web* client ID, passed to google_sign_in as serverClientId
  /// so the returned idToken's `aud` is the web client the backend whitelists.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  /// Public web host that serves invite links. The QR/share flow encodes
  /// `$inviteBaseUrl/invite/<key>`; the OS routes that to the app (App Links /
  /// Universal Links) when installed, else to the website.
  static const String inviteBaseUrl = String.fromEnvironment(
    'INVITE_BASE_URL',
    defaultValue: 'https://tts.band',
  );

  /// Facebook login requires Meta business verification, which we don't have
  /// yet. Off by default; flip via --dart-define=FACEBOOK_LOGIN_ENABLED=true
  /// once the Meta app has Advanced Access.
  static const bool facebookLoginEnabled = bool.fromEnvironment(
    'FACEBOOK_LOGIN_ENABLED',
  );
}
