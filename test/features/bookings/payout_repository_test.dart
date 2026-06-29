import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);
}

void main() {
  test('fetchPayout parses the payout payload', () async {
    final dio = Dio()
      ..httpClientAdapter = _StubAdapter((o) => ResponseBody.fromString(
            '{"payout":{"id":9,"base_amount":"1000.00","adjusted_amount":"1000.00","payout_config_id":42},'
            '"config":{"id":42,"name":"Standard","is_active":true},'
            '"result":{"band_cut":200.0,"distributable_amount":800.0,"member_payouts":[],"payment_group_payouts":[]},'
            '"adjustments":[],"events":[],"available_configs":[]}',
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          ));
    final repo = BookingsRepository(dio);

    final payout = await repo.fetchPayout(1, 2);
    expect(payout.bandCut, 200.0);
    expect(payout.config?.name, 'Standard');
  });

  test('updateAttendance issues a PATCH with attendance_status', () async {
    RequestOptions? captured;
    final dio = Dio()
      ..httpClientAdapter = _StubAdapter((o) {
        captured = o;
        return ResponseBody.fromString('{"member":{"id":5,"attendance_status":"absent"}}', 200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
      });
    final repo = BookingsRepository(dio);

    await repo.updateAttendance(1, 2, 3, 5, 'absent');
    expect(captured!.method, 'PATCH');
    expect(captured!.data, {'attendance_status': 'absent'});
  });
}
