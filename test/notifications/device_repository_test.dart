import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/device_repository.dart';

/// Minimal in-memory Dio adapter capturing the last request.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;
  Object? lastBody;
  int statusCode = 200;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    lastBody = options.data;
    return ResponseBody.fromString('{}', statusCode,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
}

void main() {
  late Dio dio;
  late _CapturingAdapter adapter;
  late DeviceRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    adapter = _CapturingAdapter();
    dio.httpClientAdapter = adapter;
    repo = DeviceRepository(dio);
  });

  test('register POSTs token and platform to /api/mobile/devices', () async {
    await repo.register(token: 'tok-abc', platform: 'ios');
    expect(adapter.lastOptions!.method, 'POST');
    expect(adapter.lastOptions!.path, '/api/mobile/devices');
    expect(adapter.lastBody, {'token': 'tok-abc', 'platform': 'ios'});
  });

  test('deregister DELETEs /devices with the token in the body', () async {
    await repo.deregister('tok-abc');
    expect(adapter.lastOptions!.method, 'DELETE');
    expect(adapter.lastOptions!.path, '/api/mobile/devices');
    expect(adapter.lastBody, {'token': 'tok-abc'});
  });
}
