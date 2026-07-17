import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/push_route.dart';

void main() {
  test('rehearsal_cancelled routes to the rehearsal detail', () {
    expect(
      routeForPushData({'type': 'rehearsal_cancelled', 'rehearsalId': '42'}),
      '/rehearsals/42',
    );
  });

  test('rehearsal_restored routes to the rehearsal detail', () {
    expect(
      routeForPushData({'type': 'rehearsal_restored', 'rehearsalId': '7'}),
      '/rehearsals/7',
    );
  });

  test('missing or non-numeric rehearsalId does not route', () {
    expect(routeForPushData({'type': 'rehearsal_cancelled'}), isNull);
    expect(routeForPushData({'type': 'rehearsal_cancelled', 'rehearsalId': 'abc'}), isNull);
  });

  test('unknown types do not route', () {
    expect(routeForPushData({'type': 'event_reminder_8h', 'eventKey': 'k'}), isNull);
    expect(routeForPushData({}), isNull);
  });

  test('questionnaire_submitted routes to the instance responses screen', () {
    expect(
      routeForPushData({
        'type': 'questionnaire_submitted',
        'questionnaireId': '3',
        'instanceId': '9',
      }),
      '/questionnaires/3/instances/9',
    );
  });

  test('questionnaire_submitted without questionnaireId has no route', () {
    expect(
      routeForPushData({'type': 'questionnaire_submitted', 'instanceId': '9'}),
      isNull,
    );
  });
}
