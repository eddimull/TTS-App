# Social Login (Google / Apple / Facebook) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Users can sign in / sign up with Google, Apple, or Facebook on the Flutter mobile app and the TTS web app, auto-linking to existing accounts by email.

**Architecture:** Backend gains a `social_accounts` table, per-provider token verifiers (JWKS for Google/Apple id_tokens, Graph API for Facebook access tokens), and one shared `SocialAuthService::resolveUser()` used by both a new mobile endpoint (`POST /api/mobile/auth/social`, same `{token,user,bands}` envelope as password login) and a Socialite redirect flow on web. Mobile uses native SDKs (`google_sign_in`, `sign_in_with_apple`, `flutter_facebook_auth`) and posts the provider token to the backend.

**Tech Stack:** Laravel 12 + Sanctum + Socialite + `socialiteproviders/apple` + `firebase/php-jwt` (already installed); Flutter/Riverpod v2 + Dio.

**Spec:** `docs/superpowers/specs/2026-07-03-social-login-design.md` (in tts_bandmate repo).

## Global Constraints

- **Two repos.** Part A tasks run in `/home/eddie/github/TTS` (Laravel). Part B tasks run in `/home/eddie/github/tts_bandmate` (Flutter). Every task states its repo — check `pwd` before starting.
- **TTS repo:** never run `php`/`artisan`/`composer`/`npm` on the host — always `docker compose exec app <cmd>` (stack must be up: `docker compose up -d`). Branch: `feat/social-login` cut from `staging`. PRs target `staging` (staging auto-deploys on merge).
- **tts_bandmate repo:** branch `feat/social-login` already exists (cut from `main`). PRs target `main`. Commands: `flutter test`, `flutter analyze` run on host.
- Provider identifiers are the exact lowercase strings `google`, `apple`, `facebook` everywhere (API params, DB `provider` column, route params, Dart enum `.name`).
- The mobile social endpoint returns the exact same envelope as `POST /api/mobile/auth/token`: `{token, user: {id,name,email,avatar_url}, bands: [...]}` — built with the existing `TokenService`.
- Social sign-in must set `email_verified_at` (providers verify emails; the web `dashboard` route sits behind the `verified` middleware, so a social user with a NULL `email_verified_at` would get bounced to the verify-email page).
- Git commits: conventional style, scope `social-login`. After `gh pr create`, wait for Copilot's auto-review and address its comments before calling the PR done.
- Backend tests: before writing the first test, open `tests/Feature/Api/Mobile/GoSoloTokenTest.php` and mirror its base class + database traits (RefreshDatabase vs transactions) and factory usage. Test code below assumes `Tests\TestCase` + `RefreshDatabase`; adjust to match the repo convention if it differs.
- Package versions in this plan were written against the assistant's Jan-2026 knowledge. After each `composer require` / `flutter pub add`, skim the installed package's README and adapt API calls if signatures moved (called out per-task where risk is real).

---

# Part A — Backend + Web (repo: /home/eddie/github/TTS)

### Task A1: Branch, packages, provider config

**Files:**
- Modify: `config/services.php`
- Modify: `.env.example`
- Modify: `app/Providers/AppServiceProvider.php`

**Interfaces:**
- Produces: `config('services.google.allowed_client_ids')` / `config('services.apple.allowed_client_ids')` (arrays), `config('services.facebook.client_secret')`, Socialite drivers `google`, `apple`, `facebook` resolvable.

- [ ] **Step 1: Branch**

```bash
cd /home/eddie/github/TTS
git fetch origin staging && git checkout -b feat/social-login origin/staging
docker compose up -d
```

- [ ] **Step 2: Install packages**

```bash
docker compose exec app composer require laravel/socialite socialiteproviders/apple
```

Expected: both packages install without conflict (`firebase/php-jwt` is already present as a transitive dep — it will now be direct via socialiteproviders; that's fine).

- [ ] **Step 3: Add service config**

Append to the returned array in `config/services.php`:

```php
'google' => [
    'client_id'     => env('GOOGLE_SIGNIN_CLIENT_ID'),
    'client_secret' => env('GOOGLE_SIGNIN_CLIENT_SECRET'),
    'redirect'      => env('APP_URL') . '/auth/google/callback',
    // id_token `aud` whitelist: web client id + Android + iOS client ids, comma-separated.
    'allowed_client_ids' => array_filter(explode(',', env('GOOGLE_SIGNIN_ALLOWED_CLIENT_IDS', ''))),
],

'facebook' => [
    'client_id'     => env('FACEBOOK_CLIENT_ID'),
    'client_secret' => env('FACEBOOK_CLIENT_SECRET'),
    'redirect'      => env('APP_URL') . '/auth/facebook/callback',
],

'apple' => [
    'client_id'     => env('APPLE_SERVICES_CLIENT_ID'),   // Services ID (web flow)
    'client_secret' => env('APPLE_CLIENT_SECRET'),         // pre-generated JWT, expires ≤6 months
    'redirect'      => env('APP_URL') . '/auth/apple/callback',
    // id_token `aud` whitelist: iOS bundle id + Services ID, comma-separated.
    'allowed_client_ids' => array_filter(explode(',', env('APPLE_SIGNIN_ALLOWED_CLIENT_IDS', ''))),
],
```

Add matching empty entries to `.env.example`:

```
GOOGLE_SIGNIN_CLIENT_ID=
GOOGLE_SIGNIN_CLIENT_SECRET=
GOOGLE_SIGNIN_ALLOWED_CLIENT_IDS=
FACEBOOK_CLIENT_ID=
FACEBOOK_CLIENT_SECRET=
APPLE_SERVICES_CLIENT_ID=
APPLE_CLIENT_SECRET=
APPLE_SIGNIN_ALLOWED_CLIENT_IDS=
```

- [ ] **Step 4: Register the Apple Socialite driver**

In `app/Providers/AppServiceProvider.php` `boot()` (add the imports):

```php
use Illuminate\Support\Facades\Event;
use SocialiteProviders\Manager\SocialiteWasCalled;

// in boot():
Event::listen(SocialiteWasCalled::class, [\SocialiteProviders\Apple\AppleExtendSocialite::class, 'handle']);
```

(Check the socialiteproviders/apple README for the exact listener class name if this errors.)

- [ ] **Step 5: Smoke-verify**

```bash
docker compose exec app php artisan tinker --execute="var_dump(config('services.google.allowed_client_ids')); var_dump(get_class(Laravel\Socialite\Facades\Socialite::driver('apple')));"
```

Expected: an array (empty is fine) and a SocialiteProviders Apple provider class name. No exception.

- [ ] **Step 6: Commit**

```bash
git add composer.json composer.lock config/services.php .env.example app/Providers/AppServiceProvider.php
git commit -m "feat(social-login): install Socialite + Apple provider, add provider config"
```

---

### Task A2: `social_accounts` table, model, nullable password

**Files:**
- Create: `database/migrations/2026_07_03_000001_create_social_accounts_table.php`
- Create: `database/migrations/2026_07_03_000002_make_users_password_nullable.php`
- Create: `app/Models/SocialAccount.php`
- Modify: `app/Models/User.php` (add relation)
- Test: `tests/Feature/SocialAccountTest.php`

**Interfaces:**
- Produces: `SocialAccount` model (`fillable: user_id, provider, provider_id, avatar_url`; `belongsTo user`), `User::socialAccounts(): HasMany`, `users.password` nullable.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature;

use App\Models\SocialAccount;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SocialAccountTest extends TestCase
{
    use RefreshDatabase;

    public function test_social_account_links_to_user_and_enforces_unique_provider_id(): void
    {
        $user = User::factory()->create();

        $account = SocialAccount::create([
            'user_id'     => $user->id,
            'provider'    => 'google',
            'provider_id' => 'g-123',
            'avatar_url'  => 'https://example.com/a.png',
        ]);

        $this->assertTrue($account->user->is($user));
        $this->assertTrue($user->socialAccounts()->first()->is($account));

        $this->expectException(QueryException::class);
        SocialAccount::create([
            'user_id'     => $user->id,
            'provider'    => 'google',
            'provider_id' => 'g-123',
        ]);
    }

    public function test_user_can_be_created_without_password(): void
    {
        $user = User::create([
            'name'     => 'Social Only',
            'email'    => 'social-only@example.com',
            'password' => null,
        ]);

        $this->assertNull($user->fresh()->password);
    }
}
```

- [ ] **Step 2: Run it — expect FAIL** (`Class "App\Models\SocialAccount" not found`)

```bash
docker compose exec app php artisan test --filter=SocialAccountTest
```

- [ ] **Step 3: Implement**

`database/migrations/2026_07_03_000001_create_social_accounts_table.php`:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('social_accounts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('provider', 20);
            $table->string('provider_id');
            $table->string('avatar_url')->nullable();
            $table->timestamps();

            $table->unique(['provider', 'provider_id']);
            $table->index('user_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('social_accounts');
    }
};
```

`database/migrations/2026_07_03_000002_make_users_password_nullable.php`:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('password')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('password')->nullable(false)->change();
        });
    }
};
```

`app/Models/SocialAccount.php`:

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SocialAccount extends Model
{
    protected $fillable = ['user_id', 'provider', 'provider_id', 'avatar_url'];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
```

In `app/Models/User.php`, next to the other relations:

```php
public function socialAccounts()
{
    return $this->hasMany(SocialAccount::class);
}
```

- [ ] **Step 4: Migrate + run test — expect PASS**

```bash
docker compose exec app php artisan migrate
docker compose exec app php artisan test --filter=SocialAccountTest
```

- [ ] **Step 5: Commit**

```bash
git add database/migrations app/Models/SocialAccount.php app/Models/User.php tests/Feature/SocialAccountTest.php
git commit -m "feat(social-login): social_accounts table, model, nullable users.password"
```

---

### Task A3: Extract pending-invitation acceptance into a shared service

**Files:**
- Create: `app/Services/PendingInvitationService.php`
- Modify: `app/Http/Controllers/Api/Mobile/OnboardingController.php` (register method, currently lines ~46–82)
- Test: `tests/Feature/PendingInvitationServiceTest.php`

**Interfaces:**
- Produces: `PendingInvitationService::applyFor(User $user): void` — consumes any pending `EventSubs` and band `Invitations` matching `$user->email`, assigning roles. Constants `PendingInvitationService::OWNER_INVITE_TYPE = 1`, `::MEMBER_INVITE_TYPE = 2`.
- Behavior must be identical to the current inline code in `OnboardingController@register`.

- [ ] **Step 1: Write the failing test**

Look at how existing tests create `Invitations` and bands (grep `Invitations::` under `tests/`) and mirror the factory/setup style. The test:

```php
<?php

namespace Tests\Feature;

use App\Models\Bands;
use App\Models\Invitations;
use App\Models\User;
use App\Services\PendingInvitationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PendingInvitationServiceTest extends TestCase
{
    use RefreshDatabase;

    public function test_applies_pending_member_invitation_and_marks_it_consumed(): void
    {
        $band = Bands::factory()->create();
        $invitation = Invitations::create([
            'band_id'        => $band->id,
            'email'          => 'newbie@example.com',
            'invite_type_id' => PendingInvitationService::MEMBER_INVITE_TYPE,
            'pending'        => true,
        ]);
        $user = User::factory()->create(['email' => 'newbie@example.com']);

        app(PendingInvitationService::class)->applyFor($user);

        $this->assertFalse((bool) $invitation->fresh()->pending);
        $this->assertTrue($user->fresh()->bandMember->contains('id', $band->id));
    }

    public function test_ignores_invitations_for_other_emails(): void
    {
        $band = Bands::factory()->create();
        $invitation = Invitations::create([
            'band_id'        => $band->id,
            'email'          => 'someone-else@example.com',
            'invite_type_id' => PendingInvitationService::MEMBER_INVITE_TYPE,
            'pending'        => true,
        ]);
        $user = User::factory()->create(['email' => 'me@example.com']);

        app(PendingInvitationService::class)->applyFor($user);

        $this->assertTrue((bool) $invitation->fresh()->pending);
        $this->assertFalse($user->fresh()->bandMember->contains('id', $band->id));
    }
}
```

(If `Invitations::create` needs a `key` or other required columns, copy the creation style from an existing invitation test.)

- [ ] **Step 2: Run — expect FAIL** (class not found)

```bash
docker compose exec app php artisan test --filter=PendingInvitationServiceTest
```

- [ ] **Step 3: Implement — move the code verbatim**

`app/Services/PendingInvitationService.php` (this is the exact block from `OnboardingController@register`, wrapped in a class):

```php
<?php

namespace App\Services;

use App\Models\BandMembers;
use App\Models\BandOwners;
use App\Models\EventSubs;
use App\Models\Invitations;
use App\Models\User;

class PendingInvitationService
{
    public const OWNER_INVITE_TYPE = 1;
    public const MEMBER_INVITE_TYPE = 2;

    /**
     * Consume any pending sub-invitations and band invitations addressed to
     * this user's email, assigning the corresponding roles. Shared by email
     * registration and social sign-up so the two paths cannot drift.
     */
    public function applyFor(User $user): void
    {
        $subInvitations = EventSubs::where('email', $user->email)
            ->where('pending', true)
            ->get();

        if ($subInvitations->isNotEmpty()) {
            $service = new SubInvitationService();
            foreach ($subInvitations as $eventSub) {
                $service->acceptInvitation($eventSub->invitation_key, $user);
            }
        }

        $invitations = Invitations::where('email', $user->email)
            ->where('pending', true)
            ->get();

        foreach ($invitations as $invitation) {
            if ($invitation->invite_type_id === self::OWNER_INVITE_TYPE) {
                BandOwners::create([
                    'user_id' => $user->id,
                    'band_id' => $invitation->band_id,
                ]);
                setPermissionsTeamId($invitation->band_id);
                $user->assignRole('band-owner');
                setPermissionsTeamId(null);
            }
            if ($invitation->invite_type_id === self::MEMBER_INVITE_TYPE) {
                BandMembers::create([
                    'user_id' => $user->id,
                    'band_id' => $invitation->band_id,
                ]);
                $user->assignBandMemberDefaults($invitation->band_id);
            }
            $invitation->pending = false;
            $invitation->save();
        }
    }
}
```

In `OnboardingController`:
1. Add constructor param: `public function __construct(private readonly TokenService $tokenService, private readonly PendingInvitationService $pendingInvitations) {}`
2. In `register()`, replace the whole block from `// Apply any pending sub-invitations` through the end of the `foreach ($invitations ...)` loop with:

```php
$this->pendingInvitations->applyFor($user);
```

3. Leave the controller's own `OWNER_INVITE_TYPE`/`MEMBER_INVITE_TYPE` constants — `joinBand()` and `inviteQr()` still use them.
4. Remove now-unused imports from the controller **only if** nothing else in the file uses them (`joinBand` still uses `BandOwners`/`BandMembers`/`Invitations`, so likely only `EventSubs` and `SubInvitationService` become removable).

- [ ] **Step 4: Run new test + all onboarding/register tests — expect PASS**

```bash
docker compose exec app php artisan test --filter=PendingInvitationServiceTest
docker compose exec app php artisan test --filter=Onboarding
docker compose exec app php artisan test --filter=Register
```

- [ ] **Step 5: Commit**

```bash
git add app/Services/PendingInvitationService.php app/Http/Controllers/Api/Mobile/OnboardingController.php tests/Feature/PendingInvitationServiceTest.php
git commit -m "refactor(social-login): extract pending-invitation acceptance into shared service"
```

---

### Task A4: Provider token verifiers

**Files:**
- Create: `app/Services/SocialAuth/SocialProfile.php`
- Create: `app/Services/SocialAuth/InvalidSocialTokenException.php`
- Create: `app/Services/SocialAuth/SocialTokenVerifier.php` (interface)
- Create: `app/Services/SocialAuth/AbstractIdTokenVerifier.php`
- Create: `app/Services/SocialAuth/GoogleIdTokenVerifier.php`
- Create: `app/Services/SocialAuth/AppleIdTokenVerifier.php`
- Create: `app/Services/SocialAuth/FacebookAccessTokenVerifier.php`
- Create: `app/Services/SocialAuth/SocialTokenVerifierManager.php`
- Test: `tests/Unit/SocialAuth/AppleIdTokenVerifierTest.php`
- Test: `tests/Unit/SocialAuth/FacebookAccessTokenVerifierTest.php`

**Interfaces:**
- Produces:
  - `SocialProfile` readonly DTO: `__construct(public string $provider, public string $providerId, public string $email, public ?string $name, public ?string $avatarUrl)`
  - `SocialTokenVerifier::verify(string $token): SocialProfile` (throws `InvalidSocialTokenException`)
  - `SocialTokenVerifierManager::for(string $provider): SocialTokenVerifier`

- [ ] **Step 1: Write the failing tests**

`tests/Unit/SocialAuth/AppleIdTokenVerifierTest.php` — generates a real RSA keypair, serves it as a faked JWKS, and signs tokens with it:

```php
<?php

namespace Tests\Unit\SocialAuth;

use App\Services\SocialAuth\AppleIdTokenVerifier;
use App\Services\SocialAuth\InvalidSocialTokenException;
use Firebase\JWT\JWT;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class AppleIdTokenVerifierTest extends TestCase
{
    private string $privateKey;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        config(['services.apple.allowed_client_ids' => ['band.tts.bandmate']]);

        $res = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
        openssl_pkey_export($res, $this->privateKey);
        $details = openssl_pkey_get_details($res);

        $b64url = fn (string $bin) => rtrim(strtr(base64_encode($bin), '+/', '-_'), '=');
        Http::fake([
            'https://appleid.apple.com/auth/keys' => Http::response([
                'keys' => [[
                    'kty' => 'RSA',
                    'kid' => 'test-key',
                    'use' => 'sig',
                    'alg' => 'RS256',
                    'n'   => $b64url($details['rsa']['n']),
                    'e'   => $b64url($details['rsa']['e']),
                ]],
            ]),
        ]);
    }

    private function makeToken(array $overrides = []): string
    {
        $claims = array_merge([
            'iss'   => 'https://appleid.apple.com',
            'aud'   => 'band.tts.bandmate',
            'sub'   => 'apple-user-1',
            'email' => 'apple-user@example.com',
            'iat'   => time(),
            'exp'   => time() + 300,
        ], $overrides);

        return JWT::encode($claims, $this->privateKey, 'RS256', 'test-key');
    }

    public function test_valid_token_yields_profile(): void
    {
        $profile = app(AppleIdTokenVerifier::class)->verify($this->makeToken());

        $this->assertSame('apple', $profile->provider);
        $this->assertSame('apple-user-1', $profile->providerId);
        $this->assertSame('apple-user@example.com', $profile->email);
        $this->assertNull($profile->name);
    }

    public function test_wrong_audience_is_rejected(): void
    {
        $this->expectException(InvalidSocialTokenException::class);
        app(AppleIdTokenVerifier::class)->verify($this->makeToken(['aud' => 'some.other.app']));
    }

    public function test_expired_token_is_rejected(): void
    {
        $this->expectException(InvalidSocialTokenException::class);
        app(AppleIdTokenVerifier::class)->verify($this->makeToken(['exp' => time() - 10, 'iat' => time() - 600]));
    }

    public function test_garbage_token_is_rejected(): void
    {
        $this->expectException(InvalidSocialTokenException::class);
        app(AppleIdTokenVerifier::class)->verify('not-a-jwt');
    }
}
```

`tests/Unit/SocialAuth/FacebookAccessTokenVerifierTest.php`:

```php
<?php

namespace Tests\Unit\SocialAuth;

use App\Services\SocialAuth\FacebookAccessTokenVerifier;
use App\Services\SocialAuth\InvalidSocialTokenException;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class FacebookAccessTokenVerifierTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['services.facebook.client_secret' => 'shhh']);
    }

    public function test_valid_token_yields_profile(): void
    {
        Http::fake([
            'graph.facebook.com/*' => Http::response([
                'id'      => 'fb-1',
                'name'    => 'Face Book',
                'email'   => 'fb@example.com',
                'picture' => ['data' => ['url' => 'https://example.com/p.png']],
            ]),
        ]);

        $profile = app(FacebookAccessTokenVerifier::class)->verify('fb-token');

        $this->assertSame('facebook', $profile->provider);
        $this->assertSame('fb-1', $profile->providerId);
        $this->assertSame('fb@example.com', $profile->email);
        $this->assertSame('Face Book', $profile->name);
        $this->assertSame('https://example.com/p.png', $profile->avatarUrl);
    }

    public function test_graph_error_is_rejected(): void
    {
        Http::fake(['graph.facebook.com/*' => Http::response(['error' => ['message' => 'bad token']], 400)]);

        $this->expectException(InvalidSocialTokenException::class);
        app(FacebookAccessTokenVerifier::class)->verify('bad');
    }

    public function test_account_without_email_is_rejected(): void
    {
        Http::fake(['graph.facebook.com/*' => Http::response(['id' => 'fb-1', 'name' => 'No Mail'])]);

        $this->expectException(InvalidSocialTokenException::class);
        app(FacebookAccessTokenVerifier::class)->verify('fb-token');
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (classes not found)

```bash
docker compose exec app php artisan test --filter=SocialAuth
```

- [ ] **Step 3: Implement**

`app/Services/SocialAuth/SocialProfile.php`:

```php
<?php

namespace App\Services\SocialAuth;

readonly class SocialProfile
{
    public function __construct(
        public string $provider,
        public string $providerId,
        public string $email,
        public ?string $name,
        public ?string $avatarUrl,
    ) {}
}
```

`app/Services/SocialAuth/InvalidSocialTokenException.php`:

```php
<?php

namespace App\Services\SocialAuth;

class InvalidSocialTokenException extends \RuntimeException {}
```

`app/Services/SocialAuth/SocialTokenVerifier.php`:

```php
<?php

namespace App\Services\SocialAuth;

interface SocialTokenVerifier
{
    /** @throws InvalidSocialTokenException */
    public function verify(string $token): SocialProfile;
}
```

`app/Services/SocialAuth/AbstractIdTokenVerifier.php`:

```php
<?php

namespace App\Services\SocialAuth;

use Firebase\JWT\JWK;
use Firebase\JWT\JWT;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;

/**
 * Verifies an OIDC id_token against the provider's published JWKS.
 * Signature + exp are checked by firebase/php-jwt; iss and aud here.
 */
abstract class AbstractIdTokenVerifier implements SocialTokenVerifier
{
    abstract protected function provider(): string;

    abstract protected function jwksUrl(): string;

    /** @return string[] */
    abstract protected function allowedIssuers(): array;

    /** @return string[] */
    abstract protected function allowedAudiences(): array;

    abstract protected function toProfile(object $claims): SocialProfile;

    public function verify(string $token): SocialProfile
    {
        try {
            $jwks = Cache::remember(
                "social-jwks:{$this->provider()}",
                now()->addHour(),
                fn () => Http::timeout(10)->get($this->jwksUrl())->throw()->json(),
            );
            $claims = JWT::decode($token, JWK::parseKeySet($jwks));
        } catch (\Throwable) {
            throw new InvalidSocialTokenException("Could not verify your {$this->provider()} sign-in.");
        }

        $audiences = (array) ($claims->aud ?? []);
        if (!in_array($claims->iss ?? '', $this->allowedIssuers(), true)
            || array_intersect($audiences, $this->allowedAudiences()) === []) {
            throw new InvalidSocialTokenException("Could not verify your {$this->provider()} sign-in.");
        }

        if (empty($claims->email)) {
            throw new InvalidSocialTokenException(
                "Your {$this->provider()} account did not share an email address."
            );
        }

        return $this->toProfile($claims);
    }
}
```

`app/Services/SocialAuth/GoogleIdTokenVerifier.php`:

```php
<?php

namespace App\Services\SocialAuth;

class GoogleIdTokenVerifier extends AbstractIdTokenVerifier
{
    protected function provider(): string
    {
        return 'google';
    }

    protected function jwksUrl(): string
    {
        return 'https://www.googleapis.com/oauth2/v3/certs';
    }

    protected function allowedIssuers(): array
    {
        return ['https://accounts.google.com', 'accounts.google.com'];
    }

    protected function allowedAudiences(): array
    {
        return config('services.google.allowed_client_ids', []);
    }

    protected function toProfile(object $claims): SocialProfile
    {
        return new SocialProfile(
            provider: 'google',
            providerId: $claims->sub,
            email: $claims->email,
            name: $claims->name ?? null,
            avatarUrl: $claims->picture ?? null,
        );
    }
}
```

`app/Services/SocialAuth/AppleIdTokenVerifier.php`:

```php
<?php

namespace App\Services\SocialAuth;

class AppleIdTokenVerifier extends AbstractIdTokenVerifier
{
    protected function provider(): string
    {
        return 'apple';
    }

    protected function jwksUrl(): string
    {
        return 'https://appleid.apple.com/auth/keys';
    }

    protected function allowedIssuers(): array
    {
        return ['https://appleid.apple.com'];
    }

    protected function allowedAudiences(): array
    {
        return config('services.apple.allowed_client_ids', []);
    }

    protected function toProfile(object $claims): SocialProfile
    {
        // Apple id_tokens never carry a display name; SocialAuthService falls
        // back to the email local-part when creating the user.
        return new SocialProfile(
            provider: 'apple',
            providerId: $claims->sub,
            email: $claims->email,
            name: null,
            avatarUrl: null,
        );
    }
}
```

`app/Services/SocialAuth/FacebookAccessTokenVerifier.php`:

```php
<?php

namespace App\Services\SocialAuth;

use Illuminate\Support\Facades\Http;

/**
 * Facebook uses opaque access tokens, not id_tokens — validate by calling the
 * Graph API. appsecret_proof binds the call to OUR app secret, so a token
 * issued to a different app fails (enable "Require App Secret" in the FB app).
 */
class FacebookAccessTokenVerifier implements SocialTokenVerifier
{
    public function verify(string $token): SocialProfile
    {
        $response = Http::timeout(10)->get('https://graph.facebook.com/v21.0/me', [
            'fields'           => 'id,name,email,picture.type(large)',
            'access_token'     => $token,
            'appsecret_proof'  => hash_hmac('sha256', $token, config('services.facebook.client_secret', '')),
        ]);

        if ($response->failed() || !$response->json('id')) {
            throw new InvalidSocialTokenException('Could not verify your facebook sign-in.');
        }

        $email = $response->json('email');
        if (!$email) {
            throw new InvalidSocialTokenException(
                'Your Facebook account has no email address. Please sign up with email instead.'
            );
        }

        return new SocialProfile(
            provider: 'facebook',
            providerId: (string) $response->json('id'),
            email: $email,
            name: $response->json('name'),
            avatarUrl: $response->json('picture.data.url'),
        );
    }
}
```

`app/Services/SocialAuth/SocialTokenVerifierManager.php`:

```php
<?php

namespace App\Services\SocialAuth;

class SocialTokenVerifierManager
{
    public function for(string $provider): SocialTokenVerifier
    {
        return match ($provider) {
            'google'   => app(GoogleIdTokenVerifier::class),
            'apple'    => app(AppleIdTokenVerifier::class),
            'facebook' => app(FacebookAccessTokenVerifier::class),
        };
    }
}
```

- [ ] **Step 4: Run — expect PASS**

```bash
docker compose exec app php artisan test --filter=SocialAuth
```

- [ ] **Step 5: Commit**

```bash
git add app/Services/SocialAuth tests/Unit/SocialAuth
git commit -m "feat(social-login): per-provider token verifiers (JWKS for Google/Apple, Graph for Facebook)"
```

---

### Task A5: `SocialAuthService::resolveUser`

**Files:**
- Create: `app/Services/SocialAuth/SocialAuthService.php`
- Test: `tests/Feature/SocialAuthServiceTest.php`

**Interfaces:**
- Consumes: `SocialProfile` (A4), `SocialAccount` (A2), `PendingInvitationService::applyFor` (A3).
- Produces: `SocialAuthService::resolveUser(SocialProfile $profile): User`.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature;

use App\Models\Bands;
use App\Models\Invitations;
use App\Models\SocialAccount;
use App\Models\User;
use App\Services\PendingInvitationService;
use App\Services\SocialAuth\SocialAuthService;
use App\Services\SocialAuth\SocialProfile;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SocialAuthServiceTest extends TestCase
{
    use RefreshDatabase;

    private function profile(array $overrides = []): SocialProfile
    {
        return new SocialProfile(...array_merge([
            'provider'   => 'google',
            'providerId' => 'g-1',
            'email'      => 'new@example.com',
            'name'       => 'New Person',
            'avatarUrl'  => 'https://example.com/a.png',
        ], $overrides));
    }

    public function test_existing_link_returns_linked_user(): void
    {
        $user = User::factory()->create();
        SocialAccount::create(['user_id' => $user->id, 'provider' => 'google', 'provider_id' => 'g-1']);

        $resolved = app(SocialAuthService::class)->resolveUser($this->profile());

        $this->assertTrue($resolved->is($user));
        $this->assertSame(1, SocialAccount::count());
    }

    public function test_matching_email_auto_links_and_marks_verified(): void
    {
        $user = User::factory()->create(['email' => 'existing@example.com', 'email_verified_at' => null]);

        $resolved = app(SocialAuthService::class)
            ->resolveUser($this->profile(['email' => 'existing@example.com']));

        $this->assertTrue($resolved->is($user));
        $this->assertNotNull($resolved->fresh()->email_verified_at);
        $this->assertDatabaseHas('social_accounts', [
            'user_id'     => $user->id,
            'provider'    => 'google',
            'provider_id' => 'g-1',
        ]);
    }

    public function test_unknown_email_creates_user_and_applies_invitations(): void
    {
        $band = Bands::factory()->create();
        Invitations::create([
            'band_id'        => $band->id,
            'email'          => 'new@example.com',
            'invite_type_id' => PendingInvitationService::MEMBER_INVITE_TYPE,
            'pending'        => true,
        ]);

        $resolved = app(SocialAuthService::class)->resolveUser($this->profile());

        $this->assertSame('New Person', $resolved->name);
        $this->assertNull($resolved->password);
        $this->assertNotNull($resolved->email_verified_at);
        $this->assertTrue($resolved->fresh()->bandMember->contains('id', $band->id));
    }

    public function test_missing_name_falls_back_to_email_local_part(): void
    {
        $resolved = app(SocialAuthService::class)
            ->resolveUser($this->profile(['provider' => 'apple', 'providerId' => 'a-1', 'email' => 'jane.doe@example.com', 'name' => null]));

        $this->assertSame('jane.doe', $resolved->name);
    }
}
```

(Same caveat as A3: if `Invitations::create` needs extra columns, mirror existing tests.)

- [ ] **Step 2: Run — expect FAIL**

```bash
docker compose exec app php artisan test --filter=SocialAuthServiceTest
```

- [ ] **Step 3: Implement**

`app/Services/SocialAuth/SocialAuthService.php`:

```php
<?php

namespace App\Services\SocialAuth;

use App\Models\SocialAccount;
use App\Models\User;
use App\Services\PendingInvitationService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class SocialAuthService
{
    public function __construct(
        private readonly PendingInvitationService $pendingInvitations,
    ) {}

    /**
     * Resolve a verified provider profile to a local user:
     *  1. already linked (provider, provider_id) -> that user
     *  2. email matches an existing user        -> auto-link + return it
     *  3. otherwise                              -> create user + link,
     *     honoring pending invitations exactly like email registration.
     *
     * Providers verify email ownership, so both auto-link and creation mark
     * the email verified (the web dashboard sits behind `verified`).
     */
    public function resolveUser(SocialProfile $profile): User
    {
        return DB::transaction(function () use ($profile) {
            $existing = SocialAccount::where('provider', $profile->provider)
                ->where('provider_id', $profile->providerId)
                ->first();

            if ($existing) {
                if ($profile->avatarUrl && $existing->avatar_url !== $profile->avatarUrl) {
                    $existing->update(['avatar_url' => $profile->avatarUrl]);
                }

                return $existing->user;
            }

            $user = User::where('email', $profile->email)->first();

            if (!$user) {
                $user = User::create([
                    'name'     => $profile->name ?: Str::before($profile->email, '@'),
                    'email'    => $profile->email,
                    'password' => null,
                ]);
                $this->pendingInvitations->applyFor($user);
            }

            if ($user->email_verified_at === null) {
                $user->forceFill(['email_verified_at' => now()])->save();
            }

            SocialAccount::create([
                'user_id'     => $user->id,
                'provider'    => $profile->provider,
                'provider_id' => $profile->providerId,
                'avatar_url'  => $profile->avatarUrl,
            ]);

            return $user;
        });
    }
}
```

- [ ] **Step 4: Run — expect PASS**

```bash
docker compose exec app php artisan test --filter=SocialAuthServiceTest
```

- [ ] **Step 5: Commit**

```bash
git add app/Services/SocialAuth/SocialAuthService.php tests/Feature/SocialAuthServiceTest.php
git commit -m "feat(social-login): SocialAuthService resolves provider profiles to users"
```

---

### Task A6: Mobile endpoint `POST /api/mobile/auth/social`

**Files:**
- Create: `app/Http/Controllers/Api/Mobile/SocialAuthController.php`
- Modify: `routes/api.php` (public mobile group, next to `mobile.auth.token`)
- Test: `tests/Feature/Api/Mobile/SocialLoginTest.php`

**Interfaces:**
- Consumes: `SocialTokenVerifierManager` (A4), `SocialAuthService` (A5), `TokenService` (existing).
- Produces: `POST /api/mobile/auth/social` accepting `{provider, token, device_name}`, returning the standard `{token, user, bands}` envelope; invalid provider token → 422.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\SocialAccount;
use App\Models\User;
use App\Services\SocialAuth\InvalidSocialTokenException;
use App\Services\SocialAuth\SocialProfile;
use App\Services\SocialAuth\SocialTokenVerifier;
use App\Services\SocialAuth\SocialTokenVerifierManager;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SocialLoginTest extends TestCase
{
    use RefreshDatabase;

    private function fakeVerifier(SocialProfile $profile): void
    {
        $verifier = new class($profile) implements SocialTokenVerifier {
            public function __construct(private readonly SocialProfile $profile) {}

            public function verify(string $token): SocialProfile
            {
                if ($token === 'bad-token') {
                    throw new InvalidSocialTokenException('Could not verify your google sign-in.');
                }

                return $this->profile;
            }
        };

        $this->mock(SocialTokenVerifierManager::class)
            ->shouldReceive('for')
            ->andReturn($verifier);
    }

    public function test_new_user_is_created_and_receives_standard_envelope(): void
    {
        $this->fakeVerifier(new SocialProfile('google', 'g-9', 'social@example.com', 'Social Sam', null));

        $response = $this->postJson('/api/mobile/auth/social', [
            'provider'    => 'google',
            'token'       => 'good-token',
            'device_name' => 'tts_bandmate_app',
        ]);

        $response->assertOk()
            ->assertJsonStructure(['token', 'user' => ['id', 'name', 'email', 'avatar_url'], 'bands']);

        $this->assertSame('Social Sam', User::where('email', 'social@example.com')->first()->name);
        $this->assertSame(1, SocialAccount::count());
    }

    public function test_existing_email_logs_into_existing_account(): void
    {
        $user = User::factory()->create(['email' => 'existing@example.com']);
        $this->fakeVerifier(new SocialProfile('google', 'g-9', 'existing@example.com', 'Whoever', null));

        $response = $this->postJson('/api/mobile/auth/social', [
            'provider'    => 'google',
            'token'       => 'good-token',
            'device_name' => 'tts_bandmate_app',
        ]);

        $response->assertOk()->assertJsonPath('user.id', $user->id);
        $this->assertSame(1, User::where('email', 'existing@example.com')->count());
    }

    public function test_invalid_provider_token_is_422(): void
    {
        $this->fakeVerifier(new SocialProfile('google', 'g-9', 'x@example.com', null, null));

        $this->postJson('/api/mobile/auth/social', [
            'provider'    => 'google',
            'token'       => 'bad-token',
            'device_name' => 'tts_bandmate_app',
        ])->assertStatus(422)->assertJsonValidationErrors('token');
    }

    public function test_unknown_provider_is_422(): void
    {
        $this->postJson('/api/mobile/auth/social', [
            'provider'    => 'myspace',
            'token'       => 't',
            'device_name' => 'tts_bandmate_app',
        ])->assertStatus(422)->assertJsonValidationErrors('provider');
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (404, route not defined)

```bash
docker compose exec app php artisan test --filter=SocialLoginTest
```

- [ ] **Step 3: Implement**

`app/Http/Controllers/Api/Mobile/SocialAuthController.php`:

```php
<?php

namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Services\Mobile\TokenService;
use App\Services\SocialAuth\InvalidSocialTokenException;
use App\Services\SocialAuth\SocialAuthService;
use App\Services\SocialAuth\SocialTokenVerifierManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class SocialAuthController extends Controller
{
    public function __construct(
        private readonly TokenService $tokenService,
        private readonly SocialTokenVerifierManager $verifiers,
        private readonly SocialAuthService $socialAuth,
    ) {}

    public function token(Request $request): JsonResponse
    {
        $data = $request->validate([
            'provider'    => 'required|string|in:google,apple,facebook',
            'token'       => 'required|string',
            'device_name' => 'required|string|max:255',
        ]);

        try {
            $profile = $this->verifiers->for($data['provider'])->verify($data['token']);
        } catch (InvalidSocialTokenException $e) {
            throw ValidationException::withMessages(['token' => [$e->getMessage()]]);
        }

        $user = $this->socialAuth->resolveUser($profile);

        $abilities = $this->tokenService->buildAbilities($user);
        $token     = $user->createToken($data['device_name'], $abilities)->plainTextToken;

        return response()->json([
            'token' => $token,
            'user'  => $this->tokenService->formatUser($user),
            'bands' => $this->tokenService->formatBands($user),
        ]);
    }
}
```

In `routes/api.php`, inside the `Route::prefix('mobile')` group directly under the `mobile.auth.token` route:

```php
Route::post('/auth/social', [App\Http\Controllers\Api\Mobile\SocialAuthController::class, 'token'])->name('mobile.auth.social');
```

- [ ] **Step 4: Run — expect PASS**

```bash
docker compose exec app php artisan test --filter=SocialLoginTest
```

- [ ] **Step 5: Commit**

```bash
git add app/Http/Controllers/Api/Mobile/SocialAuthController.php routes/api.php tests/Feature/Api/Mobile/SocialLoginTest.php
git commit -m "feat(social-login): mobile social token-exchange endpoint"
```

---

### Task A7: Web Socialite redirect + callback flow

**Files:**
- Create: `app/Http/Controllers/Auth/SocialLoginController.php`
- Modify: `routes/auth.php` (inside the existing `guest` middleware group)
- Modify: `bootstrap/app.php` (CSRF exemption for Apple's POST callback)
- Test: `tests/Feature/Auth/SocialWebLoginTest.php`

**Interfaces:**
- Consumes: `SocialAuthService` (A5), `SocialProfile` (A4), Socialite drivers (A1).
- Produces: `GET /auth/{provider}/redirect` (name `social.redirect`), `GET /auth/{provider}/callback` (name `social.callback`), `POST /auth/apple/callback`.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature\Auth;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Socialite\Contracts\Provider;
use Laravel\Socialite\Facades\Socialite;
use Laravel\Socialite\Two\User as SocialiteUser;
use Mockery;
use Tests\TestCase;

class SocialWebLoginTest extends TestCase
{
    use RefreshDatabase;

    private function mockSocialiteUser(): void
    {
        $socialiteUser = (new SocialiteUser())->map([
            'id'     => 'g-web-1',
            'email'  => 'weblogin@example.com',
            'name'   => 'Web Person',
            'avatar' => null,
        ]);

        $provider = Mockery::mock(Provider::class);
        $provider->shouldReceive('user')->andReturn($socialiteUser);
        Socialite::shouldReceive('driver')->with('google')->andReturn($provider);
    }

    public function test_redirect_route_sends_user_to_provider(): void
    {
        $provider = Mockery::mock(Provider::class);
        $provider->shouldReceive('redirect')->andReturn(redirect('https://accounts.google.com/o/oauth2/auth'));
        Socialite::shouldReceive('driver')->with('google')->andReturn($provider);

        $this->get('/auth/google/redirect')->assertRedirect();
    }

    public function test_callback_creates_user_and_logs_in(): void
    {
        $this->mockSocialiteUser();

        $response = $this->get('/auth/google/callback?code=abc&state=xyz');

        $response->assertRedirect();
        $this->assertAuthenticated();
        $user = User::where('email', 'weblogin@example.com')->first();
        $this->assertNotNull($user);
        $this->assertNotNull($user->email_verified_at);
    }

    public function test_callback_links_existing_user_by_email(): void
    {
        $existing = User::factory()->create(['email' => 'weblogin@example.com']);
        $this->mockSocialiteUser();

        $this->get('/auth/google/callback?code=abc&state=xyz');

        $this->assertAuthenticatedAs($existing);
    }

    public function test_provider_failure_redirects_to_login_with_error(): void
    {
        $provider = Mockery::mock(Provider::class);
        $provider->shouldReceive('user')->andThrow(new \Exception('provider blew up'));
        Socialite::shouldReceive('driver')->with('google')->andReturn($provider);

        $this->get('/auth/google/callback?code=abc&state=xyz')
            ->assertRedirect(route('login'))
            ->assertSessionHasErrors('email');
    }

    public function test_unknown_provider_404s(): void
    {
        $this->get('/auth/myspace/redirect')->assertNotFound();
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (404s)

```bash
docker compose exec app php artisan test --filter=SocialWebLoginTest
```

- [ ] **Step 3: Implement**

`app/Http/Controllers/Auth/SocialLoginController.php`:

```php
<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Services\SocialAuth\SocialAuthService;
use App\Services\SocialAuth\SocialProfile;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Laravel\Socialite\Facades\Socialite;

class SocialLoginController extends Controller
{
    private const PROVIDERS = ['google', 'apple', 'facebook'];

    public function __construct(private readonly SocialAuthService $socialAuth) {}

    public function redirect(string $provider): RedirectResponse
    {
        abort_unless(in_array($provider, self::PROVIDERS, true), 404);

        $driver = Socialite::driver($provider);

        // Apple returns via cross-site form_post, which drops the SameSite=lax
        // session cookie — state validation would always fail. Go stateless.
        if ($provider === 'apple') {
            $driver->stateless();
        }

        return $driver->redirect();
    }

    public function callback(Request $request, string $provider): RedirectResponse
    {
        abort_unless(in_array($provider, self::PROVIDERS, true), 404);

        try {
            $driver = Socialite::driver($provider);
            $socialiteUser = $provider === 'apple' ? $driver->stateless()->user() : $driver->user();

            $email = $socialiteUser->getEmail();
            if (!$email) {
                return redirect()->route('login')->withErrors([
                    'email' => ucfirst($provider) . ' did not share an email address. Please log in with email instead.',
                ]);
            }

            $user = $this->socialAuth->resolveUser(new SocialProfile(
                provider: $provider,
                providerId: (string) $socialiteUser->getId(),
                email: $email,
                name: $socialiteUser->getName(),
                avatarUrl: $socialiteUser->getAvatar(),
            ));
        } catch (\Throwable $e) {
            report($e);

            return redirect()->route('login')->withErrors([
                'email' => 'Social sign-in failed. Please try again.',
            ]);
        }

        Auth::login($user, remember: true);
        $request->session()->regenerate();

        return redirect()->intended(route('dashboard'));
    }
}
```

(Verify the `dashboard` route name exists — `php artisan route:list --name=dashboard`. If it's different, use that.)

In `routes/auth.php`, inside the existing `Route::middleware('guest')->group(...)`:

```php
use App\Http\Controllers\Auth\SocialLoginController;

Route::get('auth/{provider}/redirect', [SocialLoginController::class, 'redirect'])
    ->name('social.redirect');
Route::get('auth/{provider}/callback', [SocialLoginController::class, 'callback'])
    ->name('social.callback');
// Apple's form_post response arrives as a POST.
Route::post('auth/apple/callback', fn (\Illuminate\Http\Request $r) => app(SocialLoginController::class)->callback($r, 'apple'));
```

In `bootstrap/app.php`, add the CSRF exemption inside the existing `->withMiddleware(...)` closure (read the file first and merge with whatever's there):

```php
$middleware->validateCsrfTokens(except: [
    'auth/apple/callback',
]);
```

- [ ] **Step 4: Run — expect PASS**

```bash
docker compose exec app php artisan test --filter=SocialWebLoginTest
```

- [ ] **Step 5: Commit**

```bash
git add app/Http/Controllers/Auth/SocialLoginController.php routes/auth.php bootstrap/app.php tests/Feature/Auth/SocialWebLoginTest.php
git commit -m "feat(social-login): web Socialite redirect/callback flow"
```

---

### Task A8: Web UI — social buttons on Login and Register pages

**Files:**
- Create: `resources/js/Components/SocialLoginButtons.vue`
- Modify: `resources/js/Pages/Auth/Login.vue`
- Modify: `resources/js/Pages/Auth/Register.vue`

**Interfaces:**
- Consumes: web routes from A7 (`/auth/{provider}/redirect`).
- Produces: `<social-login-buttons />` component used by both pages.

- [ ] **Step 1: Check the Vue test setup**

Look at `package.json` scripts and an existing component test (memory: Vue tests exist in CI; assert with `wrapper.text()`/`find()`, never on `<!--v-if-->` markers). If there is a components test directory, add a test mirroring its style asserting the three links render with the right `href`s; if component tests aren't established for `resources/js/Components`, skip the test and rely on visual verification in Step 4.

- [ ] **Step 2: Create the component**

`resources/js/Components/SocialLoginButtons.vue`:

```vue
<template>
  <div>
    <div class="relative my-6">
      <div class="absolute inset-0 flex items-center">
        <div class="w-full border-t border-gray-300 dark:border-gray-600" />
      </div>
      <div class="relative flex justify-center text-sm">
        <span class="px-2 bg-white dark:bg-gray-800 text-gray-500 dark:text-gray-400">
          or continue with
        </span>
      </div>
    </div>

    <div class="space-y-3">
      <a
        href="/auth/google/redirect"
        class="w-full inline-flex items-center justify-center gap-3 py-2 px-4 border border-gray-300 rounded-md shadow-sm bg-white text-sm font-medium text-gray-700 hover:bg-gray-50"
        dusk="social-login-google"
      >
        <svg class="w-5 h-5" viewBox="0 0 24 24"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.27-4.74 3.27-8.1z"/><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84A11 11 0 0 0 12 23z"/><path fill="#FBBC05" d="M5.84 14.1a6.6 6.6 0 0 1 0-4.2V7.06H2.18a11 11 0 0 0 0 9.88l3.66-2.84z"/><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15A11 11 0 0 0 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/></svg>
        Continue with Google
      </a>

      <a
        href="/auth/apple/redirect"
        class="w-full inline-flex items-center justify-center gap-3 py-2 px-4 rounded-md shadow-sm bg-black text-sm font-medium text-white hover:bg-gray-900"
        dusk="social-login-apple"
      >
        <svg class="w-5 h-5" viewBox="0 0 24 24" fill="currentColor"><path d="M16.36 12.79c.03 3.2 2.81 4.27 2.84 4.28-.02.08-.44 1.52-1.46 3-.88 1.28-1.8 2.55-3.24 2.58-1.42.03-1.88-.84-3.5-.84-1.63 0-2.14.81-3.48.87-1.4.05-2.46-1.38-3.35-2.65-1.82-2.63-3.2-7.42-1.34-10.66a5.19 5.19 0 0 1 4.39-2.66c1.37-.03 2.66.92 3.5.92.83 0 2.4-1.14 4.05-.97.69.03 2.63.28 3.87 2.1-.1.06-2.31 1.35-2.28 4.03zM13.7 4.6c.74-.9 1.24-2.14 1.1-3.38-1.06.04-2.35.71-3.11 1.6-.69.79-1.29 2.06-1.13 3.27 1.19.09 2.4-.6 3.14-1.49z"/></svg>
        Continue with Apple
      </a>

      <a
        href="/auth/facebook/redirect"
        class="w-full inline-flex items-center justify-center gap-3 py-2 px-4 rounded-md shadow-sm text-sm font-medium text-white hover:opacity-90"
        style="background-color: #1877F2"
        dusk="social-login-facebook"
      >
        <svg class="w-5 h-5" viewBox="0 0 24 24" fill="currentColor"><path d="M24 12.07C24 5.4 18.63 0 12 0S0 5.4 0 12.07C0 18.1 4.39 23.09 10.13 24v-8.44H7.08v-3.49h3.05V9.41c0-3.02 1.79-4.7 4.53-4.7 1.31 0 2.68.24 2.68.24v2.97h-1.51c-1.49 0-1.96.93-1.96 1.89v2.26h3.33l-.53 3.49h-2.8V24C19.61 23.09 24 18.1 24 12.07z"/></svg>
        Continue with Facebook
      </a>
    </div>
  </div>
</template>
```

(SVGs are the standard brand glyphs; if design review wants pixel-perfect official assets, swap them later — keep the `dusk` attributes.)

- [ ] **Step 3: Use it in both pages**

In `Login.vue`: import and register `SocialLoginButtons from '@/Components/SocialLoginButtons'`, then place `<social-login-buttons />` directly after the closing `</form>` tag (before the `canRegister` block). Same in `Register.vue` after its form.

- [ ] **Step 4: Verify visually**

Build assets and load the login page (use laravel-boost's `get-absolute-url` or the dev server per repo convention), confirm the three buttons render in light + dark mode and that clicking Google hits `/auth/google/redirect` (it will error without real credentials — a Socialite "missing client id"-style error or provider 400 is expected and fine here; a Laravel 404 is not).

- [ ] **Step 5: Commit**

```bash
git add resources/js/Components/SocialLoginButtons.vue resources/js/Pages/Auth/Login.vue resources/js/Pages/Auth/Register.vue
git commit -m "feat(social-login): social buttons on web login/register pages"
```

---

### Task A9: Backend full suite + PR

- [ ] **Step 1: Full test suite**

```bash
docker compose exec app php artisan test
```

Expected: green. Known flake caveat (memory): `band_roles` filter tests can race under `--parallel` — re-run sequentially before concluding a failure is real.

- [ ] **Step 2: Push + PR to staging**

```bash
git push -u origin feat/social-login
gh pr create --base staging --title "Social login: Google / Apple / Facebook (backend + web)" --body "..."
```

PR body: summarize schema, verifiers, mobile endpoint, web flow; link the spec; note the new env vars that must be set in staging/prod before the buttons work; note that merging auto-deploys staging (routes deploy dark until env vars are set — callbacks just error to the login page).

- [ ] **Step 3: Wait for Copilot review and address comments** (required — memory)

---

# Part B — Flutter app (repo: /home/eddie/github/tts_bandmate)

### Task B1: Endpoint constant, AppConfig, `AuthRepository.socialLogin`

**Files:**
- Modify: `lib/core/network/api_endpoints.dart`
- Modify: `lib/core/config/app_config.dart`
- Modify: `lib/features/auth/data/auth_repository.dart`
- Test: `test/features/auth/auth_repository_social_test.dart`

**Interfaces:**
- Produces: `ApiEndpoints.mobileSocial = '/api/mobile/auth/social'`; `AppConfig.googleServerClientId`; `AuthRepository.socialLogin(String provider, String token, String deviceName)` returning the same record type as `login()`.

- [ ] **Step 1: Write the failing test**

`test/features/auth/auth_repository_social_test.dart` (same `_FakeDio` pattern as `auth_repository_refresh_test.dart`, extended to capture the posted body):

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/auth_repository.dart';
import 'package:tts_bandmate/core/network/api_endpoints.dart';

class _FakeDio extends Fake implements Dio {
  _FakeDio(this._responses);

  final Map<String, dynamic> _responses;
  Object? lastPostData;

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
    lastPostData = data;
    final body = _responses[path];
    if (body == null) {
      throw DioException(requestOptions: RequestOptions(path: path));
    }
    return Response<T>(
      data: body as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  test('socialLogin posts provider payload and parses the standard envelope',
      () async {
    final dio = _FakeDio({
      ApiEndpoints.mobileSocial: {
        'token': 'social-token-1',
        'user': {
          'id': 7,
          'name': 'Sam',
          'email': 's@example.com',
          'avatar_url': null
        },
        'bands': <dynamic>[],
      },
    });

    final repo = AuthRepository(dio);
    final result =
        await repo.socialLogin('google', 'id-token-abc', 'tts_bandmate_app');

    expect(result.token, 'social-token-1');
    expect(result.user.id, 7);
    expect(dio.lastPostData, {
      'provider': 'google',
      'token': 'id-token-abc',
      'device_name': 'tts_bandmate_app',
    });
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (no `mobileSocial`, no `socialLogin`)

```bash
cd /home/eddie/github/tts_bandmate && flutter test test/features/auth/auth_repository_social_test.dart
```

- [ ] **Step 3: Implement**

`api_endpoints.dart`, next to `mobileToken`:

```dart
static const String mobileSocial = '/api/mobile/auth/social';
```

`app_config.dart`, after `googlePlacesApiKey`:

```dart
/// Google OAuth *web* client ID, passed to google_sign_in as serverClientId
/// so the returned idToken's `aud` is the web client the backend whitelists.
static const String googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '',
);
```

`auth_repository.dart`, after `register()`:

```dart
/// Exchange a verified social-provider token (Google/Apple id_token or
/// Facebook access token) for a Sanctum token. Same envelope as [login].
Future<({String token, AuthUser user, List<BandSummary> bands})> socialLogin(
  String provider,
  String token,
  String deviceName,
) async {
  final response = await _dio.post<Map<String, dynamic>>(
    ApiEndpoints.mobileSocial,
    data: {
      'provider': provider,
      'token': token,
      'device_name': deviceName,
    },
  );

  final data = response.data!;
  final newToken = data['token'] as String;
  final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  final bandList = (data['bands'] as List<dynamic>)
      .map((b) => BandSummary.fromJson(b as Map<String, dynamic>))
      .toList();

  return (token: newToken, user: user, bands: bandList);
}
```

- [ ] **Step 4: Run — expect PASS**, then `flutter analyze` (clean)

- [ ] **Step 5: Commit**

```bash
git add lib/core/network/api_endpoints.dart lib/core/config/app_config.dart lib/features/auth/data/auth_repository.dart test/features/auth/auth_repository_social_test.dart
git commit -m "feat(social-login): AuthRepository.socialLogin + endpoint constant"
```

---

### Task B2: Packages + `SocialSignInService` abstraction

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/features/auth/data/social_sign_in_service.dart`
- Create: `lib/features/auth/data/native_social_sign_in_service.dart`
- Create: `lib/features/auth/providers/social_sign_in_provider.dart`

**Interfaces:**
- Produces:
  - `enum SocialProvider { google, apple, facebook }` + `extension SocialProviderLabel` (`.label` → 'Google'/'Apple'/'Facebook')
  - `class SocialCredential { SocialProvider provider; String token; }`
  - `abstract class SocialSignInService { Future<SocialCredential?> signIn(SocialProvider provider); }` — **returns null on user cancel**, throws on real failure
  - `socialSignInServiceProvider` (Riverpod `Provider<SocialSignInService>`)

- [ ] **Step 1: Add packages**

```bash
flutter pub add google_sign_in sign_in_with_apple flutter_facebook_auth
```

⚠ **API drift risk is real here.** `google_sign_in` v7 replaced the v6 API (`GoogleSignIn.instance`, `initialize()`, `authenticate()`); `flutter_facebook_auth` renamed `accessToken.token` → `tokenString` in v7. The code below targets the v7-era APIs — after `pub add`, open each package's README and reconcile.

- [ ] **Step 2: Create the abstraction**

`lib/features/auth/data/social_sign_in_service.dart`:

```dart
enum SocialProvider { google, apple, facebook }

extension SocialProviderLabel on SocialProvider {
  String get label => switch (this) {
        SocialProvider.google => 'Google',
        SocialProvider.apple => 'Apple',
        SocialProvider.facebook => 'Facebook',
      };
}

class SocialCredential {
  const SocialCredential({required this.provider, required this.token});

  final SocialProvider provider;

  /// Google/Apple: OIDC id_token. Facebook: access token.
  final String token;
}

/// Wraps the native provider SDKs so the auth notifier can be unit-tested
/// with a fake. Implementations return null when the user cancels the
/// native sheet and throw on real failures.
abstract class SocialSignInService {
  Future<SocialCredential?> signIn(SocialProvider provider);
}
```

- [ ] **Step 3: Native implementation**

`lib/features/auth/data/native_social_sign_in_service.dart`:

```dart
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/config/app_config.dart';
import 'social_sign_in_service.dart';

class NativeSocialSignInService implements SocialSignInService {
  bool _googleInitialized = false;

  @override
  Future<SocialCredential?> signIn(SocialProvider provider) {
    return switch (provider) {
      SocialProvider.google => _google(),
      SocialProvider.apple => _apple(),
      SocialProvider.facebook => _facebook(),
    };
  }

  Future<SocialCredential?> _google() async {
    try {
      if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize(
          serverClientId: AppConfig.googleServerClientId,
        );
        _googleInitialized = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return null;
      return SocialCredential(provider: SocialProvider.google, token: idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  Future<SocialCredential?> _apple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final idToken = credential.identityToken;
      if (idToken == null) return null;
      return SocialCredential(provider: SocialProvider.apple, token: idToken);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }

  Future<SocialCredential?> _facebook() async {
    final result = await FacebookAuth.instance.login(
      permissions: const ['email', 'public_profile'],
    );
    switch (result.status) {
      case LoginStatus.success:
        return SocialCredential(
          provider: SocialProvider.facebook,
          token: result.accessToken!.tokenString,
        );
      case LoginStatus.cancelled:
        return null;
      default:
        throw StateError(result.message ?? 'Facebook sign-in failed');
    }
  }
}
```

`lib/features/auth/providers/social_sign_in_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/native_social_sign_in_service.dart';
import '../data/social_sign_in_service.dart';

final socialSignInServiceProvider = Provider<SocialSignInService>(
  (ref) => NativeSocialSignInService(),
);
```

- [ ] **Step 4: Verify it compiles** (native SDKs aren't unit-testable — B3 tests through the fake)

```bash
flutter analyze
```

Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/auth/data/social_sign_in_service.dart lib/features/auth/data/native_social_sign_in_service.dart lib/features/auth/providers/social_sign_in_provider.dart
git commit -m "feat(social-login): SocialSignInService abstraction over native SDKs"
```

---

### Task B3: `AuthNotifier.socialLogin`

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart`
- Test: `test/features/auth/auth_notifier_social_test.dart`

**Interfaces:**
- Consumes: `socialSignInServiceProvider` (B2), `AuthRepository.socialLogin` (B1).
- Produces: `AuthNotifier.socialLogin(SocialProvider provider)` — cancel leaves state untouched; success → `AuthAuthenticated`; failure → `AuthUnauthenticated(errorMessage)`.

- [ ] **Step 1: Write the failing test**

First find the existing fakes: `grep -rn "FakeSecureStorage\|apiClientProvider" test/ | head` and mirror their shapes. The test (adjust fake constructors to match what you find):

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/api_client.dart';
import 'package:tts_bandmate/core/network/api_endpoints.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'package:tts_bandmate/features/auth/data/social_sign_in_service.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/auth/providers/social_sign_in_provider.dart';

class _FakeDio extends Fake implements Dio {
  _FakeDio(this._responses);
  final Map<String, dynamic> _responses;

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
    if (body == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
            statusCode: 422, requestOptions: RequestOptions(path: path)),
      );
    }
    return Response<T>(
        data: body as T,
        statusCode: 200,
        requestOptions: RequestOptions(path: path));
  }
}

class _FakeApiClient extends Fake implements ApiClient {
  _FakeApiClient(this.dio);
  @override
  final Dio dio;
}

class _FakeSocialSignIn implements SocialSignInService {
  _FakeSocialSignIn(this.credential);
  final SocialCredential? credential;

  @override
  Future<SocialCredential?> signIn(SocialProvider provider) async => credential;
}

void main() {
  const envelope = {
    'token': 't-1',
    'user': {'id': 1, 'name': 'S', 'email': 's@e.com', 'avatar_url': null},
    'bands': <dynamic>[],
  };

  ProviderContainer makeContainer({
    required SocialCredential? credential,
    Map<String, dynamic> responses = const {ApiEndpoints.mobileSocial: envelope},
  }) {
    // Reuse the repo's existing FakeSecureStorage (grep test/ for it) in the
    // secureStorageProvider override below.
    return ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(_FakeApiClient(_FakeDio(responses))),
      socialSignInServiceProvider
          .overrideWithValue(_FakeSocialSignIn(credential)),
      // secureStorageProvider.overrideWithValue(FakeSecureStorage()),
    ]);
  }

  test('successful social login transitions to AuthAuthenticated', () async {
    final container = makeContainer(
      credential: const SocialCredential(
          provider: SocialProvider.google, token: 'id-tok'),
    );
    await container.read(authProvider.future);

    await container.read(authProvider.notifier).socialLogin(
          SocialProvider.google,
        );

    expect(container.read(authProvider).value, isA<AuthAuthenticated>());
  });

  test('cancelled native sheet leaves state untouched', () async {
    final container = makeContainer(credential: null);
    await container.read(authProvider.future);
    final before = container.read(authProvider).value;

    await container.read(authProvider.notifier).socialLogin(
          SocialProvider.apple,
        );

    expect(container.read(authProvider).value, same(before));
  });

  test('backend rejection surfaces a friendly error', () async {
    final container = makeContainer(
      credential: const SocialCredential(
          provider: SocialProvider.google, token: 'bad'),
      responses: const {}, // 422 from fake dio
    );
    await container.read(authProvider.future);

    await container.read(authProvider.notifier).socialLogin(
          SocialProvider.google,
        );

    final state = container.read(authProvider).value;
    expect(state, isA<AuthUnauthenticated>());
    expect((state as AuthUnauthenticated).errorMessage, contains('Google'));
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (`socialLogin` undefined)

```bash
flutter test test/features/auth/auth_notifier_social_test.dart
```

- [ ] **Step 3: Implement**

In `auth_provider.dart`, add imports for `social_sign_in_service.dart` and `social_sign_in_provider.dart`, then after `register()`:

```dart
/// Sign in with a social provider. The native sheet runs first (no state
/// change); only after we hold a credential do we enter AuthLoading.
/// A cancelled sheet leaves the state exactly as it was.
Future<void> socialLogin(SocialProvider provider) async {
  final storage = ref.read(secureStorageProvider);
  _repo ??= AuthRepository(ref.read(apiClientProvider).dio);

  final SocialCredential? credential;
  try {
    credential =
        await ref.read(socialSignInServiceProvider).signIn(provider);
  } catch (_) {
    state = AsyncValue.data(AuthUnauthenticated(
      errorMessage:
          'Could not start ${provider.label} sign-in. Please try again.',
    ));
    return;
  }

  if (credential == null) return; // user cancelled

  state = const AsyncValue.data(AuthLoading());

  state = await AsyncValue.guard(() async {
    final result = await _repository.socialLogin(
      credential.provider.name,
      credential.token,
      'tts_bandmate_app',
    );
    await storage.writeToken(result.token);
    await storage.writeUser(result.user.toJsonString());
    return AuthAuthenticated(user: result.user, bands: result.bands);
  });

  if (state.hasError) {
    state = AsyncValue.data(
      AuthUnauthenticated(
        errorMessage: _friendlySocialError(state.error, provider),
      ),
    );
  }

  if (state.value is AuthAuthenticated) {
    unawaited(_registerPushToken());
  }
}
```

And next to the other error helpers:

```dart
String _friendlySocialError(Object? error, SocialProvider provider) {
  final msg = error?.toString() ?? '';
  if (msg.contains('422')) {
    return 'Could not verify your ${provider.label} sign-in. Please try again.';
  }
  if (msg.contains('SocketException') ||
      msg.contains('connection') ||
      msg.contains('timeout')) {
    return 'Could not reach the server. Check your connection.';
  }
  return '${provider.label} sign-in failed. Please try again.';
}
```

- [ ] **Step 4: Run — expect PASS**, plus the whole auth suite

```bash
flutter test test/features/auth/
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/providers/auth_provider.dart test/features/auth/auth_notifier_social_test.dart
git commit -m "feat(social-login): AuthNotifier.socialLogin with cancel/error handling"
```

---

### Task B4: Social buttons UI on Welcome / Login / Sign-up screens

**Files:**
- Create: `lib/features/auth/widgets/social_login_buttons.dart`
- Modify: `lib/features/auth/screens/login_screen.dart`
- Modify: `lib/features/auth/screens/welcome_screen.dart`
- Modify: `lib/features/auth/screens/sign_up_screen.dart`

**Interfaces:**
- Consumes: `AuthNotifier.socialLogin` (B3).
- Produces: `SocialLoginButtons` widget (self-contained: divider, three buttons, its own error text, busy state). Renders nothing on web/desktop; Apple button iOS-only.

- [ ] **Step 1: Create the widget**

`lib/features/auth/widgets/social_login_buttons.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

import '../data/social_sign_in_service.dart';
import '../providers/auth_provider.dart';

/// "or continue with" divider + provider buttons. Native mobile only:
/// renders nothing on web/desktop. Apple shows only on iOS (App Store
/// policy requires it there; it isn't configured elsewhere).
class SocialLoginButtons extends ConsumerStatefulWidget {
  const SocialLoginButtons({super.key});

  @override
  ConsumerState<SocialLoginButtons> createState() => _SocialLoginButtonsState();
}

class _SocialLoginButtonsState extends ConsumerState<SocialLoginButtons> {
  SocialProvider? _busy;
  String? _error;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<void> _signIn(SocialProvider provider) async {
    setState(() {
      _busy = provider;
      _error = null;
    });

    await ref.read(authProvider.notifier).socialLogin(provider);

    if (!mounted) return;
    final state = ref.read(authProvider).value;
    setState(() {
      _busy = null;
      if (state is AuthUnauthenticated && state.errorMessage != null) {
        _error = state.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();

    final providers = [
      SocialProvider.google,
      if (defaultTargetPlatform == TargetPlatform.iOS) SocialProvider.apple,
      SocialProvider.facebook,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
              child: Container(
                  height: 0.5, color: CupertinoColors.separator.resolveFrom(context))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('or continue with',
                style: TextStyle(fontSize: 13, color: context.secondaryText)),
          ),
          Expanded(
              child: Container(
                  height: 0.5, color: CupertinoColors.separator.resolveFrom(context))),
        ]),
        const SizedBox(height: 16),
        for (final provider in providers) ...[
          _SocialButton(
            provider: provider,
            busy: _busy == provider,
            enabled: _busy == null,
            onPressed: () => _signIn(provider),
          ),
          const SizedBox(height: 10),
        ],
        if (_error != null) ...[
          const SizedBox(height: 2),
          Text(
            _error!,
            style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.systemRed.resolveFrom(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.provider,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final SocialProvider provider;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (provider) {
      SocialProvider.google => (
          CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          CupertinoColors.label.resolveFrom(context),
          CupertinoIcons.globe,
        ),
      SocialProvider.apple => (
          CupertinoColors.label.resolveFrom(context),
          CupertinoColors.systemBackground.resolveFrom(context),
          CupertinoIcons.device_phone_portrait,
        ),
      SocialProvider.facebook => (
          const Color(0xFF1877F2),
          CupertinoColors.white,
          CupertinoIcons.f_cursive,
        ),
    };

    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: background,
      borderRadius: BorderRadius.circular(10),
      onPressed: enabled ? onPressed : null,
      child: busy
          ? CupertinoActivityIndicator(color: foreground)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 8),
                Text('Continue with ${provider.label}',
                    style: TextStyle(fontSize: 15, color: foreground)),
              ],
            ),
    );
  }
}
```

(Placeholder Cupertino icons keep this dependency-free; if brand-accurate logos are wanted, add SVG assets in a follow-up. Consider delegating this task's visual polish to the flutter-ux-developer agent.)

- [ ] **Step 2: Integrate into the three screens**

- `login_screen.dart`: insert `const SocialLoginButtons(),` immediately after the `if (_loginError != null) ...[...]` block (before the `SizedBox(height: 24)` that precedes the "Don't have an account?" row).
- `sign_up_screen.dart`: same placement — after the submit button/error, before the "already have an account" footer (read the file to find the analogous spot).
- `welcome_screen.dart`: after the existing two buttons, add `const SocialLoginButtons()` at the bottom of the button column.

- [ ] **Step 3: Verify**

```bash
flutter analyze && flutter test
```

Expected: clean analyze, all tests pass (existing screen tests must not break).

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/widgets/social_login_buttons.dart lib/features/auth/screens/
git commit -m "feat(social-login): social buttons on welcome/login/signup screens"
```

---

### Task B5: Android + iOS platform configuration

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create/Modify: `android/app/src/main/res/values/strings.xml`
- Modify: `ios/Runner/Info.plist`
- Modify: `ios/Runner/Runner.entitlements`

- [ ] **Step 1: Android — Facebook**

In `android/app/src/main/res/values/strings.xml` (create if missing):

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="facebook_app_id">FACEBOOK_APP_ID_PLACEHOLDER</string>
    <string name="facebook_client_token">FACEBOOK_CLIENT_TOKEN_PLACEHOLDER</string>
    <string name="fb_login_protocol_scheme">fbFACEBOOK_APP_ID_PLACEHOLDER</string>
</resources>
```

In `AndroidManifest.xml` inside `<application>`:

```xml
<meta-data android:name="com.facebook.sdk.ApplicationId" android:value="@string/facebook_app_id"/>
<meta-data android:name="com.facebook.sdk.ClientToken" android:value="@string/facebook_client_token"/>
```

(Google needs no manifest change — `google-services.json` + `serverClientId` cover it.)

- [ ] **Step 2: iOS — Google, Facebook, Apple**

`ios/Runner/Info.plist` additions (real IDs come from the console-setup checklist in B6; placeholders keep the structure compilable):

```xml
<key>GIDClientID</key>
<string>IOS_GOOGLE_CLIENT_ID_PLACEHOLDER.apps.googleusercontent.com</string>
<key>FacebookAppID</key>
<string>FACEBOOK_APP_ID_PLACEHOLDER</string>
<key>FacebookClientToken</key>
<string>FACEBOOK_CLIENT_TOKEN_PLACEHOLDER</string>
<key>FacebookDisplayName</key>
<string>TTS Bandmate</string>
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>fbapi</string>
  <string>fb-messenger-share-api</string>
</array>
```

And append to the existing `CFBundleURLTypes` array:

```xml
<dict>
  <key>CFBundleURLSchemes</key>
  <array>
    <string>com.googleusercontent.apps.IOS_GOOGLE_CLIENT_ID_PLACEHOLDER</string>
    <string>fbFACEBOOK_APP_ID_PLACEHOLDER</string>
  </array>
</dict>
```

`ios/Runner/Runner.entitlements` — add inside the root `<dict>`:

```xml
<key>com.apple.developer.applesignin</key>
<array>
  <string>Default</string>
</array>
```

- [ ] **Step 3: Verify Android still builds** (iOS build needs a Mac — skip here)

```bash
flutter build apk --debug
```

Expected: builds. (Facebook SDK tolerates placeholder IDs at build time; sign-in will fail at runtime until real IDs land — that's the B6 checklist.)

- [ ] **Step 4: Commit**

```bash
git add android ios
git commit -m "feat(social-login): Android/iOS platform config for provider SDKs"
```

---

### Task B6: Console-setup checklist, full suite, PR

**Files:**
- Create: `docs/social-login-setup.md`

- [ ] **Step 1: Write the human checklist**

`docs/social-login-setup.md` — a checklist of every step only the account owner can do, with where each resulting value goes:

```markdown
# Social login — credential setup checklist

## Google (Google Cloud Console → APIs & Services → Credentials)
- [ ] OAuth client (Web) → `GOOGLE_SIGNIN_CLIENT_ID` / `GOOGLE_SIGNIN_CLIENT_SECRET` (TTS .env),
      also passed to the app as `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`
- [ ] OAuth client (Android): package `com.tts.bandmate` (verify in android/app/build.gradle.kts) + release AND debug SHA-1
- [ ] OAuth client (iOS): the app bundle id → its client id into Info.plist `GIDClientID` + reversed-id URL scheme
- [ ] `GOOGLE_SIGNIN_ALLOWED_CLIENT_IDS` (TTS .env) = web client id (Android/iOS sign-ins carry the web id as `aud` via serverClientId)
- [ ] Authorized redirect URI on the web client: https://tts.band/auth/google/callback (+ staging URL)

## Apple (developer.apple.com)
- [ ] Enable "Sign in with Apple" capability on the App ID
- [ ] Create a Services ID (web) with return URL https://tts.band/auth/apple/callback → `APPLE_SERVICES_CLIENT_ID`
- [ ] Create a Sign in with Apple key (.p8), generate the client-secret JWT → `APPLE_CLIENT_SECRET`
      ⚠ expires ≤ 6 months — diarize regeneration
- [ ] `APPLE_SIGNIN_ALLOWED_CLIENT_IDS` = app bundle id + Services ID (comma-separated)

## Facebook (developers.facebook.com)
- [ ] Create app, add "Facebook Login" product → `FACEBOOK_CLIENT_ID` / `FACEBOOK_CLIENT_SECRET`
- [ ] Enable Settings → Advanced → "Require App Secret"
- [ ] Add Android platform (package + key hashes) and iOS platform (bundle id)
- [ ] Replace FACEBOOK_APP_ID_PLACEHOLDER / FACEBOOK_CLIENT_TOKEN_PLACEHOLDER in
      android/app/src/main/res/values/strings.xml and ios/Runner/Info.plist
- [ ] Valid OAuth redirect URI: https://tts.band/auth/facebook/callback (+ staging)
- [ ] Switch the app to Live mode (app review) before public rollout

## Backend env (staging + prod)
All the GOOGLE_SIGNIN_* / APPLE_* / FACEBOOK_* vars from .env.example.
```

- [ ] **Step 2: Full suite + analyze**

```bash
flutter analyze && flutter test
```

- [ ] **Step 3: Push + PR to main**

```bash
git push -u origin feat/social-login
gh pr create --base main --title "Social login: Google / Apple / Facebook" --body "..."
```

PR body: link the spec + backend PR, note the dart-define (`GOOGLE_SERVER_CLIENT_ID`), the placeholder IDs pending console setup, and that on-device verification is blocked on the B6 checklist.

- [ ] **Step 4: Wait for Copilot review and address comments** (required — memory)

- [ ] **Step 5: On-device verification (after console setup)**

Use the run-on-device skill: Google sign-in on the Android phone against the local backend (needs the debug SHA-1 registered). Apple/Facebook and iOS require credentials/hardware — track as follow-up if unavailable.

---

## Execution order & dependencies

- A1→A2→A3→A4→A5→A6→A7→A8→A9 strictly in order (each consumes the previous).
- Part B can start any time after A6 exists on a reachable backend for manual testing, but B1–B4 are testable against fakes with no backend at all — only B6's on-device step needs the deployed backend + credentials.
- B1→B2→B3→B4 in order; B5 independent after B2; B6 last.
