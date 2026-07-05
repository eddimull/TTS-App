/// Pure mapper: turn a push notification's data map into the in-app route to
/// open when the user taps it, or null if the type has no destination.
/// Kept free of platform channels so it is unit-testable (see
/// `inviteRouteForUri` in core/deeplink for the same pattern).
String? routeForPushData(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  if (type != 'rehearsal_cancelled' && type != 'rehearsal_restored') {
    return null;
  }
  final rehearsalId = int.tryParse(data['rehearsalId']?.toString() ?? '');
  if (rehearsalId == null) return null;
  return '/rehearsals/$rehearsalId';
}
