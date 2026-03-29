class ApiEndpoints {
  ApiEndpoints._();

  static const String mobileToken = '/api/mobile/auth/token';
  static const String mobileMe = '/api/mobile/auth/me';
  static const String mobileLogout = '/api/mobile/auth/token';

  static const String mobileDashboard = '/api/mobile/dashboard';
  static String mobileBandEvents(int bandId) => '/api/mobile/bands/$bandId/events';
  static String mobileEventDetail(String key) => '/api/mobile/events/$key';

  static String mobileBandBookings(int bandId) =>
      '/api/mobile/bands/$bandId/bookings';
  static String mobileBookingDetail(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId';
  static String mobileBandRehearsalSchedules(int bandId) =>
      '/api/mobile/bands/$bandId/rehearsal-schedules';
  static String mobileRehearsalDetail(int rehearsalId) =>
      '/api/mobile/rehearsals/$rehearsalId';
  static String mobileRehearsalByKey(String key) =>
      '/api/mobile/rehearsals/by-key/$key';
  static String mobileRehearsalUpdateNotes(int rehearsalId) =>
      '/api/mobile/rehearsals/$rehearsalId/notes';
}
