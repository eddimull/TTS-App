class ApiEndpoints {
  ApiEndpoints._();

  static const String mobileToken = '/api/mobile/auth/token';
  static const String mobileSocial = '/api/mobile/auth/social';
  static const String mobileTokenRefresh = '/api/mobile/token/refresh';
  static const String mobileMe = '/api/mobile/auth/me';
  static const String mobileMeBookings = '/api/mobile/me/bookings';
  static const String mobileStats = '/api/mobile/me/stats';
  static const String mobileCalendarFeed = '/api/mobile/me/calendar-feed';
  static const String mobileCalendarFeedReset =
      '/api/mobile/me/calendar-feed/reset';
  static const String mobileLogout = '/api/mobile/auth/token';

  // Account management. GET returns profile + state/country lists; PATCH
  // updates the profile; DELETE requests email-confirmed account deletion.
  static const String mobileAccount = '/api/mobile/account';

  static const String mobileDashboard = '/api/mobile/dashboard';
  static const String mobileDashboardLoadOlder =
      '/api/mobile/dashboard/load-older';
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
  static String mobileBookingPayout(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/payout';
  static String mobileBookingPayoutAdjustments(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/payout/adjustments';
  static String mobileBookingPayoutAdjustment(int bandId, int bookingId, int adjustmentId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/payout/adjustments/$adjustmentId';
  static String mobileBookingPayoutConfiguration(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/payout/configuration';
  static String mobileEventMemberAttendance(int bandId, int bookingId, int eventId, int memberId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/events/$eventId/members/$memberId/attendance';
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
  static String mobileBookingContractAmend(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/contract/amend';
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
  static String mobileRehearsalSetCancelled(int rehearsalId) =>
      '/api/mobile/rehearsals/$rehearsalId/cancelled';

  static const String mobileSearch = '/api/mobile/search';

  static String mobileBandSongs(int bandId) => '/api/mobile/bands/$bandId/songs';
  static String mobileBandSong(int bandId, int songId) =>
      '/api/mobile/bands/$bandId/songs/$songId';

  /// BPM lookup passthrough (band-independent, like the web /songs/lookup).
  static const String mobileSongsLookup = '/api/mobile/songs/lookup';

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
  static String mobileBandFinancesRevenue(int bandId) =>
      '/api/mobile/bands/$bandId/finances/revenue';
  static String mobileBandFinancesTrends(int bandId) =>
      '/api/mobile/bands/$bandId/finances/trends';

  // Payout flow editor
  static String mobilePayoutFlowConfigs(int bandId) =>
      '/api/mobile/bands/$bandId/payout-flow/configs';
  static String mobilePayoutFlowConfig(int bandId, int configId) =>
      '/api/mobile/bands/$bandId/payout-flow/configs/$configId';
  static String mobilePayoutFlowPreview(int bandId) =>
      '/api/mobile/bands/$bandId/payout-flow/preview';
  static String mobilePayoutFlowTemplates(int bandId) =>
      '/api/mobile/bands/$bandId/payout-flow/templates';

  static String mobileEventSubs(String key) =>
      '/api/mobile/events/$key/subs';
  static String mobileEventMemberSub(String key, int memberId) =>
      '/api/mobile/events/$key/members/$memberId/sub';

  // Attire chips
  static String mobileBandAttireChips(int bandId) =>
      '/api/mobile/bands/$bandId/attire-chips';
  static String mobileBandAttireChip(int bandId, int chipId) =>
      '/api/mobile/bands/$bandId/attire-chips/$chipId';

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

  // Setlist editor (pre-gig)
  static String mobileEventSetlist(String key) =>
      '/api/mobile/events/$key/setlist';
  static String mobileEventSetlistGenerate(String key) =>
      '/api/mobile/events/$key/setlist/generate';
  static String mobileEventSetlistRefine(String key) =>
      '/api/mobile/events/$key/setlist/refine';

  // Setlist prompt templates
  static String mobileBandSetlistPromptTemplates(int bandId) =>
      '/api/mobile/bands/$bandId/setlist-prompt-templates';
  static String mobileBandSetlistPromptTemplate(int bandId, int templateId) =>
      '/api/mobile/bands/$bandId/setlist-prompt-templates/$templateId';

  // Push device registration (Phase 1 notifications). Both register (POST) and
  // deregister (DELETE) use this path; the token travels in the request body.
  static const String mobileDevices = '/api/mobile/devices';

  // Personnel — Roles
  static String mobileBandRoles(int bandId) =>
      '/api/mobile/bands/$bandId/roles';
  static String mobileBandRole(int bandId, int roleId) =>
      '/api/mobile/bands/$bandId/roles/$roleId';
  static String mobileBandRolesReorder(int bandId) =>
      '/api/mobile/bands/$bandId/roles/reorder';

  // Personnel — Rosters
  static String mobileBandRosters(int bandId) =>
      '/api/mobile/bands/$bandId/rosters';
  static String mobileBandRoster(int bandId, int rosterId) =>
      '/api/mobile/bands/$bandId/rosters/$rosterId';
  static String mobileBandRosterSetDefault(int bandId, int rosterId) =>
      '/api/mobile/bands/$bandId/rosters/$rosterId/set-default';
  static String mobileBandRostersInitialize(int bandId) =>
      '/api/mobile/bands/$bandId/rosters/initialize';
  static String mobileBandRosterFutureEventsDiff(int bandId, int rosterId) =>
      '/api/mobile/bands/$bandId/rosters/$rosterId/future-events-diff';
  static String mobileBandRosterReconcileFutureEvents(int bandId, int rosterId) =>
      '/api/mobile/bands/$bandId/rosters/$rosterId/reconcile-future-events';

  // Personnel — Roster Slots
  static String mobileBandRosterSlots(int bandId, int rosterId) =>
      '/api/mobile/bands/$bandId/rosters/$rosterId/slots';
  static String mobileBandRosterSlot(int bandId, int slotId) =>
      '/api/mobile/bands/$bandId/roster-slots/$slotId';

  // Personnel — Roster Members
  static String mobileBandRosterMembers(int bandId, int rosterId) =>
      '/api/mobile/bands/$bandId/rosters/$rosterId/members';
  static String mobileBandRosterMember(int bandId, int memberId) =>
      '/api/mobile/bands/$bandId/roster-members/$memberId';
  static String mobileBandRosterMemberToggleActive(int bandId, int memberId) =>
      '/api/mobile/bands/$bandId/roster-members/$memberId/toggle-active';

  // Personnel — Substitute Call Lists
  static String mobileBandCallLists(int bandId) =>
      '/api/mobile/bands/$bandId/call-lists';
  static String mobileBandCallList(int bandId, int entryId) =>
      '/api/mobile/bands/$bandId/call-lists/$entryId';
  static String mobileBandCallListsReorder(int bandId) =>
      '/api/mobile/bands/$bandId/call-lists/reorder';

  // Personnel — Band Subs
  static String mobileBandSubs(int bandId) =>
      '/api/mobile/bands/$bandId/subs';
  static String mobileBandSubInvite(int bandId) =>
      '/api/mobile/bands/$bandId/subs/invite';
  static String mobileBandSubInvitation(int bandId, int invitationId) =>
      '/api/mobile/bands/$bandId/subs/invitations/$invitationId';
  static String mobileBandSubUser(int bandId, int userId) =>
      '/api/mobile/bands/$bandId/subs/$userId';

  // Rehearsal Planner
  static String mobileRehearsalPlannerSessions(int bandId) =>
      '/api/mobile/bands/$bandId/rehearsal-planner/sessions';

  static String mobileRehearsalPlannerMessages(int bandId, int sessionId) =>
      '/api/mobile/bands/$bandId/rehearsal-planner/sessions/$sessionId/messages';

  static String mobileRehearsalPlannerSession(int bandId, int sessionId) =>
      '/api/mobile/bands/$bandId/rehearsal-planner/sessions/$sessionId';

  // Chat & comments
  static const String mobileConversations = '/api/mobile/conversations';
  static const String mobileConversationsDm = '/api/mobile/conversations/dm';
  static const String mobileChatContacts = '/api/mobile/chat/contacts';
  static String mobileConversationMessages(int conversationId) =>
      '/api/mobile/conversations/$conversationId/messages';
  static String mobileMessage(int messageId) => '/api/mobile/messages/$messageId';
  static String mobileConversationRead(int conversationId) =>
      '/api/mobile/conversations/$conversationId/read';
  static String mobileConversationTyping(int conversationId) =>
      '/api/mobile/conversations/$conversationId/typing';
  static String mobileEventConversation(String key) =>
      '/api/mobile/events/$key/conversation';
  static String mobileRehearsalConversation(int rehearsalId) =>
      '/api/mobile/rehearsals/$rehearsalId/conversation';
  static String mobileBookingConversation(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/conversation';
  static String mobileMessageAttachment(int messageId, int attachmentId) =>
      '/api/mobile/messages/$messageId/attachments/$attachmentId';

  // Questionnaires
  static String mobileBandQuestionnaires(int bandId) =>
      '/api/mobile/bands/$bandId/questionnaires';
  static String mobileBandQuestionnaireCatalog(int bandId) =>
      '/api/mobile/bands/$bandId/questionnaires/catalog';
  static String mobileBandQuestionnaire(int bandId, int questionnaireId) =>
      '/api/mobile/bands/$bandId/questionnaires/$questionnaireId';
  static String mobileBandQuestionnaireArchive(int bandId, int questionnaireId) =>
      '/api/mobile/bands/$bandId/questionnaires/$questionnaireId/archive';
  static String mobileBandQuestionnaireRestore(int bandId, int questionnaireId) =>
      '/api/mobile/bands/$bandId/questionnaires/$questionnaireId/restore';
  static String mobileBandQuestionnaireInstances(int bandId, int questionnaireId) =>
      '/api/mobile/bands/$bandId/questionnaires/$questionnaireId/instances';
  static String mobileBandQuestionnaireEligibleBookings(int bandId, int questionnaireId) =>
      '/api/mobile/bands/$bandId/questionnaires/$questionnaireId/eligible-bookings';
  static String mobileBandBookingQuestionnaireInstances(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/questionnaire-instances';
  static String mobileBandBookingQuestionnairesSend(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/questionnaires';
  static String mobileBandQuestionnaireInstance(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId';
  static String mobileBandQuestionnaireInstanceResend(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/resend';
  static String mobileBandQuestionnaireInstanceLock(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/lock';
  static String mobileBandQuestionnaireInstanceUnlock(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/unlock';
  static String mobileBandQuestionnaireResponseApply(
          int bandId, int instanceId, int responseId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/responses/$responseId/apply';
  static String mobileBandQuestionnaireInstanceApplyAll(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/apply-all';
  static String mobileBandQuestionnaireInstanceAppendToNotes(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/append-to-notes';
}
