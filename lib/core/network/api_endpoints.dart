class ApiEndpoints {
  ApiEndpoints._();

  static const String mobileToken = '/api/mobile/auth/token';
  static const String mobileMe = '/api/mobile/auth/me';
  static const String mobileMeBookings = '/api/mobile/me/bookings';
  static const String mobileLogout = '/api/mobile/auth/token';

  static const String mobileDashboard = '/api/mobile/dashboard';
  static String mobileBandEvents(int bandId) => '/api/mobile/bands/$bandId/events';
  static String mobileEventDetail(String key) => '/api/mobile/events/$key';
  static String mobileUpdateEvent(String key) => '/api/mobile/events/$key';
  static String mobileEventAttachments(String key) => '/api/mobile/events/$key/attachments';
  static String mobileDeleteEventAttachment(String key, int id) =>
      '/api/mobile/events/$key/attachments/$id';

  static String mobileBandBookings(int bandId) =>
      '/api/mobile/bands/$bandId/bookings';
  static String mobileBookingDetail(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId';
  static String mobileBookingById(int bandId, int id) =>
      '/api/mobile/bands/$bandId/bookings/$id';
  static String mobileCancelBooking(int bandId, int id) =>
      '/api/mobile/bands/$bandId/bookings/$id/cancel';

  /// POST: create a new event under a booking.
  static String mobileBookingEvents(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/events';

  /// PUT / DELETE: update or remove an existing event under a booking.
  static String mobileBookingEvent(int bandId, int bookingId, int eventId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/events/$eventId';
  static String mobileBandContacts(int bandId) =>
      '/api/mobile/bands/$bandId/contacts';
  static String mobileBookingContacts(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/contacts';
  static String mobileBookingContact(int bandId, int bookingId, int bcId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/contacts/$bcId';
  static String mobileBookingPayments(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/payments';
  static String mobileBookingPayment(int bandId, int bookingId, int paymentId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/payments/$paymentId';
  static String mobileBookingContract(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/contract';
  static String mobileBookingContractUpload(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/contract/upload';
  static String mobileBookingContractSend(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/contract/send';
  static String mobileBookingContractTerms(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/contract/terms';
  static String mobileBookingContractView(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/contract/view';
  static String mobileBookingContractViewUrl(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/contract/view-url';
  static String mobileBookingContractDownload(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/contract/download';
  static String mobileContractHistory(String envelopeId) =>
      '/api/mobile/contracts/$envelopeId/history';
  static String mobileBookingHistory(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/history';
  static const String mobileEventTypes = '/api/mobile/event-types';
  static String mobileBandRehearsalSchedules(int bandId) =>
      '/api/mobile/bands/$bandId/rehearsal-schedules';
  static String mobileRehearsalDetail(int rehearsalId) =>
      '/api/mobile/rehearsals/$rehearsalId';
  static String mobileRehearsalByKey(String key) =>
      '/api/mobile/rehearsals/by-key/$key';
  static String mobileRehearsalUpdateNotes(int rehearsalId) =>
      '/api/mobile/rehearsals/$rehearsalId/notes';

  static const String mobileSearch = '/api/mobile/search';

  static String mobileBandSongs(int bandId) => '/api/mobile/bands/$bandId/songs';
  static const String mobileChartsAll = '/api/mobile/charts';
  static String mobileBandCharts(int bandId) => '/api/mobile/bands/$bandId/charts';
  static String mobileBandChart(int bandId, int chartId) =>
      '/api/mobile/bands/$bandId/charts/$chartId';
  static String mobileBandChartUploads(int bandId, int chartId) =>
      '/api/mobile/bands/$bandId/charts/$chartId/uploads';
  static String mobileBandChartUpload(int bandId, int chartId, int uploadId) =>
      '/api/mobile/bands/$bandId/charts/$chartId/uploads/$uploadId';
  static String mobileBandChartUploadDownload(int bandId, int chartId, int uploadId) =>
      '/api/mobile/bands/$bandId/charts/$chartId/uploads/$uploadId/download';

  static String mobileBandFinances(int bandId) =>
      '/api/mobile/bands/$bandId/finances';
  static String mobileBandFinancesUnpaid(int bandId) =>
      '/api/mobile/bands/$bandId/finances/unpaid';
  static String mobileBandFinancesPaid(int bandId) =>
      '/api/mobile/bands/$bandId/finances/paid';

  static String mobileEventSubs(String key) =>
      '/api/mobile/events/$key/subs';
  static String mobileEventMemberSub(String key, int memberId) =>
      '/api/mobile/events/$key/members/$memberId/sub';

  // Onboarding
  static const String mobileRegister = '/api/mobile/auth/register';
  static const String mobileCreateBand = '/api/mobile/bands';
  static const String mobileBandsSolo = '/api/mobile/bands/solo';
  static const String mobileBandsJoin = '/api/mobile/bands/join';
  static String mobileBandInvite(int bandId) => '/api/mobile/bands/$bandId/invite';
  static String mobileBandInviteQr(int bandId) => '/api/mobile/bands/$bandId/invite-qr';

  // Band Settings
  static String mobileBandDetail(int bandId) => '/api/mobile/bands/$bandId';
  static String mobileBandLogo(int bandId) => '/api/mobile/bands/$bandId/logo';
  static String mobileBandMembers(int bandId) => '/api/mobile/bands/$bandId/members';
  static String mobileBandMember(int bandId, int userId) =>
      '/api/mobile/bands/$bandId/members/$userId';
  static String mobileBandMemberPermissions(int bandId, int userId) =>
      '/api/mobile/bands/$bandId/members/$userId/permissions';
  static String mobileBandInvitations(int bandId) =>
      '/api/mobile/bands/$bandId/invitations';
  static String mobileBandInvitation(int bandId, int invitationId) =>
      '/api/mobile/bands/$bandId/invitations/$invitationId';
}
