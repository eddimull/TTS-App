import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

void main() {
  test('connection-type DioExceptions map to the offline message', () {
    final e = DioException(
      requestOptions: RequestOptions(path: '/api/mobile/dashboard'),
      type: DioExceptionType.connectionError,
    );
    expect(ErrorView.friendlyMessage(e), kOfflineMessage);
  });

  test('OfflineException maps to the offline message', () {
    expect(
        ErrorView.friendlyMessage(const OfflineException()), kOfflineMessage);
  });

  test('server message from a response body still wins for HTTP errors', () {
    final e = DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 422,
        data: {'message': 'Name is required.'},
      ),
    );
    expect(ErrorView.friendlyMessage(e), 'Name is required.');
  });

  test('non-network errors fall back to toString', () {
    expect(ErrorView.friendlyMessage(StateError('boom')),
        contains('boom'));
  });
}
