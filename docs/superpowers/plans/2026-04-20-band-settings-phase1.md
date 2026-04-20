# Band Settings Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an owner-only Band Settings section to the mobile app covering band info editing, member management with per-feature permission toggles, invitation management, and QR invite.

**Architecture:** New `lib/features/band_settings/` feature slice following the existing `data/ → providers/ → screens/` pattern. Backend gains a new `BandSettingsController` with 8 new endpoints; the existing `OnboardingController` invite/QR endpoints are reused. Flutter state lives in a single `BandSettingsNotifier` (AsyncNotifier) with optimistic permission toggle updates.

**Tech Stack:** Flutter/Dart, Riverpod v2 AsyncNotifier, Dio, GoRouter, Cupertino widgets, qr_flutter (already in pubspec), image_picker (already in pubspec). Laravel backend with Sanctum auth, Spatie permissions (team-scoped), BandMemberRemovalService.

---

## File Map

### New files — Flutter
- `lib/features/band_settings/data/models/band_detail.dart` — name, site_name, address fields, logo_url
- `lib/features/band_settings/data/models/band_member.dart` — id, name, is_owner, permissions map
- `lib/features/band_settings/data/models/band_invitation.dart` — id, email, invite_type, key
- `lib/features/band_settings/data/band_settings_repository.dart` — all API calls for this feature
- `lib/features/band_settings/providers/band_settings_provider.dart` — AsyncNotifier + provider
- `lib/features/band_settings/screens/band_settings_screen.dart` — grouped settings list (4 sections)
- `lib/features/band_settings/screens/band_info_edit_screen.dart` — name/URL/address/logo form
- `lib/features/band_settings/screens/member_permissions_screen.dart` — 9 read/write toggles
- `lib/features/band_settings/screens/widgets/invite_section.dart` — expandable email + QR widget
- `test/features/band_settings/band_settings_repository_test.dart`
- `test/features/band_settings/band_settings_provider_test.dart`

### Modified files — Flutter
- `lib/core/network/api_endpoints.dart` — 7 new endpoint constants
- `lib/core/config/router.dart` — add `/band-settings` route (child screens use Navigator.push, not GoRouter)
- `lib/features/more/screens/more_screen.dart` — owner-only Band Settings tile

### New files — Laravel backend
- `app/Http/Controllers/Api/Mobile/BandSettingsController.php` — 8 new actions
- `routes/api.php` — register new routes under the mobile middleware group

---

## Task 1: Add API endpoint constants

**Files:**
- Modify: `lib/core/network/api_endpoints.dart`

- [ ] **Step 1: Add the 7 new endpoint methods**

Open `lib/core/network/api_endpoints.dart` and append these static methods inside the `ApiEndpoints` class, after the existing onboarding block:

```dart
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
```

- [ ] **Step 2: Verify no analysis errors**

```bash
flutter analyze lib/core/network/api_endpoints.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add lib/core/network/api_endpoints.dart
git commit -m "feat: add band settings API endpoint constants"
```

---

## Task 2: Data models

**Files:**
- Create: `lib/features/band_settings/data/models/band_detail.dart`
- Create: `lib/features/band_settings/data/models/band_member.dart`
- Create: `lib/features/band_settings/data/models/band_invitation.dart`

- [ ] **Step 1: Write failing model tests**

Create `test/features/band_settings/band_settings_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_detail.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_member.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_invitation.dart';

void main() {
  group('BandDetail.fromJson', () {
    test('test_parses_all_fields', () {
      final detail = BandDetail.fromJson({
        'id': 42,
        'name': 'The Rocking Eds',
        'site_name': 'the-rocking-eds',
        'address': '123 Main St',
        'city': 'Nashville',
        'state': 'TN',
        'zip': '37201',
        'logo_url': 'https://example.com/logo.png',
      });
      expect(detail.id, 42);
      expect(detail.name, 'The Rocking Eds');
      expect(detail.siteName, 'the-rocking-eds');
      expect(detail.address, '123 Main St');
      expect(detail.city, 'Nashville');
      expect(detail.state, 'TN');
      expect(detail.zip, '37201');
      expect(detail.logoUrl, 'https://example.com/logo.png');
    });

    test('test_handles_null_optional_fields', () {
      final detail = BandDetail.fromJson({
        'id': 1,
        'name': 'Band',
        'site_name': 'band',
      });
      expect(detail.address, '');
      expect(detail.city, '');
      expect(detail.state, '');
      expect(detail.zip, '');
      expect(detail.logoUrl, isNull);
    });
  });

  group('BandMember.fromJson', () {
    test('test_parses_member_with_permissions', () {
      final member = BandMember.fromJson({
        'id': 5,
        'name': 'Jane Doe',
        'is_owner': false,
        'permissions': {
          'read:events': true,
          'write:events': false,
          'read:bookings': true,
          'write:bookings': false,
          'read:rehearsals': true,
          'write:rehearsals': false,
          'read:charts': true,
          'write:charts': false,
          'read:songs': true,
          'write:songs': false,
          'read:media': false,
          'write:media': false,
          'read:invoices': false,
          'write:invoices': false,
          'read:proposals': false,
          'write:proposals': false,
          'read:colors': false,
          'write:colors': false,
        },
      });
      expect(member.id, 5);
      expect(member.name, 'Jane Doe');
      expect(member.isOwner, false);
      expect(member.permissions['read:events'], true);
      expect(member.permissions['write:events'], false);
    });

    test('test_parses_owner', () {
      final member = BandMember.fromJson({
        'id': 1,
        'name': 'Eddie',
        'is_owner': true,
        'permissions': {},
      });
      expect(member.isOwner, true);
    });
  });

  group('BandInvitation.fromJson', () {
    test('test_parses_invitation', () {
      final inv = BandInvitation.fromJson({
        'id': 99,
        'email': 'new@example.com',
        'invite_type': 'member',
        'key': 'abc-123',
      });
      expect(inv.id, 99);
      expect(inv.email, 'new@example.com');
      expect(inv.inviteType, 'member');
      expect(inv.key, 'abc-123');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/features/band_settings/band_settings_models_test.dart
```

Expected: FAIL — models not found.

- [ ] **Step 3: Create BandDetail model**

Create `lib/features/band_settings/data/models/band_detail.dart`:

```dart
class BandDetail {
  const BandDetail({
    required this.id,
    required this.name,
    required this.siteName,
    required this.address,
    required this.city,
    required this.state,
    required this.zip,
    this.logoUrl,
  });

  final int id;
  final String name;
  final String siteName;
  final String address;
  final String city;
  final String state;
  final String zip;
  final String? logoUrl;

  factory BandDetail.fromJson(Map<String, dynamic> json) {
    return BandDetail(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      siteName: json['site_name'] as String,
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      zip: json['zip'] as String? ?? '',
      logoUrl: json['logo_url'] as String?,
    );
  }

  BandDetail copyWith({
    String? name,
    String? siteName,
    String? address,
    String? city,
    String? state,
    String? zip,
    String? logoUrl,
  }) {
    return BandDetail(
      id: id,
      name: name ?? this.name,
      siteName: siteName ?? this.siteName,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zip: zip ?? this.zip,
      logoUrl: logoUrl ?? this.logoUrl,
    );
  }
}
```

- [ ] **Step 4: Create BandMember model**

Create `lib/features/band_settings/data/models/band_member.dart`:

```dart
class BandMember {
  const BandMember({
    required this.id,
    required this.name,
    required this.isOwner,
    required this.permissions,
  });

  final int id;
  final String name;
  final bool isOwner;

  /// Keys are Spatie permission strings e.g. 'read:events', 'write:events'.
  final Map<String, bool> permissions;

  factory BandMember.fromJson(Map<String, dynamic> json) {
    final rawPerms = (json['permissions'] as Map<String, dynamic>?) ?? {};
    return BandMember(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      isOwner: (json['is_owner'] as bool?) ?? false,
      permissions: rawPerms.map((k, v) => MapEntry(k, v as bool)),
    );
  }

  BandMember withPermission(String permission, {required bool granted}) {
    return BandMember(
      id: id,
      name: name,
      isOwner: isOwner,
      permissions: {...permissions, permission: granted},
    );
  }
}
```

- [ ] **Step 5: Create BandInvitation model**

Create `lib/features/band_settings/data/models/band_invitation.dart`:

```dart
class BandInvitation {
  const BandInvitation({
    required this.id,
    required this.email,
    required this.inviteType,
    required this.key,
  });

  final int id;
  final String email;

  /// 'owner' or 'member'
  final String inviteType;
  final String key;

  factory BandInvitation.fromJson(Map<String, dynamic> json) {
    return BandInvitation(
      id: (json['id'] as num).toInt(),
      email: json['email'] as String,
      inviteType: json['invite_type'] as String,
      key: json['key'] as String,
    );
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
flutter test test/features/band_settings/band_settings_models_test.dart
```

Expected: 5 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/band_settings/data/models/ test/features/band_settings/band_settings_models_test.dart
git commit -m "feat: add band settings data models (BandDetail, BandMember, BandInvitation)"
```

---

## Task 3: BandSettingsRepository

**Files:**
- Create: `lib/features/band_settings/data/band_settings_repository.dart`
- Create: `test/features/band_settings/band_settings_repository_test.dart`

- [ ] **Step 1: Write failing repository tests**

Create `test/features/band_settings/band_settings_repository_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/features/band_settings/band_settings_repository_test.dart
```

Expected: FAIL — `BandSettingsRepository` not found.

- [ ] **Step 3: Create the repository**

Create `lib/features/band_settings/data/band_settings_repository.dart`:

```dart
import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/band_detail.dart';
import 'models/band_invitation.dart';
import 'models/band_member.dart';

class BandSettingsRepository {
  BandSettingsRepository(this._dio);

  final Dio _dio;

  Future<BandDetail> getBandDetail(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandDetail(bandId),
    );
    return BandDetail.fromJson(
        response.data!['band'] as Map<String, dynamic>);
  }

  Future<void> updateBandDetail(
    int bandId, {
    required String name,
    required String siteName,
    required String address,
    required String city,
    required String state,
    required String zip,
  }) async {
    await _dio.patch<void>(
      ApiEndpoints.mobileBandDetail(bandId),
      data: {
        'name': name,
        'site_name': siteName,
        'address': address,
        'city': city,
        'state': state,
        'zip': zip,
      },
    );
  }

  Future<void> uploadLogo(int bandId, List<int> bytes, String filename) async {
    final formData = FormData.fromMap({
      'logo': MultipartFile.fromBytes(bytes, filename: filename),
    });
    await _dio.post<void>(
      ApiEndpoints.mobileBandLogo(bandId),
      data: formData,
    );
  }

  Future<List<BandMember>> getMembers(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandMembers(bandId),
    );
    final list = response.data!['members'] as List<dynamic>;
    return list
        .map((m) => BandMember.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeMember(int bandId, int userId) async {
    await _dio.delete<void>(
      ApiEndpoints.mobileBandMember(bandId, userId),
    );
  }

  Future<void> setPermission(
    int bandId,
    int userId, {
    required String permission,
    required bool granted,
  }) async {
    await _dio.patch<void>(
      ApiEndpoints.mobileBandMemberPermissions(bandId, userId),
      data: {'permission': permission, 'granted': granted},
    );
  }

  Future<List<BandInvitation>> getInvitations(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandInvitations(bandId),
    );
    final list = response.data!['invitations'] as List<dynamic>;
    return list
        .map((i) => BandInvitation.fromJson(i as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeInvitation(int bandId, int invitationId) async {
    await _dio.delete<void>(
      ApiEndpoints.mobileBandInvitation(bandId, invitationId),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/features/band_settings/band_settings_repository_test.dart
```

Expected: 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/band_settings/data/band_settings_repository.dart \
        test/features/band_settings/band_settings_repository_test.dart
git commit -m "feat: add BandSettingsRepository with full CRUD for band settings"
```

---

## Task 4: BandSettingsNotifier (provider)

**Files:**
- Create: `lib/features/band_settings/providers/band_settings_provider.dart`
- Create: `test/features/band_settings/band_settings_provider_test.dart`

- [ ] **Step 1: Write failing provider tests**

Create `test/features/band_settings/band_settings_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/band_settings/data/band_settings_repository.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_detail.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_invitation.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_member.dart';
import 'package:tts_bandmate/features/band_settings/providers/band_settings_provider.dart';

// ── Fake repository ───────────────────────────────────────────────────────────

class FakeBandSettingsRepository implements BandSettingsRepository {
  FakeBandSettingsRepository({
    this.detail,
    this.members = const [],
    this.invitations = const [],
    this.setPermissionShouldFail = false,
  });

  final BandDetail? detail;
  final List<BandMember> members;
  final List<BandInvitation> invitations;
  final bool setPermissionShouldFail;

  String? lastPermission;
  bool? lastGranted;
  int? removedMemberId;
  int? revokedInvitationId;

  @override
  Future<BandDetail> getBandDetail(int bandId) async =>
      detail ??
      const BandDetail(
          id: 10,
          name: 'Test Band',
          siteName: 'test-band',
          address: '',
          city: '',
          state: '',
          zip: '');

  @override
  Future<void> updateBandDetail(int bandId,
      {required String name,
      required String siteName,
      required String address,
      required String city,
      required String state,
      required String zip}) async {}

  @override
  Future<void> uploadLogo(int bandId, List<int> bytes, String filename) async {}

  @override
  Future<List<BandMember>> getMembers(int bandId) async => members;

  @override
  Future<void> removeMember(int bandId, int userId) async {
    removedMemberId = userId;
  }

  @override
  Future<void> setPermission(int bandId, int userId,
      {required String permission, required bool granted}) async {
    if (setPermissionShouldFail) throw Exception('Server error');
    lastPermission = permission;
    lastGranted = granted;
  }

  @override
  Future<List<BandInvitation>> getInvitations(int bandId) async => invitations;

  @override
  Future<void> revokeInvitation(int bandId, int invitationId) async {
    revokedInvitationId = invitationId;
  }
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _member = BandMember(
  id: 5,
  name: 'Jane',
  isOwner: false,
  permissions: {'read:events': false},
);

const _invite = BandInvitation(
  id: 99,
  email: 'new@example.com',
  inviteType: 'member',
  key: 'abc-123',
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('BandSettingsNotifier', () {
    ProviderContainer makeContainer(FakeBandSettingsRepository repo) {
      return ProviderContainer(
        overrides: [
          bandSettingsRepositoryProvider.overrideWithValue(repo),
        ],
      );
    }

    test('test_load_populates_state', () async {
      final repo = FakeBandSettingsRepository(
        members: [_member],
        invitations: [_invite],
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(bandSettingsProvider(10).notifier).load();

      final state = container.read(bandSettingsProvider(10)).value!;
      expect(state.detail.name, 'Test Band');
      expect(state.members.length, 1);
      expect(state.invitations.length, 1);
    });

    test('test_togglePermission_optimistically_updates_and_calls_repo',
        () async {
      final repo = FakeBandSettingsRepository(members: [_member]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(bandSettingsProvider(10).notifier).load();

      await container
          .read(bandSettingsProvider(10).notifier)
          .togglePermission(memberId: 5, permission: 'read:events', granted: true);

      final state = container.read(bandSettingsProvider(10)).value!;
      expect(state.members.first.permissions['read:events'], true);
      expect(repo.lastPermission, 'read:events');
      expect(repo.lastGranted, true);
    });

    test('test_togglePermission_reverts_on_api_failure', () async {
      final repo = FakeBandSettingsRepository(
        members: [_member],
        setPermissionShouldFail: true,
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(bandSettingsProvider(10).notifier).load();

      Object? caughtError;
      try {
        await container
            .read(bandSettingsProvider(10).notifier)
            .togglePermission(
                memberId: 5, permission: 'read:events', granted: true);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isNotNull);
      final state = container.read(bandSettingsProvider(10)).value!;
      // Should have reverted to false
      expect(state.members.first.permissions['read:events'], false);
    });

    test('test_removeMember_removes_from_local_state', () async {
      final repo = FakeBandSettingsRepository(members: [_member]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(bandSettingsProvider(10).notifier).load();

      await container
          .read(bandSettingsProvider(10).notifier)
          .removeMember(bandId: 10, userId: 5);

      final state = container.read(bandSettingsProvider(10)).value!;
      expect(state.members, isEmpty);
      expect(repo.removedMemberId, 5);
    });

    test('test_revokeInvitation_removes_from_local_state', () async {
      final repo = FakeBandSettingsRepository(invitations: [_invite]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(bandSettingsProvider(10).notifier).load();

      await container
          .read(bandSettingsProvider(10).notifier)
          .revokeInvitation(bandId: 10, invitationId: 99);

      final state = container.read(bandSettingsProvider(10)).value!;
      expect(state.invitations, isEmpty);
      expect(repo.revokedInvitationId, 99);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/features/band_settings/band_settings_provider_test.dart
```

Expected: FAIL — `BandSettingsNotifier` not found.

- [ ] **Step 3: Create the provider**

Create `lib/features/band_settings/providers/band_settings_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/band_settings_repository.dart';
import '../data/models/band_detail.dart';
import '../data/models/band_invitation.dart';
import '../data/models/band_member.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class BandSettingsState {
  const BandSettingsState({
    required this.detail,
    required this.members,
    required this.invitations,
  });

  final BandDetail detail;
  final List<BandMember> members;
  final List<BandInvitation> invitations;

  BandSettingsState copyWith({
    BandDetail? detail,
    List<BandMember>? members,
    List<BandInvitation>? invitations,
  }) {
    return BandSettingsState(
      detail: detail ?? this.detail,
      members: members ?? this.members,
      invitations: invitations ?? this.invitations,
    );
  }
}

// ── Repository provider ───────────────────────────────────────────────────────

final bandSettingsRepositoryProvider =
    Provider<BandSettingsRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return BandSettingsRepository(dio);
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class BandSettingsNotifier
    extends FamilyAsyncNotifier<BandSettingsState, int> {
  BandSettingsRepository get _repo =>
      ref.read(bandSettingsRepositoryProvider);

  @override
  Future<BandSettingsState> build(int bandId) async {
    final results = await Future.wait([
      _repo.getBandDetail(bandId),
      _repo.getMembers(bandId),
      _repo.getInvitations(bandId),
    ]);
    return BandSettingsState(
      detail: results[0] as BandDetail,
      members: results[1] as List<BandMember>,
      invitations: results[2] as List<BandInvitation>,
    );
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build(arg));
  }

  /// Optimistic toggle: flips locally, reverts and rethrows on failure.
  Future<void> togglePermission({
    required int memberId,
    required String permission,
    required bool granted,
  }) async {
    final current = state.value;
    if (current == null) return;

    // Apply optimistic update
    final updated = current.members.map((m) {
      if (m.id != memberId) return m;
      return m.withPermission(permission, granted: granted);
    }).toList();
    state = AsyncValue.data(current.copyWith(members: updated));

    try {
      await _repo.setPermission(arg, memberId,
          permission: permission, granted: granted);
    } catch (e) {
      // Revert
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  Future<void> removeMember({
    required int bandId,
    required int userId,
  }) async {
    await _repo.removeMember(bandId, userId);
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        members: current.members.where((m) => m.id != userId).toList(),
      ),
    );
  }

  Future<void> revokeInvitation({
    required int bandId,
    required int invitationId,
  }) async {
    await _repo.revokeInvitation(bandId, invitationId);
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        invitations:
            current.invitations.where((i) => i.id != invitationId).toList(),
      ),
    );
  }

  Future<void> updateDetail(BandDetail detail) async {
    await _repo.updateBandDetail(
      detail.id,
      name: detail.name,
      siteName: detail.siteName,
      address: detail.address,
      city: detail.city,
      state: detail.state,
      zip: detail.zip,
    );
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(current.copyWith(detail: detail));
  }
}

final bandSettingsProvider = AsyncNotifierProviderFamily<
    BandSettingsNotifier, BandSettingsState, int>(
  () => BandSettingsNotifier(),
);
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/features/band_settings/band_settings_provider_test.dart
```

Expected: 5 tests PASS.

- [ ] **Step 5: Run all tests to check no regressions**

```bash
flutter test
```

Expected: all existing tests plus new ones pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/band_settings/providers/band_settings_provider.dart \
        test/features/band_settings/band_settings_provider_test.dart
git commit -m "feat: add BandSettingsNotifier with optimistic permission toggles"
```

---

## Task 5: Backend — BandSettingsController

**Files:**
- Create: `app/Http/Controllers/Api/Mobile/BandSettingsController.php`
- Modify: `routes/api.php`

All work is in the Laravel backend at `/home/eddie/github/TTS`.

- [ ] **Step 1: Create the controller**

Create `app/Http/Controllers/Api/Mobile/BandSettingsController.php`:

```php
<?php

namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Models\Bands;
use App\Models\BandMembers;
use App\Models\Invitations;
use App\Services\BandMemberRemovalService;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Spatie\Permission\Models\Permission;

class BandSettingsController extends Controller
{
    public function __construct(
        private BandMemberRemovalService $removalService
    ) {}

    public function show(Bands $band): JsonResponse
    {
        return response()->json([
            'band' => [
                'id'       => $band->id,
                'name'     => $band->name,
                'site_name'=> $band->site_name,
                'address'  => $band->address ?? '',
                'city'     => $band->city ?? '',
                'state'    => $band->state ?? '',
                'zip'      => $band->zip ?? '',
                'logo_url' => $band->logo_url ?? null,
            ],
        ]);
    }

    public function update(Request $request, Bands $band): JsonResponse
    {
        $data = $request->validate([
            'name'      => 'required|string|max:255',
            'site_name' => 'required|string|max:255|unique:bands,site_name,' . $band->id,
            'address'   => 'nullable|string|max:255',
            'city'      => 'nullable|string|max:100',
            'state'     => 'nullable|string|max:100',
            'zip'       => 'nullable|string|max:20',
        ]);
        $band->update($data);
        return response()->json(['band' => $band->fresh()]);
    }

    public function uploadLogo(Request $request, Bands $band): JsonResponse
    {
        $request->validate(['logo' => 'required|image|max:5120']);
        $path = $request->file('logo')->store("bands/{$band->id}/logo", 'public');
        $band->update(['logo_url' => asset('storage/' . $path)]);
        return response()->json(['logo_url' => $band->logo_url]);
    }

    public function members(Bands $band): JsonResponse
    {
        setPermissionsTeamId($band->id);

        $ownerIds = $band->owners()->pluck('user_id')->toArray();

        $members = $band->everyone()->get()->map(function ($user) use ($ownerIds, $band) {
            setPermissionsTeamId($band->id);
            $isOwner = in_array($user->id, $ownerIds);
            $perms = [];
            foreach ($this->allPermissionNames() as $perm) {
                $perms[$perm] = $isOwner || $user->hasPermissionTo($perm);
            }
            return [
                'id'          => $user->id,
                'name'        => $user->name,
                'is_owner'    => $isOwner,
                'permissions' => $perms,
            ];
        });

        return response()->json(['members' => $members]);
    }

    public function removeMember(Bands $band, int $userId): JsonResponse
    {
        $this->removalService->remove($band, $userId);
        return response()->json(null, 204);
    }

    public function setPermission(Request $request, Bands $band, int $userId): JsonResponse
    {
        $data = $request->validate([
            'permission' => 'required|string',
            'granted'    => 'required|boolean',
        ]);

        $user = \App\Models\User::findOrFail($userId);
        setPermissionsTeamId($band->id);

        if ($data['granted']) {
            $user->givePermissionTo($data['permission']);
        } else {
            $user->revokePermissionTo($data['permission']);
        }

        return response()->json(['ok' => true]);
    }

    public function invitations(Bands $band): JsonResponse
    {
        $invitations = $band->invitations()
            ->where('pending', true)
            ->get()
            ->map(fn($inv) => [
                'id'          => $inv->id,
                'email'       => $inv->email,
                'invite_type' => $inv->invite_type_id === 1 ? 'owner' : 'member',
                'key'         => $inv->key,
            ]);

        return response()->json(['invitations' => $invitations]);
    }

    public function revokeInvitation(Bands $band, Invitations $invitation): JsonResponse
    {
        $invitation->update(['pending' => false]);
        return response()->json(null, 204);
    }

    private function allPermissionNames(): array
    {
        return [
            'read:events', 'write:events',
            'read:bookings', 'write:bookings',
            'read:rehearsals', 'write:rehearsals',
            'read:charts', 'write:charts',
            'read:songs', 'write:songs',
            'read:media', 'write:media',
            'read:invoices', 'write:invoices',
            'read:proposals', 'write:proposals',
            'read:colors', 'write:colors',
        ];
    }
}
```

- [ ] **Step 2: Register routes in routes/api.php**

In `routes/api.php`, inside the Sanctum-authenticated mobile middleware group, add these routes after the existing onboarding routes. All are protected by the existing `owner` middleware on the band:

```php
// Band Settings (owner only)
Route::middleware(['auth:sanctum', 'userInBand', 'owner'])->group(function () {
    Route::get('/mobile/bands/{band}', [BandSettingsController::class, 'show']);
    Route::patch('/mobile/bands/{band}', [BandSettingsController::class, 'update']);
    Route::post('/mobile/bands/{band}/logo', [BandSettingsController::class, 'uploadLogo']);
    Route::get('/mobile/bands/{band}/members', [BandSettingsController::class, 'members']);
    Route::delete('/mobile/bands/{band}/members/{userId}', [BandSettingsController::class, 'removeMember']);
    Route::patch('/mobile/bands/{band}/members/{userId}/permissions', [BandSettingsController::class, 'setPermission']);
    Route::get('/mobile/bands/{band}/invitations', [BandSettingsController::class, 'invitations']);
    Route::delete('/mobile/bands/{band}/invitations/{invitation}', [BandSettingsController::class, 'revokeInvitation']);
});
```

Also add the import at the top of the controller file if the `use` statements are not auto-resolved:
```php
use App\Http\Controllers\Api\Mobile\BandSettingsController;
```

- [ ] **Step 3: Verify routes are registered**

```bash
cd /home/eddie/github/TTS && php artisan route:list --path=api/mobile/bands
```

Expected: the 8 new routes appear in the list.

- [ ] **Step 4: Verify no PHP syntax errors**

```bash
cd /home/eddie/github/TTS && php artisan route:cache
```

Expected: `Routes cached successfully.`

- [ ] **Step 5: Clear route cache**

```bash
cd /home/eddie/github/TTS && php artisan route:clear
```

- [ ] **Step 6: Commit (backend)**

```bash
cd /home/eddie/github/TTS
git add app/Http/Controllers/Api/Mobile/BandSettingsController.php routes/api.php
git commit -m "feat: add BandSettingsController with 8 mobile API endpoints"
```

---

## Task 6: MemberPermissionsScreen

**Files:**
- Create: `lib/features/band_settings/screens/member_permissions_screen.dart`

- [ ] **Step 1: Create the screen**

Create `lib/features/band_settings/screens/member_permissions_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/band_member.dart';
import '../providers/band_settings_provider.dart';

class MemberPermissionsScreen extends ConsumerWidget {
  const MemberPermissionsScreen({
    super.key,
    required this.bandId,
    required this.member,
  });

  final int bandId;
  final BandMember member;

  static const _resources = [
    ('Events', 'events'),
    ('Bookings', 'bookings'),
    ('Rehearsals', 'rehearsals'),
    ('Charts', 'charts'),
    ('Songs', 'songs'),
    ('Media', 'media'),
    ('Invoices', 'invoices'),
    ('Proposals', 'proposals'),
    ('Colors', 'colors'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(bandSettingsProvider(bandId));
    final currentMember = settingsAsync.value?.members
        .where((m) => m.id == member.id)
        .firstOrNull ?? member;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(currentMember.name),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            if (currentMember.isOwner)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Owners have full access to all features.',
                  style: TextStyle(color: CupertinoColors.secondaryLabel),
                ),
              ),
            const SizedBox(height: 8),
            CupertinoListSection.insetGrouped(
              header: const Text('Permissions'),
              children: [
                for (final (label, key) in _resources) ...[
                  _PermissionRow(
                    label: '$label — Read',
                    permissionKey: 'read:$key',
                    value: currentMember.permissions['read:$key'] ?? false,
                    isOwner: currentMember.isOwner,
                    memberId: currentMember.id,
                    bandId: bandId,
                  ),
                  _PermissionRow(
                    label: '$label — Write',
                    permissionKey: 'write:$key',
                    value: currentMember.permissions['write:$key'] ?? false,
                    isOwner: currentMember.isOwner,
                    memberId: currentMember.id,
                    bandId: bandId,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends ConsumerWidget {
  const _PermissionRow({
    required this.label,
    required this.permissionKey,
    required this.value,
    required this.isOwner,
    required this.memberId,
    required this.bandId,
  });

  final String label;
  final String permissionKey;
  final bool value;
  final bool isOwner;
  final int memberId;
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoListTile(
      title: Text(label),
      trailing: CupertinoSwitch(
        value: isOwner ? true : value,
        onChanged: isOwner
            ? null
            : (granted) async {
                try {
                  await ref
                      .read(bandSettingsProvider(bandId).notifier)
                      .togglePermission(
                        memberId: memberId,
                        permission: permissionKey,
                        granted: granted,
                      );
                } catch (_) {
                  if (context.mounted) {
                    showCupertinoDialog<void>(
                      context: context,
                      builder: (_) => CupertinoAlertDialog(
                        title: const Text('Error'),
                        content: const Text(
                            'Failed to update permission. Please try again.'),
                        actions: [
                          CupertinoDialogAction(
                            child: const Text('OK'),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    );
                  }
                }
              },
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze for errors**

```bash
flutter analyze lib/features/band_settings/screens/member_permissions_screen.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/band_settings/screens/member_permissions_screen.dart
git commit -m "feat: add MemberPermissionsScreen with 18 read/write toggles"
```

---

## Task 7: InviteSection widget

**Files:**
- Create: `lib/features/band_settings/screens/widgets/invite_section.dart`

- [ ] **Step 1: Create the widget**

Create `lib/features/band_settings/screens/widgets/invite_section.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/band_invitation.dart';
import '../../providers/band_settings_provider.dart';
import '../../../../../features/bands/data/bands_repository.dart';
import '../../../../../features/bands/providers/bands_provider.dart';

class InviteSection extends ConsumerStatefulWidget {
  const InviteSection({super.key, required this.bandId});

  final int bandId;

  @override
  ConsumerState<InviteSection> createState() => _InviteSectionState();
}

class _InviteSectionState extends ConsumerState<InviteSection> {
  bool _expanded = false;
  final _emailController = TextEditingController();
  int _selectedType = 1; // 0 = owner, 1 = member
  bool _sending = false;
  String? _inviteKey;

  @override
  void initState() {
    super.initState();
    _loadInviteKey();
  }

  Future<void> _loadInviteKey() async {
    try {
      final key = await ref
          .read(bandsRepositoryProvider)
          .getInviteKey(widget.bandId);
      if (mounted) setState(() => _inviteKey = key);
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendInvite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(bandsRepositoryProvider).inviteMembers(
            widget.bandId,
            [email],
          );
      _emailController.clear();
      setState(() => _expanded = false);
      // Reload invitations
      await ref
          .read(bandSettingsProvider(widget.bandId).notifier)
          .load();
    } catch (_) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to send invite. Please try again.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showQrModal() {
    if (_inviteKey == null) return;
    final key = _inviteKey!;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Invite QR Code'),
        message: Column(
          children: [
            QrImageView(data: key, size: 200),
            const SizedBox(height: 8),
            const Text('Anyone with this code can join your band.'),
          ],
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Share.share(key);
              Navigator.of(context).pop();
            },
            child: const Text('Share Code'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      header: const Text('Invite'),
      children: [
        CupertinoListTile(
          title: const Text('Invite a Member'),
          trailing: Icon(
            _expanded
                ? CupertinoIcons.chevron_up
                : CupertinoIcons.chevron_down,
            size: 16,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CupertinoTextField(
                  controller: _emailController,
                  placeholder: 'Email address',
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                ),
                const SizedBox(height: 8),
                CupertinoSlidingSegmentedControl<int>(
                  groupValue: _selectedType,
                  onValueChanged: (v) =>
                      setState(() => _selectedType = v ?? 1),
                  children: const {
                    0: Text('Owner'),
                    1: Text('Member'),
                  },
                ),
                const SizedBox(height: 12),
                CupertinoButton.filled(
                  onPressed: _sending ? null : _sendInvite,
                  child: _sending
                      ? const CupertinoActivityIndicator()
                      : const Text('Send Invite'),
                ),
              ],
            ),
          ),
        ],
        if (_inviteKey != null)
          CupertinoListTile(
            title: const Text('Show QR Code'),
            leading: const Icon(CupertinoIcons.qrcode),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 14),
            onTap: _showQrModal,
          ),
      ],
    );
  }
}
```

- [ ] **Step 2: Check if `share_plus` is in pubspec. If not, add it.**

```bash
grep 'share_plus' /home/eddie/github/tts_bandmate/pubspec.yaml
```

If not found, add `share_plus: ^10.0.0` to the `dependencies` section in `pubspec.yaml`, then run:

```bash
flutter pub get
```

- [ ] **Step 3: Analyze for errors**

```bash
flutter analyze lib/features/band_settings/screens/widgets/invite_section.dart
```

Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/band_settings/screens/widgets/invite_section.dart pubspec.yaml pubspec.lock
git commit -m "feat: add InviteSection widget with expandable form and QR modal"
```

---

## Task 8: BandInfoEditScreen

**Files:**
- Create: `lib/features/band_settings/screens/band_info_edit_screen.dart`

- [ ] **Step 1: Create the screen**

Create `lib/features/band_settings/screens/band_info_edit_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../data/models/band_detail.dart';
import '../providers/band_settings_provider.dart';

class BandInfoEditScreen extends ConsumerStatefulWidget {
  const BandInfoEditScreen({
    super.key,
    required this.bandId,
    required this.initial,
  });

  final int bandId;
  final BandDetail initial;

  @override
  ConsumerState<BandInfoEditScreen> createState() => _BandInfoEditScreenState();
}

class _BandInfoEditScreenState extends ConsumerState<BandInfoEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _siteName;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _zip;
  bool _saving = false;
  bool _uploadingLogo = false;
  String? _logoUrl;
  final Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _name = TextEditingController(text: d.name);
    _siteName = TextEditingController(text: d.siteName);
    _address = TextEditingController(text: d.address);
    _city = TextEditingController(text: d.city);
    _state = TextEditingController(text: d.state);
    _zip = TextEditingController(text: d.zip);
    _logoUrl = d.logoUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _siteName.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _zip.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _uploadingLogo = true);
    try {
      final bytes = await file.readAsBytes();
      await ref
          .read(bandSettingsRepositoryProvider)
          .uploadLogo(widget.bandId, bytes, file.name);
      // Re-fetch detail to get updated logo_url
      await ref.read(bandSettingsProvider(widget.bandId).notifier).load();
      final detail = ref.read(bandSettingsProvider(widget.bandId)).value?.detail;
      if (mounted) setState(() => _logoUrl = detail?.logoUrl);
    } catch (_) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Upload Failed'),
            content: const Text('Could not upload logo. Please try again.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _fieldErrors.clear();
    });
    final updated = widget.initial.copyWith(
      name: _name.text.trim(),
      siteName: _siteName.text.trim(),
      address: _address.text.trim(),
      city: _city.text.trim(),
      state: _state.text.trim(),
      zip: _zip.text.trim(),
    );
    try {
      await ref
          .read(bandSettingsProvider(widget.bandId).notifier)
          .updateDetail(updated);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Surface validation errors if the server returned field-level messages.
      // DioException bodies with 422 status contain an 'errors' map.
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Save Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController controller,
      {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: CupertinoColors.secondaryLabel)),
          const SizedBox(height: 4),
          CupertinoTextField(controller: controller, keyboardType: keyboardType),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Edit Band Info'),
        trailing: _saving
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _save,
                child: const Text('Save'),
              ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Logo
            Center(
              child: GestureDetector(
                onTap: _uploadingLogo ? null : _pickLogo,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundImage: _logoUrl != null
                          ? NetworkImage(_logoUrl!)
                          : null,
                      child: _logoUrl == null
                          ? const Icon(CupertinoIcons.camera, size: 32)
                          : null,
                    ),
                    if (_uploadingLogo)
                      const CupertinoActivityIndicator(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _field('Band Name', _name),
            _field('Page URL', _siteName),
            _field('Street Address', _address),
            _field('City', _city),
            _field('State', _state),
            _field('Zip', _zip, keyboardType: TextInputType.number),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze for errors**

```bash
flutter analyze lib/features/band_settings/screens/band_info_edit_screen.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/band_settings/screens/band_info_edit_screen.dart
git commit -m "feat: add BandInfoEditScreen with logo upload and field editing"
```

---

## Task 9: BandSettingsScreen (main screen)

**Files:**
- Create: `lib/features/band_settings/screens/band_settings_screen.dart`

- [ ] **Step 1: Create the screen**

Create `lib/features/band_settings/screens/band_settings_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/band_invitation.dart';
import '../data/models/band_member.dart';
import '../providers/band_settings_provider.dart';
import 'band_info_edit_screen.dart';
import 'member_permissions_screen.dart';
import 'widgets/invite_section.dart';

class BandSettingsScreen extends ConsumerWidget {
  const BandSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandId = ref.watch(selectedBandProvider).value;
    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Band Settings')),
        child: Center(child: Text('No band selected.')),
      );
    }

    final settingsAsync = ref.watch(bandSettingsProvider(bandId));

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
          middle: Text('Band Settings')),
      child: SafeArea(
        child: settingsAsync.when(
          loading: () =>
              const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (settings) => ListView(
            children: [
              // Section 1 — Band Info
              CupertinoListSection.insetGrouped(
                header: const Text('Band Info'),
                children: [
                  CupertinoListTile(
                    leading: settings.detail.logoUrl != null
                        ? CircleAvatar(
                            backgroundImage:
                                NetworkImage(settings.detail.logoUrl!),
                            radius: 18,
                          )
                        : const CircleAvatar(
                            radius: 18,
                            child: Icon(CupertinoIcons.music_note, size: 16),
                          ),
                    title: Text(settings.detail.name),
                    subtitle: Text(settings.detail.siteName),
                    trailing: const Icon(CupertinoIcons.chevron_right,
                        size: 14),
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => BandInfoEditScreen(
                          bandId: bandId,
                          initial: settings.detail,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Section 2 — Members
              CupertinoListSection.insetGrouped(
                header: const Text('Members'),
                children: [
                  for (final member in settings.members)
                    _MemberRow(
                      member: member,
                      bandId: bandId,
                    ),
                ],
              ),

              // Section 3 — Invitations
              if (settings.invitations.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  header: const Text('Pending Invitations'),
                  children: [
                    for (final invite in settings.invitations)
                      _InvitationRow(
                        invite: invite,
                        bandId: bandId,
                      ),
                  ],
                ),

              // Section 4 — Invite
              InviteSection(bandId: bandId),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Member row with swipe-to-delete ──────────────────────────────────────────

class _MemberRow extends ConsumerWidget {
  const _MemberRow({required this.member, required this.bandId});

  final BandMember member;
  final int bandId;

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.name} from the band?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(bandSettingsProvider(bandId).notifier)
          .removeMember(bandId: bandId, userId: member.id);
    } catch (_) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to remove member.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(member.id),
      direction: member.isOwner
          ? DismissDirection.none
          : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _confirmRemove(context, ref);
        return false; // State update handled by notifier
      },
      background: Container(
        color: CupertinoColors.destructiveRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      child: CupertinoListTile(
        leading: CircleAvatar(
          child: Text(member.name.isNotEmpty ? member.name[0].toUpperCase() : '?'),
        ),
        title: Text(member.name),
        subtitle: Text(member.isOwner ? 'Owner' : 'Member'),
        trailing: const Icon(CupertinoIcons.chevron_right, size: 14),
        onTap: () => Navigator.of(context).push(
          CupertinoPageRoute<void>(
            builder: (_) => MemberPermissionsScreen(
              bandId: bandId,
              member: member,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Invitation row with swipe-to-delete ──────────────────────────────────────

class _InvitationRow extends ConsumerWidget {
  const _InvitationRow({required this.invite, required this.bandId});

  final BandInvitation invite;
  final int bandId;

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Revoke Invitation'),
        content: Text('Revoke invite to ${invite.email}?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(bandSettingsProvider(bandId).notifier)
          .revokeInvitation(bandId: bandId, invitationId: invite.id);
    } catch (_) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to revoke invitation.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(invite.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _confirmRevoke(context, ref);
        return false;
      },
      background: Container(
        color: CupertinoColors.destructiveRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      child: CupertinoListTile(
        leading: const Icon(CupertinoIcons.envelope),
        title: Text(invite.email),
        subtitle: Text(
            invite.inviteType == 'owner' ? 'Owner invite' : 'Member invite'),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze for errors**

```bash
flutter analyze lib/features/band_settings/screens/band_settings_screen.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/band_settings/screens/band_settings_screen.dart
git commit -m "feat: add BandSettingsScreen with members, invitations, and invite sections"
```

---

## Task 10: Wire router and More screen

**Files:**
- Modify: `lib/core/config/router.dart`
- Modify: `lib/features/more/screens/more_screen.dart`

- [ ] **Step 1: Add /band-settings route to router**

In `lib/core/config/router.dart`:

1. Add the import at the top with other feature imports:
```dart
import '../../features/band_settings/screens/band_settings_screen.dart';
```

2. Inside the `ShellRoute` routes list (alongside `/more`, `/finances`, etc.), add:
```dart
GoRoute(
  path: '/band-settings',
  builder: (_, __) => const BandSettingsScreen(),
),
```

- [ ] **Step 2: Add owner-only Band Settings tile in More screen**

Replace the entire `MoreScreen` class body in `lib/features/more/screens/more_screen.dart` with:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/nav_row.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider).value;
    final bandId = ref.watch(selectedBandProvider).value;

    bool isOwner = false;
    if (authState is AuthAuthenticated && bandId != null) {
      isOwner = authState.bands
          .where((b) => b.id == bandId)
          .any((b) => b.isOwner);
    }

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('More')),
      child: ListView(
        children: [
          const SizedBox(height: 16),
          NavRow(
            title: 'Finances',
            leading: Icon(
              CupertinoIcons.money_dollar_circle,
              size: 22,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            onTap: () => context.push('/finances'),
          ),
          NavRow(
            title: 'Rehearsals',
            leading: Icon(
              CupertinoIcons.person_2,
              size: 22,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            onTap: () => context.push('/rehearsals'),
          ),
          NavRow(
            title: 'Media',
            leading: Icon(
              CupertinoIcons.photo_on_rectangle,
              size: 22,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            onTap: () => context.push('/media'),
          ),
          if (isOwner)
            NavRow(
              title: 'Band Settings',
              leading: Icon(
                CupertinoIcons.settings,
                size: 22,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              onTap: () => context.push('/band-settings'),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Analyze both files**

```bash
flutter analyze lib/core/config/router.dart lib/features/more/screens/more_screen.dart
```

Expected: no issues.

- [ ] **Step 4: Run all tests**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/config/router.dart lib/features/more/screens/more_screen.dart
git commit -m "feat: wire /band-settings route and add owner-only tile to More screen"
```

---

## Task 11: End-to-end smoke test (manual)

This task verifies the feature works against the real backend. Run the app with the backend running locally.

- [ ] **Step 1: Run the app**

```bash
flutter run -d linux
```

Or for web:
```bash
flutter run -d chrome --dart-define=BASE_URL=http://localhost:8715
```

- [ ] **Step 2: Log in as a band owner**

Log in with an account that is a band owner. Confirm the More screen shows "Band Settings".

- [ ] **Step 3: Verify Band Info section**

Tap "Band Settings" → confirm band name and site_name load. Tap to edit → change the name → Save → confirm the updated name shows in the list.

- [ ] **Step 4: Verify Members section**

Confirm members list loads with correct owner/member badges. Tap a member → confirm 18 permission toggles show. Toggle one → confirm it persists (re-enter the screen). Swipe to delete a non-owner member → confirm they disappear.

- [ ] **Step 5: Verify Invitations section**

Confirm pending invitations load. Swipe to revoke → confirm it disappears.

- [ ] **Step 6: Verify Invite section**

Tap "Invite a Member" → expand → enter an email → Send → confirm it appears in the invitations list. Tap "Show QR Code" → confirm QR modal appears.

- [ ] **Step 7: Verify non-owners cannot access settings**

Log in as a band member (non-owner). Confirm "Band Settings" tile does not appear in the More screen.
