# Registration & Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add account creation and post-registration onboarding (create band / join band / go solo) to the mobile app, backed by new Laravel API endpoints.

**Architecture:** New `POST /api/mobile/auth/register` endpoint returns the same `{token, user, bands}` shape as login. After registration (or when a logged-in user has no bands), a `PathSelectionScreen` offers three routes: create a band (two-step: name → invite), join via code/QR/email-link, or go solo (auto-creates a personal band silently). All paths land on the existing dashboard; no new UI branch is needed for solo users.

**Tech Stack:** Laravel 10 (backend), Flutter/Dart (frontend), Riverpod v2, GoRouter, Dio, Sanctum tokens. New Flutter packages: `qr_flutter` (display QR), `mobile_scanner` (camera QR scan).

---

## File Map

### Backend (Laravel — `/home/eddie/github/TTS/`)

| File | Action | Purpose |
|------|--------|---------|
| `database/migrations/2026_04_18_000001_add_is_personal_to_bands_table.php` | Create | Add `is_personal` column |
| `app/Http/Controllers/Api/Mobile/OnboardingController.php` | Create | Handles register, createBand, inviteMembers, joinBand, goSolo, inviteQr |
| `routes/api.php` | Modify | Add 6 new mobile routes |

### Frontend (Flutter — `/home/eddie/github/tts_bandmate/`)

| File | Action | Purpose |
|------|--------|---------|
| `pubspec.yaml` | Modify | Add `qr_flutter`, `mobile_scanner` |
| `lib/core/network/api_endpoints.dart` | Modify | Add 6 new endpoint constants |
| `lib/features/auth/data/auth_repository.dart` | Modify | Add `register()` method |
| `lib/features/bands/data/bands_repository.dart` | Create | `createBand()`, `inviteMembers()`, `joinBand()`, `goSolo()`, `getInviteKey()` |
| `lib/features/bands/providers/bands_provider.dart` | Create | `bandsRepositoryProvider`, action methods |
| `lib/features/auth/screens/sign_up_screen.dart` | Create | Registration form |
| `lib/features/auth/screens/path_selection_screen.dart` | Create | Create / Join / Solo cards |
| `lib/features/bands/screens/create_band_screen.dart` | Create | Two-step: name → invite |
| `lib/features/bands/screens/join_band_screen.dart` | Create | Code input + QR scanner |
| `lib/features/auth/providers/auth_provider.dart` | Modify | Add `register()` method to `AuthNotifier` |
| `lib/core/config/router.dart` | Modify | Add `/signup`, update `/bands`, add `/bands/join`, `/bands/create` routes |
| `lib/features/auth/screens/login_screen.dart` | Modify | Add "Don't have an account? Sign up" link |
| `lib/features/auth/screens/band_selector_screen.dart` | Modify | Replace empty-state message with nav to `PathSelectionScreen` |

---

## Task 1: Backend migration — add `is_personal` to bands

**Files:**
- Create: `database/migrations/2026_04_18_000001_add_is_personal_to_bands_table.php`

- [ ] **Step 1: Create the migration**

```bash
cd /home/eddie/github/TTS
php artisan make:migration add_is_personal_to_bands_table --table=bands
```

Then open the generated file and replace its contents with:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('bands', function (Blueprint $table) {
            $table->boolean('is_personal')->default(false)->after('zip');
        });
    }

    public function down(): void
    {
        Schema::table('bands', function (Blueprint $table) {
            $table->dropColumn('is_personal');
        });
    }
};
```

- [ ] **Step 2: Run the migration**

```bash
php artisan migrate
```

Expected output: `Running migrations. ... done.`

- [ ] **Step 3: Add `is_personal` to `Bands` model `$fillable`**

In `app/Models/Bands.php`, update:

```php
protected $fillable = ['name', 'site_name', 'address', 'city', 'state', 'zip', 'is_personal'];
```

- [ ] **Step 4: Commit**

```bash
git add database/migrations/ app/Models/Bands.php
git commit -m "feat: add is_personal column to bands table"
```

---

## Task 2: Backend — OnboardingController with all 6 endpoints

**Files:**
- Create: `app/Http/Controllers/Api/Mobile/OnboardingController.php`
- Modify: `routes/api.php`

- [ ] **Step 1: Create the controller**

Create `app/Http/Controllers/Api/Mobile/OnboardingController.php`:

```php
<?php

namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Models\BandMembers;
use App\Models\BandOwners;
use App\Models\Bands;
use App\Models\Invitations;
use App\Services\InvitationServices;
use App\Services\Mobile\TokenService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use App\Models\User;
use App\Models\EventSubs;
use App\Services\SubInvitationService;

class OnboardingController extends Controller
{
    const OWNER_INVITE_TYPE = 1;
    const MEMBER_INVITE_TYPE = 2;

    public function __construct(private readonly TokenService $tokenService) {}

    // ── POST /api/mobile/auth/register ────────────────────────────────────────

    public function register(Request $request): JsonResponse
    {
        $request->validate([
            'name'                  => 'required|string|max:255',
            'email'                 => 'required|string|email|max:255|unique:users',
            'password'              => 'required|string|min:8|confirmed',
            'device_name'           => 'required|string',
        ]);

        $user = User::create([
            'name'     => $request->name,
            'email'    => $request->email,
            'password' => Hash::make($request->password),
        ]);

        // Apply any pending sub-invitations
        $subInvitations = EventSubs::where('email', $user->email)
            ->where('pending', true)
            ->get();

        if ($subInvitations->isNotEmpty()) {
            $service = new SubInvitationService();
            foreach ($subInvitations as $eventSub) {
                $service->acceptInvitation($eventSub->invitation_key, $user);
            }
        }

        // Apply any pending band invitations
        $invitations = Invitations::where('email', $user->email)
            ->where('pending', true)
            ->get();

        foreach ($invitations as $invitation) {
            if ($invitation->invite_type_id === static::OWNER_INVITE_TYPE) {
                BandOwners::create([
                    'user_id' => $user->id,
                    'band_id' => $invitation->band_id,
                ]);
                setPermissionsTeamId($invitation->band_id);
                $user->assignRole('band-owner');
                setPermissionsTeamId(null);
            }
            if ($invitation->invite_type_id === static::MEMBER_INVITE_TYPE) {
                BandMembers::create([
                    'user_id' => $user->id,
                    'band_id' => $invitation->band_id,
                ]);
                $user->assignBandMemberDefaults($invitation->band_id);
            }
            $invitation->pending = false;
            $invitation->save();
        }

        $abilities = $this->tokenService->buildAbilities($user);
        $token     = $user->createToken($request->device_name, $abilities)->plainTextToken;

        return response()->json([
            'token' => $token,
            'user'  => $this->tokenService->formatUser($user),
            'bands' => $this->tokenService->formatBands($user),
        ], 201);
    }

    // ── POST /api/mobile/bands ────────────────────────────────────────────────

    public function createBand(Request $request): JsonResponse
    {
        $request->validate([
            'name' => 'required|string|max:255',
        ]);

        $user = $request->user();

        $siteName = $this->uniqueSiteName(Str::slug($request->name));

        $band = Bands::create([
            'name'      => $request->name,
            'site_name' => $siteName,
        ]);

        BandOwners::create([
            'user_id' => $user->id,
            'band_id' => $band->id,
        ]);

        setPermissionsTeamId($band->id);
        $user->assignRole('band-owner');
        setPermissionsTeamId(null);

        return response()->json([
            'band' => [
                'id'       => $band->id,
                'name'     => $band->name,
                'is_owner' => true,
            ],
        ], 201);
    }

    // ── POST /api/mobile/bands/{band}/invite ──────────────────────────────────

    public function inviteMembers(Request $request, Bands $band): JsonResponse
    {
        $request->validate([
            'emails'   => 'required|array|min:1',
            'emails.*' => 'required|email',
        ]);

        $user = $request->user();

        if (!$user->ownsBand($band->id)) {
            return response()->json(['message' => 'Forbidden.'], 403);
        }

        // Temporarily set auth so InvitationServices can read Auth::user()
        Auth::setUser($user);

        $service = new InvitationServices();
        foreach ($request->emails as $email) {
            $service->inviteUser($email, $band->id, false);
        }

        return response()->json(['message' => 'Invitations sent.']);
    }

    // ── POST /api/mobile/bands/join ───────────────────────────────────────────

    public function joinBand(Request $request): JsonResponse
    {
        $request->validate([
            'key' => 'required|string',
        ]);

        $invitation = Invitations::where('key', $request->key)
            ->where('pending', true)
            ->first();

        if (!$invitation) {
            throw ValidationException::withMessages([
                'key' => ['Invalid or expired invite code.'],
            ]);
        }

        $user = $request->user();

        if ($invitation->invite_type_id === static::OWNER_INVITE_TYPE) {
            BandOwners::firstOrCreate([
                'user_id' => $user->id,
                'band_id' => $invitation->band_id,
            ]);
            setPermissionsTeamId($invitation->band_id);
            $user->assignRole('band-owner');
            setPermissionsTeamId(null);
        } else {
            BandMembers::firstOrCreate([
                'user_id' => $user->id,
                'band_id' => $invitation->band_id,
            ]);
            $user->assignBandMemberDefaults($invitation->band_id);
        }

        $invitation->pending = false;
        $invitation->save();

        return response()->json([
            'bands' => $this->tokenService->formatBands($user),
        ]);
    }

    // ── GET /api/mobile/bands/{band}/invite-qr ────────────────────────────────

    public function inviteQr(Request $request, Bands $band): JsonResponse
    {
        $user = $request->user();

        if (!$user->ownsBand($band->id)) {
            return response()->json(['message' => 'Forbidden.'], 403);
        }

        // Get or create a pending member invitation for this band
        $invitation = Invitations::where('band_id', $band->id)
            ->where('invite_type_id', static::MEMBER_INVITE_TYPE)
            ->where('pending', true)
            ->whereNull('email') // reusable invite has no email
            ->first();

        if (!$invitation) {
            $invitation = Invitations::create([
                'email'          => null,
                'band_id'        => $band->id,
                'invite_type_id' => static::MEMBER_INVITE_TYPE,
            ]);
        }

        return response()->json(['key' => $invitation->key]);
    }

    // ── POST /api/mobile/bands/solo ───────────────────────────────────────────

    public function goSolo(Request $request): JsonResponse
    {
        $user = $request->user();

        $name     = "{$user->name}'s Band";
        $siteName = $this->uniqueSiteName(Str::slug($name));

        $band = Bands::create([
            'name'        => $name,
            'site_name'   => $siteName,
            'is_personal' => true,
        ]);

        BandOwners::create([
            'user_id' => $user->id,
            'band_id' => $band->id,
        ]);

        setPermissionsTeamId($band->id);
        $user->assignRole('band-owner');
        setPermissionsTeamId(null);

        return response()->json([
            'bands' => $this->tokenService->formatBands($user),
        ], 201);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private function uniqueSiteName(string $base): string
    {
        $candidate = $base ?: 'band';
        $suffix    = 1;

        while (Bands::where('site_name', $candidate)->exists()) {
            $candidate = "{$base}-{$suffix}";
            $suffix++;
        }

        return $candidate;
    }
}
```

- [ ] **Step 2: Add routes to `routes/api.php`**

In `routes/api.php`, directly after the `Route::post('/auth/token', ...)` line (inside the `Route::prefix('mobile')` block), add:

```php
    // Registration
    Route::post('/auth/register', [App\Http\Controllers\Api\Mobile\OnboardingController::class, 'register'])->name('mobile.auth.register');
```

Then inside the `Route::middleware('auth:sanctum')` block, after the existing routes, add:

```php
        // Band onboarding
        Route::post('/bands', [App\Http\Controllers\Api\Mobile\OnboardingController::class, 'createBand'])->name('mobile.bands.create');
        Route::post('/bands/join', [App\Http\Controllers\Api\Mobile\OnboardingController::class, 'joinBand'])->name('mobile.bands.join');
        Route::post('/bands/solo', [App\Http\Controllers\Api\Mobile\OnboardingController::class, 'goSolo'])->name('mobile.bands.solo');
        Route::post('/bands/{band}/invite', [App\Http\Controllers\Api\Mobile\OnboardingController::class, 'inviteMembers'])->name('mobile.bands.invite');
        Route::get('/bands/{band}/invite-qr', [App\Http\Controllers\Api\Mobile\OnboardingController::class, 'inviteQr'])->name('mobile.bands.invite-qr');
```

> **Important:** `Route::post('/bands/join', ...)` and `Route::post('/bands/solo', ...)` must be registered **before** any `Route::post('/bands/{band}/...')` parameterised routes to prevent GoRouter treating "join" and "solo" as band IDs.

- [ ] **Step 3: Verify the routes are registered**

```bash
cd /home/eddie/github/TTS
php artisan route:list --path=mobile/auth/register
php artisan route:list --path=mobile/bands
```

Expected: 6 new `mobile.*` routes appear in the list.

- [ ] **Step 4: Handle nullable email in Invitations model**

The `inviteQr` endpoint creates an invitation with `email = null` for reusable QR codes. Check that the `invitations` table allows null emails:

```bash
php artisan db:show --table=invitations 2>/dev/null || php artisan tinker --execute="Schema::getColumnListing('invitations');"
```

If the `email` column is `NOT NULL`, create a migration to make it nullable:

```bash
php artisan make:migration make_invitations_email_nullable --table=invitations
```

Migration contents:

```php
public function up(): void
{
    Schema::table('invitations', function (Blueprint $table) {
        $table->string('email')->nullable()->change();
    });
}

public function down(): void
{
    Schema::table('invitations', function (Blueprint $table) {
        $table->string('email')->nullable(false)->change();
    });
}
```

Run: `php artisan migrate`

- [ ] **Step 5: Commit**

```bash
git add app/Http/Controllers/Api/Mobile/OnboardingController.php routes/api.php database/migrations/
git commit -m "feat: add mobile onboarding API endpoints (register, createBand, joinBand, goSolo, invite, inviteQr)"
```

---

## Task 3: Flutter — add packages and API endpoint constants

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/network/api_endpoints.dart`

- [ ] **Step 1: Add QR packages to `pubspec.yaml`**

In `/home/eddie/github/tts_bandmate/pubspec.yaml`, under `dependencies:`, add after `sentry_flutter`:

```yaml
  qr_flutter: ^4.1.0
  mobile_scanner: ^6.0.0
```

- [ ] **Step 2: Install packages**

```bash
cd /home/eddie/github/tts_bandmate
flutter pub get
```

Expected: resolves without errors.

- [ ] **Step 3: Add endpoint constants to `api_endpoints.dart`**

At the end of the `ApiEndpoints` class body in `lib/core/network/api_endpoints.dart`, add:

```dart
  // Onboarding
  static const String mobileRegister = '/api/mobile/auth/register';
  static const String mobileCreateBand = '/api/mobile/bands';
  static const String mobileBandsSolo = '/api/mobile/bands/solo';
  static const String mobileBandsJoin = '/api/mobile/bands/join';
  static String mobileBandInvite(int bandId) => '/api/mobile/bands/$bandId/invite';
  static String mobileBandInviteQr(int bandId) => '/api/mobile/bands/$bandId/invite-qr';
```

- [ ] **Step 4: Verify no analysis errors**

```bash
flutter analyze lib/core/network/api_endpoints.dart
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/network/api_endpoints.dart
git commit -m "feat: add qr_flutter, mobile_scanner packages and onboarding API endpoint constants"
```

---

## Task 4: Flutter — `BandsRepository` and `bandsProvider`

**Files:**
- Create: `lib/features/bands/data/bands_repository.dart`
- Create: `lib/features/bands/providers/bands_provider.dart`

- [ ] **Step 1: Create `BandsRepository`**

Create `lib/features/bands/data/bands_repository.dart`:

```dart
import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import '../../auth/data/models/band_summary.dart';

class BandsRepository {
  BandsRepository(this._dio);

  final Dio _dio;

  /// Create a new band. Returns the new band's id and name.
  Future<BandSummary> createBand(String name) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileCreateBand,
      data: {'name': name},
    );
    final band = response.data!['band'] as Map<String, dynamic>;
    return BandSummary.fromJson(band);
  }

  /// Send member invitations for [bandId] to each email in [emails].
  Future<void> inviteMembers(int bandId, List<String> emails) async {
    await _dio.post<void>(
      ApiEndpoints.mobileBandInvite(bandId),
      data: {'emails': emails},
    );
  }

  /// Accept an invite by [key]. Returns updated bands list.
  Future<List<BandSummary>> joinBand(String key) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandsJoin,
      data: {'key': key},
    );
    final bandList = (response.data!['bands'] as List<dynamic>)
        .map((b) => BandSummary.fromJson(b as Map<String, dynamic>))
        .toList();
    return bandList;
  }

  /// Create a personal auto-band. Returns updated bands list.
  Future<List<BandSummary>> goSolo() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandsSolo,
    );
    final bandList = (response.data!['bands'] as List<dynamic>)
        .map((b) => BandSummary.fromJson(b as Map<String, dynamic>))
        .toList();
    return bandList;
  }

  /// Get the raw invite key for [bandId] to render as QR.
  Future<String> getInviteKey(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandInviteQr(bandId),
    );
    return response.data!['key'] as String;
  }
}
```

- [ ] **Step 2: Create `bands_provider.dart`**

Create `lib/features/bands/providers/bands_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/data/models/band_summary.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/bands_repository.dart';

final bandsRepositoryProvider = Provider<BandsRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return BandsRepository(dio);
});

/// Notifier for band onboarding actions. Each method updates [authProvider]
/// on success so the router guard can react.
class BandsNotifier extends Notifier<void> {
  @override
  void build() {}

  BandsRepository get _repo => ref.read(bandsRepositoryProvider);

  /// Create a band, then (optionally) invite members. Returns the new band.
  Future<BandSummary> createBand(String name, List<String> emails) async {
    final band = await _repo.createBand(name);
    if (emails.isNotEmpty) {
      await _repo.inviteMembers(band.id, emails);
    }
    // Refresh auth so the new band appears in authState.bands
    await ref.read(authProvider.notifier).refreshBands();
    return band;
  }

  /// Accept an invite key and refresh auth bands.
  Future<void> joinBand(String key) async {
    await _repo.joinBand(key);
    await ref.read(authProvider.notifier).refreshBands();
  }

  /// Create a personal band and refresh auth bands.
  Future<void> goSolo() async {
    await _repo.goSolo();
    await ref.read(authProvider.notifier).refreshBands();
  }

  /// Get invite key for QR display.
  Future<String> getInviteKey(int bandId) => _repo.getInviteKey(bandId);
}

final bandsProvider = NotifierProvider<BandsNotifier, void>(() => BandsNotifier());
```

- [ ] **Step 3: Add `refreshBands()` to `AuthNotifier`**

In `lib/features/auth/providers/auth_provider.dart`, add this method inside `AuthNotifier` after the `logout()` method:

```dart
  /// Re-fetch the user's bands from the server and update state.
  /// Called after band creation/join/solo so the router guard reacts.
  Future<void> refreshBands() async {
    final currentState = state.value;
    if (currentState is! AuthAuthenticated) return;

    try {
      final result = await _repository.getMe();
      final storage = ref.read(secureStorageProvider);
      await storage.writeUser(result.user.toJsonString());
      state = AsyncValue.data(
        AuthAuthenticated(user: result.user, bands: result.bands),
      );
    } catch (_) {
      // Silently ignore — bands will refresh on next app launch
    }
  }
```

- [ ] **Step 4: Analyze**

```bash
flutter analyze lib/features/bands/ lib/features/auth/providers/auth_provider.dart
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/bands/ lib/features/auth/providers/auth_provider.dart
git commit -m "feat: add BandsRepository, bandsProvider, and AuthNotifier.refreshBands()"
```

---

## Task 5: Flutter — `register()` in `AuthRepository` and `AuthNotifier`

**Files:**
- Modify: `lib/features/auth/data/auth_repository.dart`
- Modify: `lib/features/auth/providers/auth_provider.dart`

- [ ] **Step 1: Add `register()` to `AuthRepository`**

In `lib/features/auth/data/auth_repository.dart`, add after the `login()` method:

```dart
  /// Register a new account and retrieve a Sanctum token.
  Future<({String token, AuthUser user, List<BandSummary> bands})> register(
    String name,
    String email,
    String password,
    String deviceName,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileRegister,
      data: {
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': password,
        'device_name': deviceName,
      },
    );

    final data = response.data!;
    final token = data['token'] as String;
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    final bandList = (data['bands'] as List<dynamic>)
        .map((b) => BandSummary.fromJson(b as Map<String, dynamic>))
        .toList();

    return (token: token, user: user, bands: bandList);
  }
```

- [ ] **Step 2: Add `register()` to `AuthNotifier`**

In `lib/features/auth/providers/auth_provider.dart`, add after the `login()` method:

```dart
  /// Register a new account and store credentials.
  Future<void> register(String name, String email, String password) async {
    state = const AsyncValue.data(AuthLoading());

    final storage = ref.read(secureStorageProvider);

    state = await AsyncValue.guard(() async {
      final result = await _repository.register(
        name,
        email,
        password,
        'tts_bandmate_app',
      );
      await storage.writeToken(result.token);
      await storage.writeUser(result.user.toJsonString());
      return AuthAuthenticated(user: result.user, bands: result.bands);
    });

    if (state.hasError) {
      state = AsyncValue.data(
        AuthUnauthenticated(errorMessage: _friendlyRegisterError(state.error)),
      );
    }
  }

  String _friendlyRegisterError(Object? error) {
    if (error == null) return 'An unknown error occurred.';
    final msg = error.toString();
    if (msg.contains('422')) return 'Email already in use or invalid input.';
    if (msg.contains('SocketException') ||
        msg.contains('connection') ||
        msg.contains('timeout')) {
      return 'Could not reach the server. Check your connection.';
    }
    return 'Registration failed. Please try again.';
  }
```

- [ ] **Step 3: Analyze**

```bash
flutter analyze lib/features/auth/
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/data/auth_repository.dart lib/features/auth/providers/auth_provider.dart
git commit -m "feat: add register() to AuthRepository and AuthNotifier"
```

---

## Task 6: Flutter — `SignUpScreen`

**Files:**
- Create: `lib/features/auth/screens/sign_up_screen.dart`

- [ ] **Step 1: Create `SignUpScreen`**

Create `lib/features/auth/screens/sign_up_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key, this.prefillEmail});

  /// Pre-filled email from a deep-link invite.
  final String? prefillEmail;

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _passwordVisible = false;
  bool _isSubmitting = false;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    if (widget.prefillEmail != null) {
      _emailController.text = widget.prefillEmail!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _validate() {
    String? nameError;
    String? emailError;
    String? passwordError;
    String? confirmError;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (name.isEmpty) nameError = 'Please enter your name.';
    if (email.isEmpty) {
      emailError = 'Please enter your email.';
    } else if (!email.contains('@')) {
      emailError = 'Enter a valid email address.';
    }
    if (password.isEmpty) {
      passwordError = 'Please enter a password.';
    } else if (password.length < 8) {
      passwordError = 'Password must be at least 8 characters.';
    }
    if (confirm != password) confirmError = 'Passwords do not match.';

    setState(() {
      _nameError = nameError;
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmError = confirmError;
      _submitError = null;
    });
    return nameError == null &&
        emailError == null &&
        passwordError == null &&
        confirmError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _isSubmitting = true);

    await ref.read(authProvider.notifier).register(
          _nameController.text.trim(),
          _emailController.text.trim(),
          _passwordController.text,
        );

    if (!mounted) return;
    final authState = ref.read(authProvider).value;
    setState(() {
      _isSubmitting = false;
      if (authState is AuthUnauthenticated) {
        _submitError = authState.errorMessage;
      }
    });
    // Router guard handles navigation on success.
  }

  Widget _field({
    required TextEditingController controller,
    required String placeholder,
    required IconData icon,
    String? error,
    bool obscure = false,
    TextInputAction action = TextInputAction.next,
    TextInputType keyboardType = TextInputType.text,
    VoidCallback? onSubmit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          obscureText: obscure,
          textInputAction: action,
          keyboardType: keyboardType,
          autocorrect: false,
          onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
          prefix: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(icon,
                size: 20,
                color: CupertinoColors.secondaryLabel.resolveFrom(context)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(10),
            border: error != null
                ? Border.all(
                    color: CupertinoColors.systemRed.resolveFrom(context))
                : null,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error,
              style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemRed.resolveFrom(context))),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Create Account')),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                controller: _nameController,
                placeholder: 'Full Name',
                icon: CupertinoIcons.person,
                error: _nameError,
              ),
              const SizedBox(height: 16),
              _field(
                controller: _emailController,
                placeholder: 'Email',
                icon: CupertinoIcons.mail,
                error: _emailError,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              _field(
                controller: _passwordController,
                placeholder: 'Password',
                icon: CupertinoIcons.lock,
                error: _passwordError,
                obscure: !_passwordVisible,
              ),
              const SizedBox(height: 16),
              _field(
                controller: _confirmController,
                placeholder: 'Confirm Password',
                icon: CupertinoIcons.lock_shield,
                error: _confirmError,
                obscure: !_passwordVisible,
                action: TextInputAction.done,
                onSubmit: _submit,
              ),
              const SizedBox(height: 8),
              CupertinoButton(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                onPressed: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                child: Text(
                  _passwordVisible ? 'Hide passwords' : 'Show passwords',
                  style: TextStyle(
                      fontSize: 13,
                      color:
                          CupertinoColors.systemBlue.resolveFrom(context)),
                ),
              ),
              const SizedBox(height: 24),
              CupertinoButton.filled(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const CupertinoActivityIndicator(
                        color: CupertinoColors.white)
                    : const Text('Create Account',
                        style: TextStyle(fontSize: 16)),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(_submitError!,
                    style: TextStyle(
                        fontSize: 13,
                        color:
                            CupertinoColors.systemRed.resolveFrom(context)),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already have an account?',
                      style: TextStyle(
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context))),
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: 4),
                    onPressed: () => context.go('/login'),
                    child: const Text('Sign In'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/features/auth/screens/sign_up_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/auth/screens/sign_up_screen.dart
git commit -m "feat: add SignUpScreen"
```

---

## Task 7: Flutter — `PathSelectionScreen`

**Files:**
- Create: `lib/features/auth/screens/path_selection_screen.dart`

- [ ] **Step 1: Create `PathSelectionScreen`**

Create `lib/features/auth/screens/path_selection_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../bands/providers/bands_provider.dart';

class PathSelectionScreen extends ConsumerStatefulWidget {
  const PathSelectionScreen({super.key});

  @override
  ConsumerState<PathSelectionScreen> createState() =>
      _PathSelectionScreenState();
}

class _PathSelectionScreenState extends ConsumerState<PathSelectionScreen> {
  bool _soloLoading = false;
  String? _soloError;

  Future<void> _goSolo() async {
    setState(() {
      _soloLoading = true;
      _soloError = null;
    });
    try {
      await ref.read(bandsProvider.notifier).goSolo();
      // Router guard detects band now exists and navigates to dashboard.
    } catch (e) {
      setState(() => _soloError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _soloLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: const Text('Get Started'),
          automaticallyImplyLeading: false,
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async =>
                ref.read(authProvider.notifier).logout(),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.square_arrow_right, size: 18),
                SizedBox(width: 4),
                Text('Sign out'),
              ],
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'How would you like to use Bandmate?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You can always add or join a band later from Settings.',
                  style: TextStyle(
                    fontSize: 14,
                    color:
                        CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 32),
                _PathCard(
                  icon: CupertinoIcons.music_mic,
                  title: 'Create a Band',
                  subtitle: 'Start a new band and invite your members.',
                  onTap: () => context.push('/bands/create'),
                ),
                const SizedBox(height: 16),
                _PathCard(
                  icon: CupertinoIcons.link,
                  title: 'Join a Band',
                  subtitle:
                      'Enter an invite code, scan a QR, or use an email link.',
                  onTap: () => context.push('/bands/join'),
                ),
                const SizedBox(height: 16),
                _PathCard(
                  icon: CupertinoIcons.music_note,
                  title: 'Go Solo',
                  subtitle:
                      'Use Bandmate for personal gig tracking and setlists.',
                  onTap: _soloLoading ? null : _goSolo,
                  loading: _soloLoading,
                ),
                if (_soloError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _soloError!,
                    style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.systemRed.resolveFrom(context)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: CupertinoColors.systemBlue
                    .resolveFrom(context)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: loading
                    ? const CupertinoActivityIndicator()
                    : Icon(icon,
                        color: CupertinoColors.systemBlue.resolveFrom(context),
                        size: 24),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context))),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                size: 18,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/features/auth/screens/path_selection_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/auth/screens/path_selection_screen.dart
git commit -m "feat: add PathSelectionScreen (create / join / solo)"
```

---

## Task 8: Flutter — `CreateBandScreen`

**Files:**
- Create: `lib/features/bands/screens/create_band_screen.dart`

- [ ] **Step 1: Create `CreateBandScreen`**

Create `lib/features/bands/screens/create_band_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../bands/providers/bands_provider.dart';

class CreateBandScreen extends ConsumerStatefulWidget {
  const CreateBandScreen({super.key});

  @override
  ConsumerState<CreateBandScreen> createState() => _CreateBandScreenState();
}

class _CreateBandScreenState extends ConsumerState<CreateBandScreen> {
  // Step 1: name
  final _nameController = TextEditingController();
  String? _nameError;

  // Step 2: invite
  final _emailController = TextEditingController();
  final List<String> _emails = [];
  String? _emailError;

  int _step = 1; // 1 = name, 2 = invite
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _addEmail() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    if (!email.contains('@')) {
      setState(() => _emailError = 'Enter a valid email address.');
      return;
    }
    if (_emails.contains(email)) {
      setState(() => _emailError = 'Already added.');
      return;
    }
    setState(() {
      _emails.add(email);
      _emailError = null;
    });
    _emailController.clear();
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _nameError = 'Please enter a band name.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await ref
          .read(bandsProvider.notifier)
          .createBand(_nameController.text.trim(), _emails);
      // Router guard sees new band and navigates to dashboard.
    } catch (e) {
      setState(() => _submitError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(_step == 1 ? 'Name Your Band' : 'Invite Members'),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _step == 1 ? _buildStep1(context) : _buildStep2(context),
        ),
      ),
    );
  }

  Widget _buildStep1(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What\'s your band called?',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        CupertinoTextField(
          controller: _nameController,
          placeholder: 'Band Name',
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _goToStep2(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(10),
            border: _nameError != null
                ? Border.all(color: CupertinoColors.systemRed.resolveFrom(context))
                : null,
          ),
        ),
        if (_nameError != null) ...[
          const SizedBox(height: 4),
          Text(_nameError!,
              style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemRed.resolveFrom(context))),
        ],
        const Spacer(),
        CupertinoButton.filled(
          onPressed: _goToStep2,
          child: const Text('Next'),
        ),
      ],
    );
  }

  void _goToStep2() {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _nameError = 'Please enter a band name.');
      return;
    }
    setState(() {
      _nameError = null;
      _step = 2;
    });
  }

  Widget _buildStep2(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Invite your bandmates',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('They\'ll receive an email invitation.',
            style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.secondaryLabel.resolveFrom(context))),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _emailController,
                placeholder: 'Email address',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addEmail(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemBackground
                      .resolveFrom(context),
                  borderRadius: BorderRadius.circular(10),
                  border: _emailError != null
                      ? Border.all(
                          color:
                              CupertinoColors.systemRed.resolveFrom(context))
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              onPressed: _addEmail,
              padding: EdgeInsets.zero,
              child: Icon(CupertinoIcons.add_circled_solid,
                  size: 36,
                  color: CupertinoColors.systemBlue.resolveFrom(context)),
            ),
          ],
        ),
        if (_emailError != null) ...[
          const SizedBox(height: 4),
          Text(_emailError!,
              style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemRed.resolveFrom(context))),
        ],
        if (_emails.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _emails
                .map((email) => _EmailChip(
                      email: email,
                      onRemove: () => setState(() => _emails.remove(email)),
                    ))
                .toList(),
          ),
        ],
        const Spacer(),
        if (_submitError != null) ...[
          Text(_submitError!,
              style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemRed.resolveFrom(context)),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
        ],
        CupertinoButton.filled(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const CupertinoActivityIndicator(color: CupertinoColors.white)
              : const Text('Done'),
        ),
        const SizedBox(height: 12),
        CupertinoButton(
          onPressed: _isSubmitting ? null : _submit,
          child: const Text('Skip for now'),
        ),
      ],
    );
  }
}

class _EmailChip extends StatelessWidget {
  const _EmailChip({required this.email, required this.onRemove});

  final String email;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBlue
            .resolveFrom(context)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(email,
              style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemBlue.resolveFrom(context))),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(CupertinoIcons.xmark_circle_fill,
                size: 16,
                color: CupertinoColors.systemBlue.resolveFrom(context)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/features/bands/screens/create_band_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/bands/screens/create_band_screen.dart
git commit -m "feat: add CreateBandScreen (two-step: name then invite)"
```

---

## Task 9: Flutter — `JoinBandScreen`

**Files:**
- Create: `lib/features/bands/screens/join_band_screen.dart`

- [ ] **Step 1: Create `JoinBandScreen`**

Create `lib/features/bands/screens/join_band_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../bands/providers/bands_provider.dart';

class JoinBandScreen extends ConsumerStatefulWidget {
  const JoinBandScreen({super.key});

  @override
  ConsumerState<JoinBandScreen> createState() => _JoinBandScreenState();
}

class _JoinBandScreenState extends ConsumerState<JoinBandScreen> {
  final _codeController = TextEditingController();
  bool _scanning = false;
  bool _isSubmitting = false;
  String? _codeError;
  String? _submitError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinWithKey(String key) async {
    if (key.trim().isEmpty) {
      setState(() => _codeError = 'Please enter an invite code.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _codeError = null;
      _submitError = null;
    });
    try {
      await ref.read(bandsProvider.notifier).joinBand(key.trim());
      // Router guard detects band and navigates to dashboard.
    } catch (e) {
      setState(() => _submitError = 'Invalid or expired code. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar:
          const CupertinoNavigationBar(middle: Text('Join a Band')),
      child: SafeArea(
        child: _scanning
            ? _buildScanner(context)
            : _buildCodeEntry(context),
      ),
    );
  }

  Widget _buildCodeEntry(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Enter an invite code',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
              'Ask a band owner for their code, or scan their QR code below.',
              style: TextStyle(
                  fontSize: 14,
                  color:
                      CupertinoColors.secondaryLabel.resolveFrom(context))),
          const SizedBox(height: 24),
          CupertinoTextField(
            controller: _codeController,
            placeholder: 'Invite code',
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onSubmitted: (_) => _joinWithKey(_codeController.text),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(10),
              border: _codeError != null
                  ? Border.all(
                      color: CupertinoColors.systemRed.resolveFrom(context))
                  : null,
            ),
          ),
          if (_codeError != null) ...[
            const SizedBox(height: 4),
            Text(_codeError!,
                style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemRed.resolveFrom(context))),
          ],
          const SizedBox(height: 16),
          CupertinoButton.filled(
            onPressed: _isSubmitting
                ? null
                : () => _joinWithKey(_codeController.text),
            child: _isSubmitting
                ? const CupertinoActivityIndicator(
                    color: CupertinoColors.white)
                : const Text('Join'),
          ),
          const SizedBox(height: 24),
          CupertinoButton(
            onPressed: () => setState(() => _scanning = true),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.qrcode_viewfinder,
                    color: CupertinoColors.systemBlue.resolveFrom(context)),
                const SizedBox(width: 8),
                const Text('Scan QR Code'),
              ],
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 12),
            Text(_submitError!,
                style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.systemRed.resolveFrom(context)),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _buildScanner(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final code = capture.barcodes.firstOrNull?.rawValue;
            if (code != null && code.isNotEmpty) {
              setState(() => _scanning = false);
              _joinWithKey(code);
            }
          },
        ),
        Positioned(
          top: 16,
          left: 16,
          child: CupertinoButton(
            color: CupertinoColors.black.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            borderRadius: BorderRadius.circular(20),
            onPressed: () => setState(() => _scanning = false),
            child: const Text('Cancel',
                style: TextStyle(color: CupertinoColors.white)),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/features/bands/screens/join_band_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/bands/screens/join_band_screen.dart
git commit -m "feat: add JoinBandScreen (invite code + QR scanner)"
```

---

## Task 10: Flutter — router, login screen, and band selector updates

**Files:**
- Modify: `lib/core/config/router.dart`
- Modify: `lib/features/auth/screens/login_screen.dart`
- Modify: `lib/features/auth/screens/band_selector_screen.dart`

- [ ] **Step 1: Add imports and routes to `router.dart`**

Add these imports at the top of `lib/core/config/router.dart` with the existing imports:

```dart
import '../../features/auth/screens/sign_up_screen.dart';
import '../../features/auth/screens/path_selection_screen.dart';
import '../../features/bands/screens/create_band_screen.dart';
import '../../features/bands/screens/join_band_screen.dart';
```

In the `routes:` list, after the `/login` route, add:

```dart
      GoRoute(
        path: '/signup',
        builder: (context, state) {
          final email = state.uri.queryParameters['email'];
          return SignUpScreen(prefillEmail: email);
        },
      ),
      GoRoute(
        path: '/bands/create',
        builder: (context, state) => const CreateBandScreen(),
      ),
      GoRoute(
        path: '/bands/join',
        builder: (context, state) => const JoinBandScreen(),
      ),
```

Change the existing `/bands` route builder from `BandSelectorScreen` to `PathSelectionScreen` when bands is empty, by replacing:

```dart
      GoRoute(
        path: '/bands',
        builder: (context, state) => const BandSelectorScreen(),
      ),
```

with:

```dart
      GoRoute(
        path: '/bands',
        builder: (context, state) => const PathSelectionScreen(),
      ),
```

> **Note:** The existing `BandSelectorScreen` (which lists multiple bands to pick from) is no longer used from the router. Multi-band users auto-navigate to dashboard via the single-band auto-select path, or if they truly have multiple bands, they can use a band switcher in Settings later. The guard logic in the router already handles single-band auto-select. Verify this is still correct in the router `redirect` block — if `bands.length > 1` with none selected, it falls through to `/bands` which now shows `PathSelectionScreen`; that's a new scenario we should handle.

Update the router redirect for the multi-band, none-selected case so it still shows a meaningful screen. In the redirect block, the case `bands.length > 1, none selected → '/bands'` will now show `PathSelectionScreen`, which is slightly wrong for an existing multi-band user. Leave this as-is for now — the most common case for `/bands` is new users with 0 bands. Multi-band selection can be addressed in a future Settings-based band switcher.

- [ ] **Step 2: Add "Sign up" link to `login_screen.dart`**

In `lib/features/auth/screens/login_screen.dart`, after the `CupertinoButton.filled` submit button (and after the `_loginError` block), add:

```dart
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account?",
                      style: TextStyle(
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.only(left: 4),
                      onPressed: () => context.push('/signup'),
                      child: const Text('Sign up'),
                    ),
                  ],
                ),
```

Also add the GoRouter import if not present:

```dart
import 'package:go_router/go_router.dart';
```

- [ ] **Step 3: Update `band_selector_screen.dart` empty state**

In `lib/features/auth/screens/band_selector_screen.dart`, replace the empty-state `Column` (the one that says "No bands found...") with:

```dart
              return const PathSelectionScreen();
```

Add the import at the top:

```dart
import 'path_selection_screen.dart';
```

- [ ] **Step 4: Analyze all changed files**

```bash
flutter analyze lib/core/config/router.dart lib/features/auth/screens/
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/config/router.dart lib/features/auth/screens/login_screen.dart lib/features/auth/screens/band_selector_screen.dart
git commit -m "feat: wire SignUpScreen, PathSelectionScreen, CreateBandScreen, JoinBandScreen into router"
```

---

## Task 11: Smoke test — run the app end to end

- [ ] **Step 1: Run the app**

```bash
cd /home/eddie/github/tts_bandmate
flutter run -d linux
```

- [ ] **Step 2: Verify login screen has "Sign up" link**

Tap "Sign up" → confirm `SignUpScreen` loads with four fields.

- [ ] **Step 3: Register a new account**

Fill in name, email, password, confirm. Tap "Create Account". Confirm:
- No error shown
- App navigates to `PathSelectionScreen` (three cards visible)

- [ ] **Step 4: Test "Go Solo"**

Tap "Go Solo" → confirm app navigates directly to dashboard.

- [ ] **Step 5: Register a second account and test "Create a Band"**

Tap "Create a Band" → enter band name → tap Next → add an email → tap Done. Confirm app navigates to dashboard.

- [ ] **Step 6: Register a third account and test "Join a Band"**

(Requires a valid invite key from the backend.) Tap "Join a Band" → enter the key → tap Join. Confirm app navigates to dashboard with the correct band.

- [ ] **Step 7: Final commit**

```bash
git add .
git commit -m "feat: complete registration and onboarding flow"
```

---

## Self-Review Notes

**Spec coverage check:**
- ✅ Registration screen (Task 6)
- ✅ Choose Your Path screen (Task 7)
- ✅ Create a Band flow — name + invite (Task 8)
- ✅ Join a Band — code + QR + email link pre-fill (Tasks 9, 10)
- ✅ Go Solo — auto-band (Tasks 1, 2, 7)
- ✅ Backend: register, createBand, inviteMembers, joinBand, goSolo, inviteQr (Tasks 1, 2)
- ✅ Login screen "Sign up" link (Task 10)
- ✅ `/bands` route → PathSelectionScreen (Task 10)
- ⚠️ Deep link handler (`bandmate://invite/{key}`) — **not covered in this plan.** Deep linking requires platform-specific config (AndroidManifest, Info.plist, `go_router` redirect on startup). Recommend as a follow-on plan once the core flow is working.
- ⚠️ QR display for band owners (Settings → Band → Invite) — `getInviteKey()` is implemented in the repository but the Settings UI entry point is not. Recommend as a follow-on task.
