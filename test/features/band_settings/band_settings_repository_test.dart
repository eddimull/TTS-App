import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/band_settings/data/band_settings_repository.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_detail.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_member.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_invitation.dart';

// Minimal Dio fake — returns pre-configured responses per path.
class _FakeDio extends Fake implements Dio {
  _FakeDio(this._responses);

  final Map<String, dynamic> _responses;
  String? lastPatchPath;
  Map<String, dynamic>? lastPatchData;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final body = _responses[path];
    if (body == null) throw DioException(requestOptions: RequestOptions(path: path));
    return Response<T>(
      data: body as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    void Function(int, int)? onSendProgress,
  }) async {
    lastPatchPath = path;
    lastPatchData = data as Map<String, dynamic>?;
    return Response<T>(
      data: _responses[path] as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return Response<T>(
      data: null,
      statusCode: 204,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final body = _responses[path];
    return Response<T>(
      data: body as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  const bandId = 10;
  const userId = 5;
  const invitationId = 99;

  group('BandSettingsRepository', () {
    test('test_getBandDetail_returns_parsed_detail', () async {
      final dio = _FakeDio({
        '/api/mobile/bands/$bandId': {
          'band': {
            'id': bandId,
            'name': 'The Eds',
            'site_name': 'the-eds',
            'address': '1 Main St',
            'city': 'Nashville',
            'state': 'TN',
            'zip': '37201',
            'logo_url': null,
          }
        },
      });
      final repo = BandSettingsRepository(dio);
      final detail = await repo.getBandDetail(bandId);
      expect(detail.name, 'The Eds');
      expect(detail.siteName, 'the-eds');
    });

    test('test_getMembers_returns_parsed_list', () async {
      final dio = _FakeDio({
        '/api/mobile/bands/$bandId/members': {
          'members': [
            {
              'id': userId,
              'name': 'Jane',
              'is_owner': false,
              'permissions': {'read:events': true, 'write:events': false},
            }
          ]
        },
      });
      final repo = BandSettingsRepository(dio);
      final members = await repo.getMembers(bandId);
      expect(members.length, 1);
      expect(members.first.name, 'Jane');
      expect(members.first.permissions['read:events'], true);
    });

    test('test_getInvitations_returns_parsed_list', () async {
      final dio = _FakeDio({
        '/api/mobile/bands/$bandId/invitations': {
          'invitations': [
            {
              'id': invitationId,
              'email': 'new@example.com',
              'invite_type': 'member',
              'key': 'abc-123',
            }
          ]
        },
      });
      final repo = BandSettingsRepository(dio);
      final invites = await repo.getInvitations(bandId);
      expect(invites.length, 1);
      expect(invites.first.email, 'new@example.com');
    });

    test('test_updateBandDetail_sends_patch_with_correct_data', () async {
      final dio = _FakeDio({
        '/api/mobile/bands/$bandId': {'band': <String, dynamic>{}},
      });
      final repo = BandSettingsRepository(dio);
      await repo.updateBandDetail(bandId,
          name: 'New Name',
          siteName: 'new-name',
          address: '2 Elm St',
          city: 'Memphis',
          state: 'TN',
          zip: '38101');
      expect(dio.lastPatchPath, '/api/mobile/bands/$bandId');
      expect(dio.lastPatchData!['name'], 'New Name');
      expect(dio.lastPatchData!['city'], 'Memphis');
    });

    test('test_setPermission_sends_patch_with_correct_data', () async {
      final dio = _FakeDio({
        '/api/mobile/bands/$bandId/members/$userId/permissions': <String, dynamic>{},
      });
      final repo = BandSettingsRepository(dio);
      await repo.setPermission(bandId, userId,
          permission: 'read:events', granted: true);
      expect(dio.lastPatchPath,
          '/api/mobile/bands/$bandId/members/$userId/permissions');
      expect(dio.lastPatchData!['permission'], 'read:events');
      expect(dio.lastPatchData!['granted'], true);
    });

    test('test_removeMember_completes_without_error', () async {
      final dio = _FakeDio({});
      final repo = BandSettingsRepository(dio);
      await expectLater(repo.removeMember(bandId, userId), completes);
    });

    test('test_revokeInvitation_completes_without_error', () async {
      final dio = _FakeDio({});
      final repo = BandSettingsRepository(dio);
      await expectLater(
          repo.revokeInvitation(bandId, invitationId), completes);
    });
  });
}
