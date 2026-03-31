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
}
