/// Pure mapper: turn a push notification's data map into the in-app route to
/// open when the user taps it, or null if the type has no destination.
/// Kept free of platform channels so it is unit-testable (see
/// `inviteRouteForUri` in core/deeplink for the same pattern).
String? routeForPushData(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  if (type == 'chat_message') {
    final conversationId = int.tryParse(data['conversationId']?.toString() ?? '');
    if (conversationId == null) return null;
    return '/conversations/$conversationId';
  }
  if (type == 'questionnaire_submitted') {
    final questionnaireId =
        int.tryParse(data['questionnaireId']?.toString() ?? '');
    final instanceId = int.tryParse(data['instanceId']?.toString() ?? '');
    if (questionnaireId == null || instanceId == null) return null;
    return '/questionnaires/$questionnaireId/instances/$instanceId';
  }
  const rehearsalTypes = {
    'rehearsal_cancelled',
    'rehearsal_restored',
    'rehearsal_sub_added',
  };
  if (!rehearsalTypes.contains(type)) {
    return null;
  }
  final rehearsalId = int.tryParse(data['rehearsalId']?.toString() ?? '');
  if (rehearsalId == null) return null;
  return '/rehearsals/$rehearsalId';
}
