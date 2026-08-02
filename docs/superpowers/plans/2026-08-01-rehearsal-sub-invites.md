# Rehearsal Sub Invites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Band leaders can invite substitutes to an individual rehearsal (from the schedule list or the detail screen); the sub is attached immediately, notified by email (+ push if registered), and sees the rehearsal in their own app.

**Architecture:** New `rehearsal_subs` table + mobile endpoints in the TTS Laravel backend (Part A), consumed by the Flutter app (Part B). Notification jobs mirror `ProcessRehearsalCancelled`; the invite picker mirrors the event sub-picker but is slot-less (call lists grouped by instrument + ad-hoc email form). Sub read-visibility follows the existing "sub may read, controller scopes" pattern in `User::canRead()`.

**Tech Stack:** Laravel 10 (Sanctum tokens, queued jobs, markdown mailables), Flutter/Dart (Riverpod v2, Cupertino, Dio, hand-written fromJson).

## Global Constraints

- **TTS repo (`/home/eddie/github/TTS`):** never run php/artisan/composer/phpunit on the host — always `docker compose exec app …`. PRs target `staging` (`gh pr create --base staging`). Merging to staging auto-deploys.
- **Mobile repo (`/home/eddie/github/tts_bandmate`):** PRs target `main`. Branch `feat/rehearsal-sub-invites` already exists with the spec committed.
- **Backend before mobile:** the app tolerates a missing `subs` key (defaults to empty), but the invite UI 404s against an old backend — deploy TTS to staging before merging the app PR, and promote to prod before any store rollout.
- **Wire contract** (frozen once Part A merges):
  - `RehearsalService::formatDetail()` gains `"subs": [{"id", "name", "email", "phone", "band_role_id", "role_name", "user_id", "is_registered"}]`.
  - `POST /api/mobile/rehearsals/{rehearsal}/subs` body: `{"call_list_entry_id": int}` **or** `{"name": str, "email": str, "phone"?: str, "band_role_id"?: int}`. Returns `201 {"subs": [...]}` (same shape as detail).
  - `DELETE /api/mobile/rehearsals/{rehearsal}/subs/{sub}` returns `200 {"subs": [...]}`.
  - Push types: `rehearsal_sub_added`, `rehearsal_sub_removed` — payload `{type, title, body, rehearsalId, date?}`, sent with `alert = true`.
- **Permissions:** writes gated `canWrite('rehearsals', $band->id)` in controllers. App-side, invite UI shows only for band owners (`BandSummary.isOwner`) because the call-lists endpoint is owner-only.
- **Dark mode:** use `context.secondaryText` / `context.tertiaryText` (never raw `CupertinoColors.secondaryLabel` in a `color:`).
- **Dates in tests:** never hardcode future dates — compute relative to `now()` (backend) / `DateTime.now()` (Flutter).
- After each `gh pr create`, wait for Copilot's auto-review and address its comments.

---

# Part A — Backend (TTS repo)

Work on a new branch: `cd /home/eddie/github/TTS && git checkout staging && git pull && git checkout -b feat/rehearsal-subs`.

Run tests with: `docker compose exec app php artisan test --filter=<Name>`.

### Task A1: `rehearsal_subs` table, model, factory, relation

**Files:**
- Create: `database/migrations/2026_08_01_000001_create_rehearsal_subs_table.php`
- Create: `app/Models/RehearsalSub.php`
- Create: `database/factories/RehearsalSubFactory.php`
- Modify: `app/Models/Rehearsal.php` (add `subs()` relation, after `bookings()` ~line 82)
- Test: `tests/Feature/Api/Mobile/RehearsalSubsTest.php` (created here, grows in later tasks)

**Interfaces:**
- Produces: `App\Models\RehearsalSub` (SoftDeletes; fillable `rehearsal_id, band_id, band_role_id, user_id, name, email, phone, notes, invited_by`; relations `rehearsal()`, `band()`, `bandRole()`, `user()`), `Rehearsal::subs(): HasMany`, `RehearsalSub::factory()`.

- [ ] **Step 1: Write the failing test**

Create `tests/Feature/Api/Mobile/RehearsalSubsTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\Bands;
use App\Models\Events;
use App\Models\EventTypes;
use App\Models\Rehearsal;
use App\Models\RehearsalSchedule;
use App\Models\RehearsalSub;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RehearsalSubsTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Owner + band + schedule + one materialized upcoming rehearsal.
     * Mirrors RehearsalsTest::createUserWithBandAndRehearsal().
     */
    private function createOwnerWithRehearsal(int $daysFromNow = 7): array
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $schedule = RehearsalSchedule::factory()->weekly()->create(['band_id' => $band->id]);

        $rehearsal = Rehearsal::factory()->create([
            'rehearsal_schedule_id' => $schedule->id,
            'band_id'               => $band->id,
        ]);

        $eventType = EventTypes::factory()->create();

        $event = Events::factory()->create([
            'eventable_id'   => $rehearsal->id,
            'eventable_type' => 'App\\Models\\Rehearsal',
            'event_type_id'  => $eventType->id,
            'date'           => now()->addDays($daysFromNow)->format('Y-m-d'),
            'start_time'     => '19:00:00',
        ]);

        $token = $user->createToken('test-device')->plainTextToken;

        return compact('user', 'band', 'schedule', 'rehearsal', 'event', 'token');
    }

    public function test_rehearsal_has_subs_relation(): void
    {
        ['rehearsal' => $rehearsal, 'band' => $band] = $this->createOwnerWithRehearsal();

        $sub = RehearsalSub::factory()->create([
            'rehearsal_id' => $rehearsal->id,
            'band_id'      => $band->id,
        ]);

        $this->assertTrue($rehearsal->subs->contains('id', $sub->id));
        $this->assertSame($rehearsal->id, $sub->rehearsal->id);
    }

    public function test_soft_deleted_sub_is_excluded_from_relation(): void
    {
        ['rehearsal' => $rehearsal, 'band' => $band] = $this->createOwnerWithRehearsal();

        $sub = RehearsalSub::factory()->create([
            'rehearsal_id' => $rehearsal->id,
            'band_id'      => $band->id,
        ]);
        $sub->delete();

        $this->assertFalse($rehearsal->fresh()->subs->contains('id', $sub->id));
        $this->assertNotNull(RehearsalSub::withTrashed()->find($sub->id));
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=RehearsalSubsTest`
Expected: FAIL — `Class "App\Models\RehearsalSub" not found`.

- [ ] **Step 3: Write migration, model, factory, relation**

`database/migrations/2026_08_01_000001_create_rehearsal_subs_table.php`:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('rehearsal_subs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('rehearsal_id')->constrained()->onDelete('cascade');
            $table->foreignId('band_id')->constrained()->onDelete('cascade');
            $table->foreignId('band_role_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->onDelete('cascade');

            $table->string('name');
            $table->string('email');
            $table->string('phone')->nullable();
            $table->text('notes')->nullable();

            $table->foreignId('invited_by')->nullable()->constrained('users')->nullOnDelete();

            $table->timestamps();
            $table->softDeletes();

            // One live row per registered user per rehearsal. MySQL allows
            // multiple NULL user_ids, so ad-hoc invitees don't collide here;
            // they're deduped by (rehearsal_id, email) in the service layer.
            $table->unique(['rehearsal_id', 'user_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('rehearsal_subs');
    }
};
```

`app/Models/RehearsalSub.php`:

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class RehearsalSub extends Model
{
    use HasFactory, SoftDeletes;

    protected $fillable = [
        'rehearsal_id',
        'band_id',
        'band_role_id',
        'user_id',
        'name',
        'email',
        'phone',
        'notes',
        'invited_by',
    ];

    public function rehearsal(): BelongsTo
    {
        return $this->belongsTo(Rehearsal::class);
    }

    public function band(): BelongsTo
    {
        return $this->belongsTo(Bands::class, 'band_id');
    }

    public function bandRole(): BelongsTo
    {
        return $this->belongsTo(BandRole::class, 'band_role_id');
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function isRegisteredUser(): bool
    {
        return $this->user_id !== null;
    }
}
```

`database/factories/RehearsalSubFactory.php`:

```php
<?php

namespace Database\Factories;

use App\Models\Bands;
use App\Models\Rehearsal;
use Illuminate\Database\Eloquent\Factories\Factory;

class RehearsalSubFactory extends Factory
{
    public function definition(): array
    {
        return [
            'rehearsal_id' => Rehearsal::factory(),
            'band_id'      => Bands::factory(),
            'band_role_id' => null,
            'user_id'      => null,
            'name'         => $this->faker->name(),
            'email'        => $this->faker->unique()->safeEmail(),
            'phone'        => null,
            'notes'        => null,
            'invited_by'   => null,
        ];
    }
}
```

`app/Models/Rehearsal.php` — add after the `bookings()` method:

```php
    /**
     * Substitutes invited to this specific rehearsal.
     */
    public function subs()
    {
        return $this->hasMany(RehearsalSub::class);
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=RehearsalSubsTest`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add database/migrations/2026_08_01_000001_create_rehearsal_subs_table.php app/Models/RehearsalSub.php database/factories/RehearsalSubFactory.php app/Models/Rehearsal.php tests/Feature/Api/Mobile/RehearsalSubsTest.php
git commit -m "feat(rehearsals): rehearsal_subs table + RehearsalSub model"
```

---

### Task A2: `User` sub-visibility helpers + `canRead('rehearsals')` carve-out

**Files:**
- Modify: `app/Models/User.php` (carve-out inside `canRead()` ~line 224; two new methods after `canWrite()` ~line 266)
- Test: `tests/Feature/Api/Mobile/RehearsalSubVisibilityTest.php` (created here, grows in Task A6)

**Interfaces:**
- Consumes: `rehearsal_subs` table (Task A1).
- Produces: `User::hasRehearsalSubAssignmentForBand(int $bandId): bool`, `User::canReadRehearsalsAsMember(int $bandId): bool`, and `canRead('rehearsals', $bandId)` returning true for subs with a live invite.

- [ ] **Step 1: Write the failing test**

Create `tests/Feature/Api/Mobile/RehearsalSubVisibilityTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\Bands;
use App\Models\BandSubs;
use App\Models\Events;
use App\Models\EventTypes;
use App\Models\Rehearsal;
use App\Models\RehearsalSchedule;
use App\Models\RehearsalSub;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RehearsalSubVisibilityTest extends TestCase
{
    use RefreshDatabase;

    /**
     * A band (with an owner), one upcoming materialized rehearsal, and a
     * separate sub user linked via band_subs. Returns everything needed to
     * add rehearsal_subs rows and mint sub tokens.
     */
    private function createBandWithSubUser(): array
    {
        $owner = User::factory()->create();
        $band  = Bands::factory()->create();
        $band->owners()->create(['user_id' => $owner->id]);

        $schedule = RehearsalSchedule::factory()->weekly()->create(['band_id' => $band->id]);

        $rehearsal = Rehearsal::factory()->create([
            'rehearsal_schedule_id' => $schedule->id,
            'band_id'               => $band->id,
        ]);

        $eventType = EventTypes::factory()->create();
        Events::factory()->create([
            'eventable_id'   => $rehearsal->id,
            'eventable_type' => 'App\\Models\\Rehearsal',
            'event_type_id'  => $eventType->id,
            'date'           => now()->addDays(7)->format('Y-m-d'),
            'start_time'     => '19:00:00',
        ]);

        $subUser = User::factory()->create();
        BandSubs::create(['user_id' => $subUser->id, 'band_id' => $band->id]);

        return compact('owner', 'band', 'schedule', 'rehearsal', 'subUser');
    }

    public function test_sub_without_invite_cannot_read_rehearsals(): void
    {
        ['band' => $band, 'subUser' => $subUser] = $this->createBandWithSubUser();

        $this->assertFalse($subUser->canRead('rehearsals', $band->id));
        $this->assertFalse($subUser->hasRehearsalSubAssignmentForBand($band->id));
    }

    public function test_sub_with_live_invite_can_read_rehearsals_but_not_as_member(): void
    {
        ['band' => $band, 'rehearsal' => $rehearsal, 'subUser' => $subUser] =
            $this->createBandWithSubUser();

        RehearsalSub::factory()->create([
            'rehearsal_id' => $rehearsal->id,
            'band_id'      => $band->id,
            'user_id'      => $subUser->id,
            'email'        => $subUser->email,
        ]);

        $this->assertTrue($subUser->canRead('rehearsals', $band->id));
        $this->assertTrue($subUser->hasRehearsalSubAssignmentForBand($band->id));
        $this->assertFalse($subUser->canReadRehearsalsAsMember($band->id));
    }

    public function test_soft_deleted_invite_does_not_grant_read(): void
    {
        ['band' => $band, 'rehearsal' => $rehearsal, 'subUser' => $subUser] =
            $this->createBandWithSubUser();

        $sub = RehearsalSub::factory()->create([
            'rehearsal_id' => $rehearsal->id,
            'band_id'      => $band->id,
            'user_id'      => $subUser->id,
            'email'        => $subUser->email,
        ]);
        $sub->delete();

        $this->assertFalse($subUser->canRead('rehearsals', $band->id));
    }

    public function test_owner_reads_rehearsals_as_member(): void
    {
        ['band' => $band, 'owner' => $owner] = $this->createBandWithSubUser();

        $this->assertTrue($owner->canReadRehearsalsAsMember($band->id));
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=RehearsalSubVisibilityTest`
Expected: FAIL — `Call to undefined method App\Models\User::hasRehearsalSubAssignmentForBand()`.

- [ ] **Step 3: Implement the User changes**

In `app/Models/User.php`, inside `canRead()` — insert between the `songs` carve-out block (ends ~line 243) and the `setPermissionsTeamId($bandId);` line:

```php
        // A sub may read rehearsals they've been invited to (a live
        // rehearsal_subs row). Controllers must scope results to those
        // rehearsals — mirrors the events/charts pattern above.
        if ($resource === 'rehearsals' && $this->isSubOfBand($bandId)
            && $this->hasRehearsalSubAssignmentForBand($bandId)) {
            return true;
        }
```

After `canWrite()` (~line 266), add:

```php
    /**
     * Does this user have at least one live rehearsal-sub invite in this band?
     */
    public function hasRehearsalSubAssignmentForBand(int $bandId): bool
    {
        return \DB::table('rehearsal_subs')
            ->where('user_id', $this->id)
            ->where('band_id', $bandId)
            ->whereNull('deleted_at')
            ->exists();
    }

    /**
     * Can this user read rehearsals through band membership (owner or the
     * read:rehearsals permission) — i.e. WITHOUT the rehearsal-sub carve-out?
     * Controllers use this to decide whether to scope rehearsal reads down to
     * the user's own invites.
     */
    public function canReadRehearsalsAsMember(int $bandId): bool
    {
        if ($this->ownsBand($bandId)) {
            return true;
        }

        setPermissionsTeamId($bandId);
        $result = $this->hasPermissionTo('read:rehearsals');
        setPermissionsTeamId(0);

        return $result;
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=RehearsalSubVisibilityTest`
Expected: PASS (4 tests). Also run `docker compose exec app php artisan test --filter=SubCrossBandPermissionTest` — the canRead change must not regress the cross-band leak tests.

- [ ] **Step 5: Commit**

```bash
git add app/Models/User.php tests/Feature/Api/Mobile/RehearsalSubVisibilityTest.php
git commit -m "feat(rehearsals): sub read carve-out for invited rehearsal subs"
```

---

### Task A3: Invite service + POST endpoint + `subs` in detail payload

**Files:**
- Create: `app/Services/RehearsalSubService.php`
- Create: `app/Http/Requests/Mobile/StoreRehearsalSubRequest.php`
- Create: `app/Http/Controllers/Api/Mobile/RehearsalSubsController.php`
- Modify: `app/Services/Mobile/RehearsalService.php` (add `formatSubs()`; add `subs` key to `formatDetail()`)
- Modify: `routes/api.php` (two routes after the existing `/rehearsals/{rehearsal}` group ~line 369)
- Test: `tests/Feature/Api/Mobile/RehearsalSubsTest.php`

**Interfaces:**
- Consumes: `RehearsalSub`, `Rehearsal::subs()` (A1); `SubstituteCallList` display accessors (`display_name`, `display_email`, `display_phone`, `band_role_id`, `rosterMember->user_id`); `BandSubs`.
- Produces: `RehearsalSubService::invite(Rehearsal $rehearsal, User $actor, array $data): RehearsalSub` (throws `ValidationException` on cancelled/past/duplicate/no-email); `RehearsalService::formatSubs(Rehearsal $rehearsal): array`; routes `mobile.rehearsals.subs.store`. `ProcessRehearsalSubAdded::dispatch(...)` is called here but the job class arrives in Task A4 — this task stubs nothing: write the `use` + dispatch line in the service **in Task A4**; in this task the service ends by returning the sub (see Step 3 note).

- [ ] **Step 1: Write the failing tests**

Append to `tests/Feature/Api/Mobile/RehearsalSubsTest.php`:

```php
    private function postSub(array $ctx, array $body)
    {
        return $this->withToken($ctx['token'])
            ->withHeaders(['X-Band-ID' => $ctx['band']->id])
            ->postJson("/api/mobile/rehearsals/{$ctx['rehearsal']->id}/subs", $body);
    }

    public function test_adhoc_invite_creates_sub_and_returns_subs_list(): void
    {
        $ctx = $this->createOwnerWithRehearsal();

        $response = $this->postSub($ctx, [
            'name'  => 'Pat Horn',
            'email' => 'pat@example.com',
            'phone' => '555-0100',
        ]);

        $response->assertCreated()
            ->assertJsonPath('subs.0.name', 'Pat Horn')
            ->assertJsonPath('subs.0.email', 'pat@example.com')
            ->assertJsonPath('subs.0.is_registered', false);

        $this->assertDatabaseHas('rehearsal_subs', [
            'rehearsal_id' => $ctx['rehearsal']->id,
            'band_id'      => $ctx['band']->id,
            'email'        => 'pat@example.com',
            'user_id'      => null,
            'invited_by'   => $ctx['user']->id,
        ]);
    }

    public function test_adhoc_invite_links_registered_user_and_ensures_band_sub(): void
    {
        $ctx = $this->createOwnerWithRehearsal();
        $registered = \App\Models\User::factory()->create(['email' => 'reg@example.com']);

        $this->postSub($ctx, ['name' => 'Reg', 'email' => 'reg@example.com'])
            ->assertCreated()
            ->assertJsonPath('subs.0.is_registered', true);

        $this->assertDatabaseHas('rehearsal_subs', [
            'rehearsal_id' => $ctx['rehearsal']->id,
            'user_id'      => $registered->id,
        ]);
        $this->assertDatabaseHas('band_subs', [
            'user_id' => $registered->id,
            'band_id' => $ctx['band']->id,
        ]);
    }

    public function test_call_list_invite_resolves_person_and_role(): void
    {
        $ctx = $this->createOwnerWithRehearsal();

        $role = \App\Models\BandRole::factory()->create(['band_id' => $ctx['band']->id]);
        $entry = \App\Models\SubstituteCallList::create([
            'band_id'      => $ctx['band']->id,
            'instrument'   => 'Trumpet',
            'band_role_id' => $role->id,
            'custom_name'  => 'Callie List',
            'custom_email' => 'callie@example.com',
            'priority'     => 1,
        ]);

        $this->postSub($ctx, ['call_list_entry_id' => $entry->id])
            ->assertCreated()
            ->assertJsonPath('subs.0.name', 'Callie List')
            ->assertJsonPath('subs.0.band_role_id', $role->id);
    }

    public function test_call_list_entry_from_other_band_is_rejected(): void
    {
        $ctx = $this->createOwnerWithRehearsal();
        $otherBand = Bands::factory()->create();
        $entry = \App\Models\SubstituteCallList::create([
            'band_id'      => $otherBand->id,
            'instrument'   => 'Guitar',
            'custom_name'  => 'Wrong Band',
            'custom_email' => 'wrong@example.com',
            'priority'     => 1,
        ]);

        $this->postSub($ctx, ['call_list_entry_id' => $entry->id])->assertNotFound();
    }

    public function test_duplicate_invite_returns_422(): void
    {
        $ctx = $this->createOwnerWithRehearsal();

        $this->postSub($ctx, ['name' => 'Pat', 'email' => 'pat@example.com'])->assertCreated();
        $this->postSub($ctx, ['name' => 'Pat', 'email' => 'pat@example.com'])
            ->assertUnprocessable();
    }

    public function test_reinvite_after_removal_restores_soft_deleted_row(): void
    {
        $ctx = $this->createOwnerWithRehearsal();

        $this->postSub($ctx, ['name' => 'Pat', 'email' => 'pat@example.com'])->assertCreated();
        $sub = RehearsalSub::where('email', 'pat@example.com')->first();
        $sub->delete();

        $this->postSub($ctx, ['name' => 'Pat', 'email' => 'pat@example.com'])->assertCreated();

        $this->assertSame(1, RehearsalSub::withTrashed()->where('email', 'pat@example.com')->count());
        $this->assertNull($sub->fresh()->deleted_at);
    }

    public function test_invite_to_cancelled_rehearsal_is_blocked(): void
    {
        $ctx = $this->createOwnerWithRehearsal();
        $ctx['rehearsal']->update(['is_cancelled' => true]);

        $this->postSub($ctx, ['name' => 'Pat', 'email' => 'pat@example.com'])
            ->assertUnprocessable();
    }

    public function test_invite_to_past_rehearsal_is_blocked(): void
    {
        $ctx = $this->createOwnerWithRehearsal(daysFromNow: -3);

        $this->postSub($ctx, ['name' => 'Pat', 'email' => 'pat@example.com'])
            ->assertUnprocessable();
    }

    public function test_non_writer_cannot_invite(): void
    {
        $ctx = $this->createOwnerWithRehearsal();

        $outsideSub = \App\Models\User::factory()->create();
        \App\Models\BandSubs::create(['user_id' => $outsideSub->id, 'band_id' => $ctx['band']->id]);
        $subToken = $outsideSub->createToken('sub-device')->plainTextToken;

        $this->withToken($subToken)
            ->withHeaders(['X-Band-ID' => $ctx['band']->id])
            ->postJson("/api/mobile/rehearsals/{$ctx['rehearsal']->id}/subs", [
                'name' => 'X', 'email' => 'x@example.com',
            ])
            ->assertForbidden();
    }

    public function test_detail_includes_subs_array(): void
    {
        $ctx = $this->createOwnerWithRehearsal();
        RehearsalSub::factory()->create([
            'rehearsal_id' => $ctx['rehearsal']->id,
            'band_id'      => $ctx['band']->id,
            'name'         => 'Detail Sub',
        ]);

        $this->withToken($ctx['token'])
            ->withHeaders(['X-Band-ID' => $ctx['band']->id])
            ->getJson("/api/mobile/rehearsals/{$ctx['rehearsal']->id}")
            ->assertOk()
            ->assertJsonPath('rehearsal.subs.0.name', 'Detail Sub')
            ->assertJsonStructure(['rehearsal' => ['subs' => ['*' => [
                'id', 'name', 'email', 'phone', 'band_role_id', 'role_name',
                'user_id', 'is_registered',
            ]]]]);
    }
```

Add these imports at the top of the test file: `use App\Models\BandRole; use App\Models\SubstituteCallList; use App\Models\BandSubs;` (or reference fully-qualified as written above). If `BandRole` has no factory, create the role with `BandRole::create(['band_id' => ..., 'name' => 'Trumpet'])` instead — check `database/factories/` first.

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=RehearsalSubsTest`
Expected: new tests FAIL (404 route not found); A1's two tests still PASS.

- [ ] **Step 3: Implement service, request, controller, routes, formatSubs**

`app/Services/RehearsalSubService.php`:

```php
<?php

namespace App\Services;

use App\Models\BandSubs;
use App\Models\Rehearsal;
use App\Models\RehearsalSub;
use App\Models\SubstituteCallList;
use App\Models\User;
use Illuminate\Validation\ValidationException;

class RehearsalSubService
{
    /**
     * Attach a substitute to a rehearsal (assignment + notification model —
     * no accept step). $data is either ['call_list_entry_id' => int] or
     * ['name', 'email', 'phone'?, 'band_role_id'?].
     *
     * @throws ValidationException on cancelled/past rehearsal, duplicate, or
     *         a call-list entry with no email.
     */
    public function invite(Rehearsal $rehearsal, User $actor, array $data): RehearsalSub
    {
        $band  = $rehearsal->rehearsalSchedule?->band ?? $rehearsal->band;
        $event = $rehearsal->events->first();
        $date  = $event
            ? (is_string($event->date) ? $event->date : $event->date->format('Y-m-d'))
            : null;

        if ($rehearsal->is_cancelled) {
            throw ValidationException::withMessages([
                'rehearsal' => 'This rehearsal has been cancelled.',
            ]);
        }
        if ($date !== null && $date < now()->toDateString()) {
            throw ValidationException::withMessages([
                'rehearsal' => 'This rehearsal has already happened.',
            ]);
        }

        if (isset($data['call_list_entry_id'])) {
            $entry = SubstituteCallList::where('band_id', $band->id)
                ->findOrFail($data['call_list_entry_id']);

            $name   = $entry->display_name;
            $email  = $entry->display_email;
            $phone  = $entry->display_phone;
            $roleId = $entry->band_role_id;
            $userId = $entry->rosterMember?->user_id;
        } else {
            $name   = $data['name'];
            $email  = $data['email'];
            $phone  = $data['phone'] ?? null;
            $roleId = $data['band_role_id'] ?? null;
            $userId = null;
        }

        if (!$email) {
            throw ValidationException::withMessages([
                'email' => 'This call list entry has no email address — add one to the call list first.',
            ]);
        }

        $userId ??= User::where('email', $email)->value('id');

        $match = $userId
            ? ['rehearsal_id' => $rehearsal->id, 'user_id' => $userId]
            : ['rehearsal_id' => $rehearsal->id, 'email' => $email];

        $existing = RehearsalSub::withTrashed()->where($match)->first();

        if ($existing && !$existing->trashed()) {
            throw ValidationException::withMessages([
                'sub' => "{$existing->name} is already invited to this rehearsal.",
            ]);
        }

        $attributes = [
            'rehearsal_id' => $rehearsal->id,
            'band_id'      => $band->id,
            'band_role_id' => $roleId,
            'user_id'      => $userId,
            'name'         => $name,
            'email'        => $email,
            'phone'        => $phone,
            'invited_by'   => $actor->id,
        ];

        if ($existing) {
            $existing->restore();
            $existing->fill($attributes)->save();
            $sub = $existing;
        } else {
            $sub = RehearsalSub::create($attributes);
        }

        // Registered subs join the band's sub bench (same side effect as
        // SubInvitationService::inviteSubToEvent()).
        if ($userId) {
            BandSubs::firstOrCreate(['user_id' => $userId, 'band_id' => $band->id]);

            $user = User::find($userId);
            if ($user && !$user->hasRole('sub')) {
                $user->assignRole('sub');
            }
        }

        return $sub;
    }
}
```

(Note: the `ProcessRehearsalSubAdded::dispatch(...)` line is added to this method in Task A4, right before `return $sub;` — keeping this task's tests free of Queue concerns.)

`app/Http/Requests/Mobile/StoreRehearsalSubRequest.php`:

```php
<?php

namespace App\Http\Requests\Mobile;

use Illuminate\Foundation\Http\FormRequest;

class StoreRehearsalSubRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // canWrite check happens in the controller
    }

    public function rules(): array
    {
        return [
            'call_list_entry_id' => ['nullable', 'required_without:email', 'integer'],
            'name'  => ['nullable', 'required_without:call_list_entry_id', 'string', 'max:255'],
            'email' => ['nullable', 'required_without:call_list_entry_id', 'email', 'max:255'],
            'phone' => ['nullable', 'string', 'max:50'],
            'band_role_id' => ['nullable', 'integer', 'exists:band_roles,id'],
        ];
    }
}
```

`app/Http/Controllers/Api/Mobile/RehearsalSubsController.php`:

```php
<?php

namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Http\Requests\Mobile\StoreRehearsalSubRequest;
use App\Models\Rehearsal;
use App\Services\Mobile\RehearsalService;
use App\Services\RehearsalSubService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class RehearsalSubsController extends Controller
{
    public function __construct(
        private readonly RehearsalSubService $subService,
        private readonly RehearsalService $rehearsalService,
    ) {}

    /**
     * POST /api/mobile/rehearsals/{rehearsal}/subs
     */
    public function store(StoreRehearsalSubRequest $request, int $rehearsal): JsonResponse
    {
        [$rehearsalModel, $band] = $this->resolveWritable($request, $rehearsal);

        $this->subService->invite($rehearsalModel, $request->user(), $request->validated());

        return response()->json(
            ['subs' => $this->rehearsalService->formatSubs($rehearsalModel)],
            201,
        );
    }

    /**
     * DELETE /api/mobile/rehearsals/{rehearsal}/subs/{sub}
     * (Implemented in a later task — route registered there too.)
     */

    /**
     * Resolve the rehearsal + band and enforce canWrite('rehearsals').
     *
     * @return array{0: Rehearsal, 1: \App\Models\Bands}
     */
    private function resolveWritable(Request $request, int $rehearsalId): array
    {
        $rehearsalModel = Rehearsal::with(['rehearsalSchedule.band', 'events'])
            ->findOrFail($rehearsalId);

        $band = $rehearsalModel->rehearsalSchedule?->band ?? $rehearsalModel->band;

        if (!$band) {
            abort(404, 'Band not found for this rehearsal.');
        }

        if (!$request->user()->canWrite('rehearsals', $band->id)) {
            abort(403, 'You do not have permission to manage subs for this rehearsal.');
        }

        return [$rehearsalModel, $band];
    }
}
```

`app/Services/Mobile/RehearsalService.php` — add method after `formatDetail()`, and add the key inside `formatDetail()`'s return array (after `'associated_bookings' => $associatedBookings,`):

```php
            'subs'                => $this->formatSubs($rehearsal),
```

```php
    /**
     * The rehearsal's invited substitutes, oldest first. Shared by the detail
     * payload and the subs store/destroy responses.
     */
    public function formatSubs(Rehearsal $rehearsal): array
    {
        return $rehearsal->subs()
            ->with(['bandRole', 'user'])
            ->orderBy('created_at')
            ->get()
            ->map(fn ($sub) => [
                'id'            => $sub->id,
                'name'          => $sub->name,
                'email'         => $sub->email,
                'phone'         => $sub->phone,
                'band_role_id'  => $sub->band_role_id,
                'role_name'     => $sub->bandRole?->name,
                'user_id'       => $sub->user_id,
                'is_registered' => $sub->user_id !== null,
            ])
            ->values()
            ->all();
    }
```

`routes/api.php` — directly after the `mobile.rehearsals.show` route (~line 369):

```php
        Route::post('/rehearsals/{rehearsal}/subs', [App\Http\Controllers\Api\Mobile\RehearsalSubsController::class, 'store'])->name('mobile.rehearsals.subs.store');
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=RehearsalSubsTest`
Expected: PASS (12 tests). Also run `--filter=RehearsalsTest` — `formatDetail` change must not break existing assertions.

- [ ] **Step 5: Commit**

```bash
git add app/Services/RehearsalSubService.php app/Http/Requests/Mobile/StoreRehearsalSubRequest.php app/Http/Controllers/Api/Mobile/RehearsalSubsController.php app/Services/Mobile/RehearsalService.php routes/api.php tests/Feature/Api/Mobile/RehearsalSubsTest.php
git commit -m "feat(rehearsals): POST /rehearsals/{id}/subs + subs in detail payload"
```

---

### Task A4: Invite notifications — mailables, views, `ProcessRehearsalSubAdded`

**Files:**
- Create: `app/Mail/RehearsalSubAdded.php`
- Create: `app/Mail/RehearsalSubNotice.php`
- Create: `resources/views/email/rehearsal-sub-added.blade.php`
- Create: `resources/views/email/rehearsal-sub-notice.blade.php`
- Create: `app/Jobs/ProcessRehearsalSubAdded.php`
- Modify: `app/Services/RehearsalSubService.php` (dispatch before `return $sub;`)
- Test: `tests/Feature/Api/Mobile/RehearsalSubNotificationsTest.php`

**Interfaces:**
- Consumes: `RehearsalSub` (A1), `RehearsalSubService::invite()` (A3), `SendUserPush::dispatch(int $userId, array $data, string $dedupeKey, bool $alert)`.
- Produces: `ProcessRehearsalSubAdded::dispatch(RehearsalSub $sub, int $actorId, string $dedupeKey)`; `App\Mail\RehearsalSubAdded(RehearsalSub $sub, Rehearsal $rehearsal, Bands $band, ?string $date)`; `App\Mail\RehearsalSubNotice(string $subjectLine, string $bodyText, string $bandName)` — the generic short notice reused by A5 (removal) and A7 (cancellation).

- [ ] **Step 1: Write the failing tests**

Create `tests/Feature/Api/Mobile/RehearsalSubNotificationsTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Jobs\ProcessRehearsalSubAdded;
use App\Jobs\SendUserPush;
use App\Mail\RehearsalSubAdded;
use App\Models\Bands;
use App\Models\DeviceToken;
use App\Models\Events;
use App\Models\EventTypes;
use App\Models\Rehearsal;
use App\Models\RehearsalSchedule;
use App\Models\RehearsalSub;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

class RehearsalSubNotificationsTest extends TestCase
{
    use RefreshDatabase;

    private function createRehearsalWithSub(?User $subUser = null): array
    {
        $owner = User::factory()->create();
        $band  = Bands::factory()->create();
        $band->owners()->create(['user_id' => $owner->id]);

        $schedule  = RehearsalSchedule::factory()->weekly()->create(['band_id' => $band->id]);
        $rehearsal = Rehearsal::factory()->create([
            'rehearsal_schedule_id' => $schedule->id,
            'band_id'               => $band->id,
        ]);
        Events::factory()->create([
            'eventable_id'   => $rehearsal->id,
            'eventable_type' => 'App\\Models\\Rehearsal',
            'event_type_id'  => EventTypes::factory()->create()->id,
            'date'           => now()->addDays(7)->format('Y-m-d'),
            'start_time'     => '19:00:00',
        ]);

        $sub = RehearsalSub::factory()->create([
            'rehearsal_id' => $rehearsal->id,
            'band_id'      => $band->id,
            'user_id'      => $subUser?->id,
            'email'        => $subUser?->email ?? 'adhoc@example.com',
            'invited_by'   => $owner->id,
        ]);

        return compact('owner', 'band', 'rehearsal', 'sub');
    }

    public function test_store_endpoint_dispatches_added_job(): void
    {
        Queue::fake();

        $owner = User::factory()->create();
        $band  = Bands::factory()->create();
        $band->owners()->create(['user_id' => $owner->id]);
        $schedule  = RehearsalSchedule::factory()->weekly()->create(['band_id' => $band->id]);
        $rehearsal = Rehearsal::factory()->create([
            'rehearsal_schedule_id' => $schedule->id,
            'band_id'               => $band->id,
        ]);
        Events::factory()->create([
            'eventable_id'   => $rehearsal->id,
            'eventable_type' => 'App\\Models\\Rehearsal',
            'event_type_id'  => EventTypes::factory()->create()->id,
            'date'           => now()->addDays(7)->format('Y-m-d'),
        ]);
        $token = $owner->createToken('t')->plainTextToken;

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->postJson("/api/mobile/rehearsals/{$rehearsal->id}/subs", [
                'name' => 'Pat', 'email' => 'pat@example.com',
            ])
            ->assertCreated();

        Queue::assertPushed(ProcessRehearsalSubAdded::class);
    }

    public function test_added_job_emails_adhoc_invitee_without_push(): void
    {
        Mail::fake();
        Queue::fake();

        ['sub' => $sub, 'owner' => $owner] = $this->createRehearsalWithSub();

        (new ProcessRehearsalSubAdded($sub, $owner->id, 'test-dedupe'))->handle();

        Mail::assertSent(RehearsalSubAdded::class,
            fn ($mail) => $mail->hasTo('adhoc@example.com'));
        Queue::assertNotPushed(SendUserPush::class);
    }

    public function test_added_job_emails_and_pushes_registered_sub_with_device(): void
    {
        Mail::fake();
        Queue::fake();

        $subUser = User::factory()->create();
        DeviceToken::factory()->create(['user_id' => $subUser->id]);

        ['sub' => $sub, 'owner' => $owner] = $this->createRehearsalWithSub($subUser);

        (new ProcessRehearsalSubAdded($sub, $owner->id, 'test-dedupe'))->handle();

        Mail::assertSent(RehearsalSubAdded::class,
            fn ($mail) => $mail->hasTo($subUser->email));
        Queue::assertPushed(SendUserPush::class);
    }
}
```

(If `DeviceToken` has no factory, create the row directly with the table's minimal columns — check `app/Models/DeviceToken.php` fillable and mirror however `RehearsalsTest`/push tests construct one.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=RehearsalSubNotificationsTest`
Expected: FAIL — `Class "App\Jobs\ProcessRehearsalSubAdded" not found`.

- [ ] **Step 3: Implement mailables, views, job, and dispatch**

`app/Mail/RehearsalSubAdded.php`:

```php
<?php

namespace App\Mail;

use App\Formatters\NoteText;
use App\Models\Bands;
use App\Models\Rehearsal;
use App\Models\RehearsalSub;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Carbon;

class RehearsalSubAdded extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public RehearsalSub $sub,
        public Rehearsal $rehearsal,
        public Bands $band,
        public ?string $date,
    ) {}

    public function build()
    {
        $event = $this->rehearsal->events->first();
        $time  = $event?->start_time?->format('g:i A');
        $venue = $this->rehearsal->venue_name
            ?? $this->rehearsal->rehearsalSchedule?->location_name;

        return $this->markdown('email.rehearsal-sub-added')
            ->with([
                'subName'  => $this->sub->name,
                'bandName' => $this->band->name,
                'roleName' => $this->sub->bandRole?->name,
                'dateText' => $this->date
                    ? Carbon::parse($this->date)->format('l, F j, Y')
                    : 'TBD',
                'timeText' => $time ?? 'TBD',
                'venue'    => $venue ?? 'TBD',
                'notes'    => NoteText::toPlainText($this->rehearsal->notes),
            ])
            ->subject("Rehearsal invitation from {$this->band->name}");
    }
}
```

`app/Mail/RehearsalSubNotice.php`:

```php
<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Queue\SerializesModels;

/**
 * Short plain notice to a rehearsal sub (removed / cancelled / restored).
 */
class RehearsalSubNotice extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $subjectLine,
        public string $bodyText,
        public string $bandName,
    ) {}

    public function build()
    {
        return $this->markdown('email.rehearsal-sub-notice')
            ->with([
                'bodyText' => $this->bodyText,
                'bandName' => $this->bandName,
            ])
            ->subject($this->subjectLine);
    }
}
```

`resources/views/email/rehearsal-sub-added.blade.php`:

```blade
@component('mail::message')
# Rehearsal invitation

Hi {{ $subName }},

You've been added as a substitute@if($roleName) ({{ $roleName }})@endif for a rehearsal with **{{ $bandName }}**.

- **Date:** {{ $dateText }}
- **Time:** {{ $timeText }}
- **Location:** {{ $venue }}
@if($notes)

**Notes:** {{ $notes }}
@endif

Thanks,<br>
{{ config('app.name') }}
@endcomponent
```

`resources/views/email/rehearsal-sub-notice.blade.php`:

```blade
@component('mail::message')
# {{ $bandName }}

{{ $bodyText }}

Thanks,<br>
{{ config('app.name') }}
@endcomponent
```

`app/Jobs/ProcessRehearsalSubAdded.php` (modeled on `ProcessRehearsalCancelled`):

```php
<?php

namespace App\Jobs;

use App\Mail\RehearsalSubAdded;
use App\Models\RehearsalSub;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Mail;

class ProcessRehearsalSubAdded implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(
        public RehearsalSub $sub,
        public int $actorId,
        public string $dedupeKey,
    ) {}

    public function handle(): void
    {
        $this->sub->loadMissing([
            'rehearsal.rehearsalSchedule.band',
            'rehearsal.events',
            'rehearsal.band',
            'bandRole',
            'user',
        ]);

        $rehearsal = $this->sub->rehearsal;
        $band = $rehearsal->rehearsalSchedule?->band ?? $rehearsal->band;
        if (!$band) {
            return;
        }

        $event = $rehearsal->events->first();
        $date  = $event
            ? (is_string($event->date) ? $event->date : $event->date->format('Y-m-d'))
            : null;

        Mail::to($this->sub->email)->send(
            new RehearsalSubAdded($this->sub, $rehearsal, $band, $date)
        );

        $user = $this->sub->user;
        if ($user && $user->deviceTokens()->exists()) {
            $whenText = $date ? Carbon::parse($date)->format('D, M j') : 'upcoming';

            $push = [
                'type'        => 'rehearsal_sub_added',
                'title'       => "You're invited to a rehearsal",
                'body'        => "{$band->name} · {$whenText}",
                'rehearsalId' => (string) $rehearsal->id,
            ];
            if ($date) {
                $push['date'] = $date;
            }

            SendUserPush::dispatch($user->id, $push, $this->dedupeKey, true);
        }
    }
}
```

`app/Services/RehearsalSubService.php` — add `use App\Jobs\ProcessRehearsalSubAdded;` and, right before `return $sub;` in `invite()`:

```php
        ProcessRehearsalSubAdded::dispatch(
            $sub,
            $actor->id,
            sprintf('rehearsal-sub:%d:added:%s', $sub->id, now()->getPreciseTimestamp(3)),
        );
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=RehearsalSubNotificationsTest`
Expected: PASS (3 tests). Re-run `--filter=RehearsalSubsTest` too — the new dispatch must not break A3's tests (they don't fake the queue; the job serializes fine but Mail must not actually send in tests — the suite's default MAIL_MAILER=array handles that).

- [ ] **Step 5: Commit**

```bash
git add app/Mail/RehearsalSubAdded.php app/Mail/RehearsalSubNotice.php resources/views/email/rehearsal-sub-added.blade.php resources/views/email/rehearsal-sub-notice.blade.php app/Jobs/ProcessRehearsalSubAdded.php app/Services/RehearsalSubService.php tests/Feature/Api/Mobile/RehearsalSubNotificationsTest.php
git commit -m "feat(rehearsals): invite emails + push via ProcessRehearsalSubAdded"
```

---

### Task A5: Removal — DELETE endpoint + `ProcessRehearsalSubRemoved`

**Files:**
- Create: `app/Jobs/ProcessRehearsalSubRemoved.php`
- Modify: `app/Services/RehearsalSubService.php` (add `remove()`)
- Modify: `app/Http/Controllers/Api/Mobile/RehearsalSubsController.php` (add `destroy()`)
- Modify: `routes/api.php` (DELETE route next to the POST from A3)
- Test: `tests/Feature/Api/Mobile/RehearsalSubsTest.php` + `RehearsalSubNotificationsTest.php`

**Interfaces:**
- Consumes: `RehearsalSubNotice` mailable (A4), `resolveWritable()` (A3).
- Produces: `RehearsalSubService::remove(Rehearsal $rehearsal, int $subId, User $actor): void`; route `mobile.rehearsals.subs.destroy`; `ProcessRehearsalSubRemoved::dispatch(RehearsalSub $sub, int $actorId, string $dedupeKey)`.

- [ ] **Step 1: Write the failing tests**

Append to `RehearsalSubsTest.php`:

```php
    public function test_remove_sub_soft_deletes_and_returns_remaining(): void
    {
        $ctx = $this->createOwnerWithRehearsal();

        $keep = RehearsalSub::factory()->create([
            'rehearsal_id' => $ctx['rehearsal']->id,
            'band_id'      => $ctx['band']->id,
            'name'         => 'Keeper',
        ]);
        $remove = RehearsalSub::factory()->create([
            'rehearsal_id' => $ctx['rehearsal']->id,
            'band_id'      => $ctx['band']->id,
            'name'         => 'Removed',
        ]);

        $this->withToken($ctx['token'])
            ->withHeaders(['X-Band-ID' => $ctx['band']->id])
            ->deleteJson("/api/mobile/rehearsals/{$ctx['rehearsal']->id}/subs/{$remove->id}")
            ->assertOk()
            ->assertJsonCount(1, 'subs')
            ->assertJsonPath('subs.0.name', 'Keeper');

        $this->assertSoftDeleted('rehearsal_subs', ['id' => $remove->id]);
        $this->assertNull($keep->fresh()->deleted_at);
    }

    public function test_remove_sub_from_wrong_rehearsal_404s(): void
    {
        $ctx = $this->createOwnerWithRehearsal();
        $otherCtx = $this->createOwnerWithRehearsal();

        $foreignSub = RehearsalSub::factory()->create([
            'rehearsal_id' => $otherCtx['rehearsal']->id,
            'band_id'      => $otherCtx['band']->id,
        ]);

        $this->withToken($ctx['token'])
            ->withHeaders(['X-Band-ID' => $ctx['band']->id])
            ->deleteJson("/api/mobile/rehearsals/{$ctx['rehearsal']->id}/subs/{$foreignSub->id}")
            ->assertNotFound();
    }
```

Append to `RehearsalSubNotificationsTest.php`:

```php
    public function test_removed_job_sends_notice_email(): void
    {
        Mail::fake();
        Queue::fake();

        ['sub' => $sub, 'owner' => $owner] = $this->createRehearsalWithSub();
        $sub->delete();

        (new \App\Jobs\ProcessRehearsalSubRemoved($sub, $owner->id, 'test-dedupe'))->handle();

        Mail::assertSent(\App\Mail\RehearsalSubNotice::class,
            fn ($mail) => $mail->hasTo('adhoc@example.com'));
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=RehearsalSubsTest`
Expected: the two new tests FAIL (405/404 — no DELETE route).

- [ ] **Step 3: Implement removal**

`app/Services/RehearsalSubService.php` — add `use App\Jobs\ProcessRehearsalSubRemoved;` and:

```php
    /**
     * Remove a sub from a rehearsal (soft delete) and notify them.
     * 404s when the sub does not belong to this rehearsal.
     */
    public function remove(Rehearsal $rehearsal, int $subId, User $actor): void
    {
        $sub = $rehearsal->subs()->findOrFail($subId);

        $sub->delete();

        ProcessRehearsalSubRemoved::dispatch(
            $sub,
            $actor->id,
            sprintf('rehearsal-sub:%d:removed:%s', $sub->id, now()->getPreciseTimestamp(3)),
        );
    }
```

`app/Jobs/ProcessRehearsalSubRemoved.php`:

```php
<?php

namespace App\Jobs;

use App\Mail\RehearsalSubNotice;
use App\Models\RehearsalSub;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Mail;

class ProcessRehearsalSubRemoved implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(
        public RehearsalSub $sub,
        public int $actorId,
        public string $dedupeKey,
    ) {}

    public function handle(): void
    {
        $this->sub->loadMissing([
            'rehearsal.rehearsalSchedule.band',
            'rehearsal.events',
            'rehearsal.band',
            'user',
        ]);

        $rehearsal = $this->sub->rehearsal;
        $band = $rehearsal->rehearsalSchedule?->band ?? $rehearsal->band;
        if (!$band) {
            return;
        }

        $event = $rehearsal->events->first();
        $date  = $event
            ? (is_string($event->date) ? $event->date : $event->date->format('Y-m-d'))
            : null;
        $whenText = $date ? Carbon::parse($date)->format('D, M j') : 'upcoming';

        Mail::to($this->sub->email)->send(new RehearsalSubNotice(
            'Rehearsal update',
            "You're no longer needed for the {$whenText} rehearsal with {$band->name}.",
            $band->name,
        ));

        $user = $this->sub->user;
        if ($user && $user->deviceTokens()->exists()) {
            $push = [
                'type'        => 'rehearsal_sub_removed',
                'title'       => 'Rehearsal update',
                'body'        => "{$band->name} · no longer needed {$whenText}",
                'rehearsalId' => (string) $rehearsal->id,
            ];
            if ($date) {
                $push['date'] = $date;
            }

            SendUserPush::dispatch($user->id, $push, $this->dedupeKey, true);
        }
    }
}
```

`RehearsalSubsController` — replace the destroy placeholder comment with:

```php
    /**
     * DELETE /api/mobile/rehearsals/{rehearsal}/subs/{sub}
     */
    public function destroy(Request $request, int $rehearsal, int $sub): JsonResponse
    {
        [$rehearsalModel] = $this->resolveWritable($request, $rehearsal);

        $this->subService->remove($rehearsalModel, $sub, $request->user());

        return response()->json([
            'subs' => $this->rehearsalService->formatSubs($rehearsalModel),
        ]);
    }
```

`routes/api.php` — after the POST from A3:

```php
        Route::delete('/rehearsals/{rehearsal}/subs/{sub}', [App\Http\Controllers\Api\Mobile\RehearsalSubsController::class, 'destroy'])->name('mobile.rehearsals.subs.destroy');
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=RehearsalSubsTest --filter=RehearsalSubNotificationsTest` (run both filters as two commands).
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/Jobs/ProcessRehearsalSubRemoved.php app/Services/RehearsalSubService.php app/Http/Controllers/Api/Mobile/RehearsalSubsController.php routes/api.php tests/Feature/Api/Mobile/RehearsalSubsTest.php tests/Feature/Api/Mobile/RehearsalSubNotificationsTest.php
git commit -m "feat(rehearsals): DELETE sub endpoint + removal notice"
```

---

### Task A6: Sub-scoped reads — schedules list + detail access

**Files:**
- Modify: `app/Http/Controllers/Api/Mobile/RehearsalsController.php` (`schedules()`, `show()`, `showByKey()`)
- Test: `tests/Feature/Api/Mobile/RehearsalSubVisibilityTest.php`

**Interfaces:**
- Consumes: `User::canReadRehearsalsAsMember()` (A2), `Rehearsal::subs()` (A1).
- Produces: sub-scoped behavior — a sub's schedule list contains only their invited rehearsals (no virtuals, schedules with none are omitted); detail endpoints allow a sub only their own invited rehearsals; virtual materialization stays member-only.

**Token gotcha (document, don't fight):** token abilities are minted at login from `canRead()`, so a sub invited *after* their last login carries a token without `read:rehearsals` and the `mobile.band:read:rehearsals` middleware 403s the schedules list until the app refreshes the token (existing refresh endpoint) or the user re-logs. Tests below mint tokens after the invite. The `/rehearsals/{id}` detail routes have no ability middleware, so notification deep-links work immediately.

- [ ] **Step 1: Write the failing tests**

Append to `RehearsalSubVisibilityTest.php`:

```php
    public function test_sub_schedule_list_contains_only_invited_rehearsals(): void
    {
        ['band' => $band, 'schedule' => $schedule, 'rehearsal' => $invited, 'subUser' => $subUser] =
            $this->createBandWithSubUser();

        // A second upcoming rehearsal the sub is NOT invited to.
        $other = Rehearsal::factory()->create([
            'rehearsal_schedule_id' => $schedule->id,
            'band_id'               => $band->id,
        ]);
        Events::factory()->create([
            'eventable_id'   => $other->id,
            'eventable_type' => 'App\\Models\\Rehearsal',
            'event_type_id'  => EventTypes::factory()->create()->id,
            'date'           => now()->addDays(14)->format('Y-m-d'),
        ]);

        RehearsalSub::factory()->create([
            'rehearsal_id' => $invited->id,
            'band_id'      => $band->id,
            'user_id'      => $subUser->id,
            'email'        => $subUser->email,
        ]);

        // Token minted AFTER the invite so it carries read:rehearsals.
        $token = $subUser->createToken('sub-device')->plainTextToken;

        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/rehearsal-schedules?include_virtual=1");

        $response->assertOk();

        $upcoming = collect($response->json('schedules'))
            ->flatMap(fn ($s) => $s['upcoming_rehearsals']);

        $this->assertTrue($upcoming->pluck('id')->contains($invited->id));
        $this->assertFalse($upcoming->pluck('id')->contains($other->id));
        // No virtual expansion for sub-scoped users even when requested.
        $this->assertFalse($upcoming->contains(fn ($r) => $r['id'] === null));
    }

    public function test_sub_can_view_invited_rehearsal_detail_but_not_others(): void
    {
        ['band' => $band, 'schedule' => $schedule, 'rehearsal' => $invited, 'subUser' => $subUser] =
            $this->createBandWithSubUser();

        $other = Rehearsal::factory()->create([
            'rehearsal_schedule_id' => $schedule->id,
            'band_id'               => $band->id,
        ]);
        Events::factory()->create([
            'eventable_id'   => $other->id,
            'eventable_type' => 'App\\Models\\Rehearsal',
            'event_type_id'  => EventTypes::factory()->create()->id,
            'date'           => now()->addDays(14)->format('Y-m-d'),
        ]);

        RehearsalSub::factory()->create([
            'rehearsal_id' => $invited->id,
            'band_id'      => $band->id,
            'user_id'      => $subUser->id,
            'email'        => $subUser->email,
        ]);
        $token = $subUser->createToken('sub-device')->plainTextToken;

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/rehearsals/{$invited->id}")
            ->assertOk();

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/rehearsals/{$other->id}")
            ->assertForbidden();
    }

    public function test_sub_cannot_materialize_virtual_rehearsals(): void
    {
        ['band' => $band, 'schedule' => $schedule, 'rehearsal' => $invited, 'subUser' => $subUser] =
            $this->createBandWithSubUser();

        RehearsalSub::factory()->create([
            'rehearsal_id' => $invited->id,
            'band_id'      => $band->id,
            'user_id'      => $subUser->id,
            'email'        => $subUser->email,
        ]);
        $token = $subUser->createToken('sub-device')->plainTextToken;

        $futureDate = now()->addDays(21)->format('Y-m-d');

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/rehearsals/by-key/virtual-rehearsal-{$schedule->id}-{$futureDate}")
            ->assertForbidden();
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=RehearsalSubVisibilityTest`
Expected: the three new tests FAIL (full list returned / 200 where 403 expected).

- [ ] **Step 3: Implement scoping in `RehearsalsController`**

In `schedules()` — replace the two lines that read `$includeVirtual` and build the query (~lines 68-81) so sub-scoped users get a filtered, virtual-free list:

```php
        $band           = $request->input('mobile_band');
        $user           = $request->user();
        // A user who can only read via the rehearsal-sub carve-out sees just
        // the rehearsals they're invited to — no virtuals, no full schedule.
        $subScoped      = !$user->canReadRehearsalsAsMember($band->id);
        $includeVirtual = $request->boolean('include_virtual') && !$subScoped;
```

and inside the `with(['rehearsals' => ...])` closure add the invite constraint:

```php
            ->with(['rehearsals' => function ($query) use ($cutoff, $subScoped, $user) {
                $query->whereHas('events', function ($eq) use ($cutoff) {
                    $eq->where('date', '>=', now()->toDateString())
                       ->where('date', '<=', $cutoff);
                })->with('events');

                if ($subScoped) {
                    $query->whereHas('subs', fn ($sq) => $sq->where('user_id', $user->id));
                }
            }])
```

and just before `return response()->json(...)`:

```php
        if ($subScoped) {
            $mapped = $mapped->filter(fn ($s) => count($s['upcoming_rehearsals']) > 0);
        }

        return response()->json(['schedules' => $mapped->values()]);
```

In `show()` — after the existing `canRead` check (~line 146), add:

```php
        if (!$request->user()->canReadRehearsalsAsMember($band->id)
            && !$rehearsalModel->subs()->where('user_id', $request->user()->id)->exists()) {
            abort(403, 'You do not have permission to view this rehearsal.');
        }
```

In `showByKey()` — add the same block in the existing-event branch (after its `canRead` check ~line 177), and in the virtual branch (after its `canRead` check ~line 195) add:

```php
        if (!$request->user()->canReadRehearsalsAsMember($band->id)) {
            abort(403, 'You do not have permission to view this rehearsal.');
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=RehearsalSubVisibilityTest` then `--filter=RehearsalsTest`
Expected: all PASS (member behavior unchanged).

- [ ] **Step 5: Commit**

```bash
git add app/Http/Controllers/Api/Mobile/RehearsalsController.php tests/Feature/Api/Mobile/RehearsalSubVisibilityTest.php
git commit -m "feat(rehearsals): scope rehearsal reads for invited subs"
```

---

### Task A7: Cancellation notifies invited subs

**Files:**
- Modify: `app/Jobs/ProcessRehearsalCancelled.php`
- Test: `tests/Feature/Api/Mobile/RehearsalSubNotificationsTest.php`

**Interfaces:**
- Consumes: `Rehearsal::subs()` (A1), `RehearsalSubNotice` (A4), existing `RehearsalCancelled` notification + push payload.

- [ ] **Step 1: Write the failing tests**

Append to `RehearsalSubNotificationsTest.php`:

```php
    public function test_cancellation_notifies_registered_sub_and_emails_adhoc(): void
    {
        Mail::fake();
        Queue::fake();
        \Illuminate\Support\Facades\Notification::fake();

        $registeredSub = User::factory()->create();
        ['rehearsal' => $rehearsal, 'owner' => $owner, 'band' => $band] =
            $this->createRehearsalWithSub($registeredSub);

        // Second, ad-hoc invitee on the same rehearsal.
        RehearsalSub::factory()->create([
            'rehearsal_id' => $rehearsal->id,
            'band_id'      => $band->id,
            'email'        => 'adhoc2@example.com',
        ]);

        $rehearsal->update(['is_cancelled' => true]);

        (new \App\Jobs\ProcessRehearsalCancelled($rehearsal->fresh(), $owner->id, true, 'dedupe-x'))
            ->handle();

        \Illuminate\Support\Facades\Notification::assertSentTo(
            $registeredSub, \App\Notifications\RehearsalCancelled::class);
        Mail::assertSent(\App\Mail\RehearsalSubNotice::class,
            fn ($mail) => $mail->hasTo('adhoc2@example.com'));
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=RehearsalSubNotificationsTest`
Expected: new test FAILS (nothing sent to sub / ad-hoc).

- [ ] **Step 3: Extend the job**

In `ProcessRehearsalCancelled::handle()`:
- change the `loadMissing` call to include subs: `$this->rehearsal->loadMissing(['rehearsalSchedule.band', 'events', 'band', 'subs.user']);`
- add imports: `use App\Mail\RehearsalSubNotice; use Illuminate\Support\Facades\Mail;`
- after the existing `foreach ($band->everyone() ...)` loop, append:

```php
        // Invited rehearsal subs get the same treatment as members; ad-hoc
        // invitees (no account) get a plain email notice.
        foreach ($this->rehearsal->subs as $sub) {
            $user = $sub->user;

            if ($user) {
                if ($user->id === $this->actorId
                    || in_array($user->id, $notifiedUserIds, true)) {
                    continue;
                }
                $notifiedUserIds[] = $user->id;

                $user->notify(new RehearsalCancelled($this->rehearsal, $this->isCancelled, $date));

                if ($user->deviceTokens()->exists()) {
                    SendUserPush::dispatch($user->id, $push, $this->dedupeKey, true);
                }
            } else {
                Mail::to($sub->email)->send(new RehearsalSubNotice(
                    $this->isCancelled ? 'Rehearsal cancelled' : 'Rehearsal back on',
                    sprintf(
                        '%s on %s has been %s.',
                        $name,
                        $whenText,
                        $this->isCancelled ? 'cancelled' : 'restored',
                    ),
                    $band->name,
                ));
            }
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=RehearsalSubNotificationsTest` then `--filter=RehearsalsTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/Jobs/ProcessRehearsalCancelled.php tests/Feature/Api/Mobile/RehearsalSubNotificationsTest.php
git commit -m "feat(rehearsals): cancellation notifies invited subs"
```

---

### Task A8: Full backend suite + PR

- [ ] **Step 1: Run the full test suite**

Run: `docker compose exec app php artisan test`
Expected: green. Known flakes (band_roles race, CalendarFeedTest) may appear under parallel runs — re-run those files sequentially before assuming a regression.

- [ ] **Step 2: Push and open PR against staging**

```bash
git push -u origin feat/rehearsal-subs
gh pr create --base staging --title "feat: invite subs to individual rehearsals (mobile)" --body "$(cat <<'EOF'
## Summary
- New `rehearsal_subs` table + `POST/DELETE /api/mobile/rehearsals/{id}/subs`
- `formatDetail()` gains a `subs` array
- Invite/removal emails (all invitees) + pushes (registered subs), `ProcessRehearsalCancelled` now notifies invited subs
- Subs see only their invited rehearsals (schedules scoped, detail gated, no virtual materialization)

Spec: tts_bandmate `docs/superpowers/specs/2026-08-01-rehearsal-sub-invites-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Wait for Copilot review and address comments** (merging to staging auto-deploys — required before the app PR merges).

---

# Part B — Flutter app (tts_bandmate repo)

Work on the existing branch `feat/rehearsal-sub-invites`. Run tests with `flutter test`, lint with `flutter analyze`.

### Task B1: `RehearsalSub` model + `RehearsalDetail.subs` + repository methods

**Files:**
- Create: `lib/features/rehearsals/data/models/rehearsal_sub.dart`
- Modify: `lib/features/rehearsals/data/models/rehearsal_detail.dart`
- Modify: `lib/core/network/api_endpoints.dart` (after `mobileRehearsalSetCancelled`)
- Modify: `lib/features/rehearsals/data/rehearsals_repository.dart`
- Test: `test/features/rehearsals/rehearsal_models_test.dart`, `test/features/rehearsals/rehearsals_repository_test.dart`

**Interfaces:**
- Consumes: wire contract from Global Constraints.
- Produces: `RehearsalSub` (`id, name, email, phone, bandRoleId, roleName, userId`, getter `isRegistered`); `RehearsalDetail.subs: List<RehearsalSub>` (empty when key absent); `RehearsalsRepository.addSub(int rehearsalId, {int? callListEntryId, String? name, String? email, String? phone, int? bandRoleId}) → Future<List<RehearsalSub>>`; `RehearsalsRepository.removeSub(int rehearsalId, int subId) → Future<List<RehearsalSub>>`; `ApiEndpoints.mobileRehearsalSubs(int)`, `ApiEndpoints.mobileRehearsalSub(int, int)`.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/rehearsals/rehearsal_models_test.dart`:

```dart
  group('RehearsalSub', () {
    test('parses full payload', () {
      final sub = RehearsalSub.fromJson(const {
        'id': 5,
        'name': 'Pat Horn',
        'email': 'pat@example.com',
        'phone': '555-0100',
        'band_role_id': 3,
        'role_name': 'Trumpet',
        'user_id': 9,
        'is_registered': true,
      });

      expect(sub.id, 5);
      expect(sub.name, 'Pat Horn');
      expect(sub.roleName, 'Trumpet');
      expect(sub.isRegistered, isTrue);
    });

    test('handles nulls for ad-hoc invitee', () {
      final sub = RehearsalSub.fromJson(const {
        'id': 6,
        'name': 'Ad Hoc',
        'email': 'adhoc@example.com',
        'phone': null,
        'band_role_id': null,
        'role_name': null,
        'user_id': null,
        'is_registered': false,
      });

      expect(sub.isRegistered, isFalse);
      expect(sub.bandRoleId, isNull);
    });
  });

  group('RehearsalDetail subs', () {
    test('parses subs list and defaults to empty when absent', () {
      final withSubs = RehearsalDetail.fromJson(const {
        'id': 1,
        'is_cancelled': false,
        'schedule': {'id': 2, 'name': 'Weekly'},
        'subs': [
          {'id': 5, 'name': 'Pat', 'email': 'p@x.com', 'user_id': null},
        ],
      });
      expect(withSubs.subs, hasLength(1));
      expect(withSubs.subs.first.name, 'Pat');

      final withoutSubs = RehearsalDetail.fromJson(const {
        'id': 1,
        'is_cancelled': false,
        'schedule': {'id': 2, 'name': 'Weekly'},
      });
      expect(withoutSubs.subs, isEmpty);
    });
  });
```

Add the needed import at the top: `import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_sub.dart';` (and `rehearsal_detail.dart` if not present).

Append to `test/features/rehearsals/rehearsals_repository_test.dart` (uses the file's existing `_FakeAdapter`):

```dart
  test('addSub posts call_list_entry_id and parses subs', () async {
    final adapter = _FakeAdapter({
      'subs': [
        {'id': 1, 'name': 'Pat', 'email': 'p@x.com', 'user_id': 9},
      ],
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://x'))
      ..httpClientAdapter = adapter;
    final repo = RehearsalsRepository(dio);

    final subs = await repo.addSub(42, callListEntryId: 7);

    expect(adapter.lastRequest!.path, '/api/mobile/rehearsals/42/subs');
    expect(adapter.lastRequest!.method, 'POST');
    expect(adapter.lastRequest!.data, {'call_list_entry_id': 7});
    expect(subs.single.name, 'Pat');
    expect(subs.single.isRegistered, isTrue);
  });

  test('addSub posts ad-hoc fields', () async {
    final adapter = _FakeAdapter({'subs': []});
    final dio = Dio(BaseOptions(baseUrl: 'http://x'))
      ..httpClientAdapter = adapter;
    final repo = RehearsalsRepository(dio);

    await repo.addSub(42, name: 'Pat', email: 'p@x.com', phone: '555');

    expect(adapter.lastRequest!.data,
        {'name': 'Pat', 'email': 'p@x.com', 'phone': '555'});
  });

  test('removeSub deletes and parses remaining subs', () async {
    final adapter = _FakeAdapter({'subs': []});
    final dio = Dio(BaseOptions(baseUrl: 'http://x'))
      ..httpClientAdapter = adapter;
    final repo = RehearsalsRepository(dio);

    final subs = await repo.removeSub(42, 5);

    expect(adapter.lastRequest!.path, '/api/mobile/rehearsals/42/subs/5');
    expect(adapter.lastRequest!.method, 'DELETE');
    expect(subs, isEmpty);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/rehearsals/rehearsal_models_test.dart test/features/rehearsals/rehearsals_repository_test.dart`
Expected: FAIL — `rehearsal_sub.dart` doesn't exist / `addSub` undefined.

- [ ] **Step 3: Implement model, detail field, endpoints, repository**

`lib/features/rehearsals/data/models/rehearsal_sub.dart`:

```dart
/// A substitute invited to one specific rehearsal.
class RehearsalSub {
  const RehearsalSub({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.bandRoleId,
    this.roleName,
    this.userId,
  });

  final int id;
  final String name;
  final String? email;
  final String? phone;
  final int? bandRoleId;
  final String? roleName;
  final int? userId;

  /// Registered users get push + in-app visibility; ad-hoc invitees email only.
  bool get isRegistered => userId != null;

  factory RehearsalSub.fromJson(Map<String, dynamic> json) {
    return RehearsalSub(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      bandRoleId: (json['band_role_id'] as num?)?.toInt(),
      roleName: json['role_name'] as String?,
      userId: (json['user_id'] as num?)?.toInt(),
    );
  }
}
```

`rehearsal_detail.dart` — add `import 'rehearsal_sub.dart';`, a `required this.subs` constructor param + `final List<RehearsalSub> subs;` field, and in `fromJson` (next to the bookings parse):

```dart
    final rawSubs = json['subs'];
    final subs = rawSubs is List
        ? rawSubs
            .cast<Map<String, dynamic>>()
            .map(RehearsalSub.fromJson)
            .toList()
        : <RehearsalSub>[];
```

passing `subs: subs,` to the constructor.

`api_endpoints.dart` — after `mobileRehearsalSetCancelled`:

```dart
  static String mobileRehearsalSubs(int rehearsalId) =>
      '/api/mobile/rehearsals/$rehearsalId/subs';
  static String mobileRehearsalSub(int rehearsalId, int subId) =>
      '/api/mobile/rehearsals/$rehearsalId/subs/$subId';
```

`rehearsals_repository.dart` — add `import 'models/rehearsal_sub.dart';` and, after `setCancelled`:

```dart
  /// Invites a sub to the rehearsal — either from a call-list entry or ad-hoc
  /// by name/email. Returns the rehearsal's refreshed subs list.
  Future<List<RehearsalSub>> addSub(
    int rehearsalId, {
    int? callListEntryId,
    String? name,
    String? email,
    String? phone,
    int? bandRoleId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalSubs(rehearsalId),
      data: {
        if (callListEntryId != null) 'call_list_entry_id': callListEntryId,
        if (callListEntryId == null) ...{
          'name': name,
          'email': email,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (bandRoleId != null) 'band_role_id': bandRoleId,
        },
      },
    );
    return _parseSubs(response.data!);
  }

  /// Removes an invited sub. Returns the rehearsal's refreshed subs list.
  Future<List<RehearsalSub>> removeSub(int rehearsalId, int subId) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalSub(rehearsalId, subId),
    );
    return _parseSubs(response.data!);
  }

  List<RehearsalSub> _parseSubs(Map<String, dynamic> data) {
    final raw = data['subs'];
    if (raw is! List) return const [];
    return raw.cast<Map<String, dynamic>>().map(RehearsalSub.fromJson).toList();
  }
```

(Also add the `ApiEndpoints` import if the file references it via a different path — it already imports it for the other endpoints.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/rehearsals/` and `flutter analyze`
Expected: PASS, no new analyzer warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rehearsals/data/models/rehearsal_sub.dart lib/features/rehearsals/data/models/rehearsal_detail.dart lib/core/network/api_endpoints.dart lib/features/rehearsals/data/rehearsals_repository.dart test/features/rehearsals/rehearsal_models_test.dart test/features/rehearsals/rehearsals_repository_test.dart
git commit -m "feat(rehearsals): RehearsalSub model + subs endpoints in repository"
```

---

### Task B2: Sub picker sheet (call lists + ad-hoc form)

**Files:**
- Create: `lib/features/rehearsals/widgets/rehearsal_sub_picker_sheet.dart`

**Interfaces:**
- Consumes: `callListsProvider(bandId)` → `AsyncValue<List<CallListGroup>>` (`lib/features/personnel/providers/subs_provider.dart`), `rolesProvider(bandId)` → `AsyncValue<List<BandRole>>` (`lib/features/personnel/providers/roles_provider.dart`), `CallListEntry` (`id, instrument, name, email, isCustom`).
- Produces: `showRehearsalSubPicker(BuildContext context, {required int bandId}) → Future<RehearsalSubPickerResult?>` where `RehearsalSubPickerResult` carries either `callListEntryId` or `name/email/phone/bandRoleId`. The caller performs the actual `addSub` call — the sheet only picks.

- [ ] **Step 1: Implement the sheet**

No unit test for this pure-UI file (matches repo convention — screens aren't unit-tested; B3's widget test covers the section wiring). Create:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/personnel/data/models/band_role.dart';
import 'package:tts_bandmate/features/personnel/data/models/call_list_entry.dart';
import 'package:tts_bandmate/features/personnel/providers/roles_provider.dart';
import 'package:tts_bandmate/features/personnel/providers/subs_provider.dart';

/// What the picker resolved to: a call-list entry, or ad-hoc contact details.
class RehearsalSubPickerResult {
  const RehearsalSubPickerResult.callList(int this.callListEntryId)
      : name = null,
        email = null,
        phone = null,
        bandRoleId = null;

  const RehearsalSubPickerResult.adHoc({
    required String this.name,
    required String this.email,
    this.phone,
    this.bandRoleId,
  }) : callListEntryId = null;

  final int? callListEntryId;
  final String? name;
  final String? email;
  final String? phone;
  final int? bandRoleId;
}

/// Shows the two-level picker: call lists grouped by instrument, plus an
/// "Invite by email…" ad-hoc form. Returns null when dismissed.
Future<RehearsalSubPickerResult?> showRehearsalSubPicker(
  BuildContext context, {
  required int bandId,
}) {
  return showCupertinoModalPopup<RehearsalSubPickerResult>(
    context: context,
    builder: (_) => _RehearsalSubPickerSheet(bandId: bandId),
  );
}

class _RehearsalSubPickerSheet extends ConsumerWidget {
  const _RehearsalSubPickerSheet({required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callListsAsync = ref.watch(callListsProvider(bandId));

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Invite Sub',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: callListsAsync.when(
                loading: () =>
                    const Center(child: CupertinoActivityIndicator()),
                // Call lists are owner-only server-side; on error (e.g. 403)
                // fall back to the ad-hoc form alone.
                error: (_, __) => _adHocOnly(context),
                data: (groups) => _entryList(context, groups),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adHocOnly(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Call lists are unavailable. You can still invite someone by email.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: context.secondaryText),
          ),
        ),
        const SizedBox(height: 12),
        _inviteByEmailButton(context),
      ],
    );
  }

  Widget _entryList(BuildContext context, List<CallListGroup> groups) {
    final rows = <Widget>[];

    for (final group in groups) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          group.instrument.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.secondaryText,
          ),
        ),
      ));
      for (final entry in group.entries) {
        rows.add(_EntryTile(entry: entry));
      }
    }

    if (rows.isEmpty) {
      return _adHocOnly(context);
    }

    rows.add(const SizedBox(height: 8));
    rows.add(Center(child: _inviteByEmailButton(context)));
    rows.add(const SizedBox(height: 16));

    return ListView(children: rows);
  }

  Widget _inviteByEmailButton(BuildContext context) {
    return CupertinoButton(
      onPressed: () async {
        final result = await showCupertinoModalPopup<RehearsalSubPickerResult>(
          context: context,
          builder: (_) => _AdHocInviteSheet(bandId: bandId),
        );
        if (result != null && context.mounted) {
          Navigator.pop(context, result);
        }
      },
      child: const Text('Invite by email…'),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final CallListEntry entry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          Navigator.pop(context, RehearsalSubPickerResult.callList(entry.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name ?? entry.email ?? 'Unknown',
                      style: const TextStyle(fontSize: 15)),
                  if (entry.email != null)
                    Text(entry.email!,
                        style: TextStyle(
                            fontSize: 12, color: context.secondaryText)),
                ],
              ),
            ),
            if (entry.isCustom)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemOrange
                      .resolveFrom(context)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Sub',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          CupertinoColors.systemOrange.resolveFrom(context),
                    )),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdHocInviteSheet extends ConsumerStatefulWidget {
  const _AdHocInviteSheet({required this.bandId});

  final int bandId;

  @override
  ConsumerState<_AdHocInviteSheet> createState() => _AdHocInviteSheetState();
}

class _AdHocInviteSheetState extends ConsumerState<_AdHocInviteSheet> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  BandRole? _role;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool get _valid =>
      _nameController.text.trim().isNotEmpty &&
      _emailController.text.trim().contains('@');

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(rolesProvider(widget.bandId));

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Invite by email',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _nameController,
                placeholder: 'Name',
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _emailController,
                placeholder: 'Email',
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _phoneController,
                placeholder: 'Phone (optional)',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              rolesAsync.maybeWhen(
                data: (roles) => roles.isEmpty
                    ? const SizedBox.shrink()
                    : CupertinoButton(
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        onPressed: () => _pickRole(roles),
                        child: Text(_role?.name ?? 'Role (optional)'),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              CupertinoButton.filled(
                onPressed: _valid
                    ? () => Navigator.pop(
                          context,
                          RehearsalSubPickerResult.adHoc(
                            name: _nameController.text.trim(),
                            email: _emailController.text.trim(),
                            phone: _phoneController.text.trim().isEmpty
                                ? null
                                : _phoneController.text.trim(),
                            bandRoleId: _role?.id,
                          ),
                        )
                    : null,
                child: const Text('Invite'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickRole(List<BandRole> roles) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          for (final role in roles)
            CupertinoActionSheetAction(
              onPressed: () {
                setState(() => _role = role);
                Navigator.pop(sheetContext);
              },
              child: Text(role.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}
```

Before implementing, check the actual `BandRole` field for its label (`name` assumed — confirm in `lib/features/personnel/data/models/band_role.dart`) and the exact `rolesProvider` family signature; adjust the two usages if they differ.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: no new warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/features/rehearsals/widgets/rehearsal_sub_picker_sheet.dart
git commit -m "feat(rehearsals): sub picker sheet (call lists + ad-hoc invite)"
```

---

### Task B3: Subs section on the rehearsal detail screen

**Files:**
- Modify: `lib/features/rehearsals/screens/rehearsal_detail_screen.dart`
- Test: `test/features/rehearsals/rehearsal_subs_section_widget_test.dart`

**Interfaces:**
- Consumes: `RehearsalDetail.subs`, `RehearsalsRepository.addSub/removeSub` (B1), `showRehearsalSubPicker` (B2), `authProvider` (`AsyncNotifier<AuthState>`; `AuthAuthenticated.bands: List<BandSummary>` with `isOwner`), `selectedBandProvider` (`AsyncNotifier<int?>`).
- Produces: a "Subs" section (between the Schedule block and associated bookings) — list of invited subs with role badges; owner-only add (+) and per-row remove.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/rehearsals/rehearsal_subs_section_widget_test.dart`. Mirror the harness in the existing `test/features/rehearsals/rehearsal_cancel_widget_test.dart` (how it pumps `RehearsalDetailScreen(preloaded: ...)` inside `CupertinoApp` + `ProviderScope`, and how it overrides providers) — reuse its override style verbatim, then assert on the new section:

```dart
// Pseudocode-free sketch — copy the exact pump/override helpers from
// rehearsal_cancel_widget_test.dart, then:

testWidgets('renders invited subs with role badges', (tester) async {
  final detail = RehearsalDetail(
    id: 1,
    isCancelled: false,
    schedule: const ScheduleStub(id: 2, name: 'Weekly'),
    associatedBookings: const [],
    subs: const [
      RehearsalSub(id: 5, name: 'Pat Horn', roleName: 'Trumpet'),
      RehearsalSub(id: 6, name: 'Ad Hoc'),
    ],
  );

  // pump RehearsalDetailScreen(preloaded: detail) with the same
  // ProviderScope overrides rehearsal_cancel_widget_test uses
  // (non-owner auth state or none — the section itself must render).

  expect(find.text('Subs'), findsOneWidget);
  expect(find.text('Pat Horn'), findsOneWidget);
  expect(find.text('Trumpet'), findsOneWidget);
  expect(find.text('Ad Hoc'), findsOneWidget);
});

testWidgets('shows empty state when no subs', (tester) async {
  // same setup, subs: const []
  expect(find.text('No subs invited.'), findsOneWidget);
});
```

Write these as real tests using the copied harness — the sketch above defines the assertions; the pump boilerplate comes from the cancel test. Note `RehearsalDetail`'s constructor gains `subs` in B1, so positional/named args must match.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/rehearsals/rehearsal_subs_section_widget_test.dart`
Expected: FAIL — `find.text('Subs')` finds nothing.

- [ ] **Step 3: Implement the section**

In `rehearsal_detail_screen.dart`:

Add imports:

```dart
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import '../data/models/rehearsal_sub.dart';
import '../widgets/rehearsal_sub_picker_sheet.dart';
```

Add state to `_RehearsalDetailViewState`:

```dart
  late List<RehearsalSub> _subs;
  bool _mutatingSubs = false;
```

Initialize in `initState()` (`_subs = List.of(widget.rehearsal.subs);`) and sync in `didUpdateWidget` (inside the existing `!identical` block, guarded like notes):

```dart
      if (!_mutatingSubs) {
        _subs = List.of(widget.rehearsal.subs);
      }
```

Add the owner check + handlers (inside the State class):

```dart
  bool get _isOwner {
    final bandId = ref.watch(selectedBandProvider).valueOrNull;
    final auth = ref.watch(authProvider).valueOrNull;
    if (bandId == null || auth is! AuthAuthenticated) return false;
    return auth.bands.any((b) => b.id == bandId && b.isOwner);
  }

  Future<void> _inviteSub() async {
    final bandId = ref.read(selectedBandProvider).valueOrNull;
    if (bandId == null) return;

    final result = await showRehearsalSubPicker(context, bandId: bandId);
    if (result == null || !mounted) return;

    setState(() => _mutatingSubs = true);
    try {
      final repo = ref.read(rehearsalsRepositoryProvider);
      final updated = await repo.addSub(
        _rehearsal.id,
        callListEntryId: result.callListEntryId,
        name: result.name,
        email: result.email,
        phone: result.phone,
        bandRoleId: result.bandRoleId,
      );
      if (mounted) setState(() => _subs = updated);
    } catch (e) {
      if (mounted) _showSubError(e);
    } finally {
      if (mounted) setState(() => _mutatingSubs = false);
    }
  }

  Future<void> _removeSub(RehearsalSub sub) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Remove sub?'),
        content: Text('${sub.name} will be notified they are no longer '
            'needed for this rehearsal.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Remove'),
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _mutatingSubs = true);
    try {
      final repo = ref.read(rehearsalsRepositoryProvider);
      final updated = await repo.removeSub(_rehearsal.id, sub.id);
      if (mounted) setState(() => _subs = updated);
    } catch (e) {
      if (mounted) _showSubError(e);
    } finally {
      if (mounted) setState(() => _mutatingSubs = false);
    }
  }

  void _showSubError(Object e) {
    showCupertinoDialog(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(ErrorView.friendlyMessage(e)),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }
```

(`ErrorView.friendlyMessage` is already imported in this file. It surfaces the backend's 422 messages like "already invited".)

Insert the section into the `ListView` children — after the Schedule `Container` block and before the associated-bookings section:

```dart
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('Subs',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_isOwner)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    onPressed: _mutatingSubs ? null : _inviteSub,
                    child: _mutatingSubs
                        ? const CupertinoActivityIndicator()
                        : const Icon(CupertinoIcons.person_badge_plus,
                            size: 22),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_subs.isEmpty)
              Text(
                'No subs invited.',
                style: TextStyle(fontSize: 13, color: context.secondaryText),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemBackground
                      .resolveFrom(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    for (final sub in _subs)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(sub.name,
                                      style: const TextStyle(fontSize: 15)),
                                  if (sub.roleName != null)
                                    Text(sub.roleName!,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context.secondaryText)),
                                ],
                              ),
                            ),
                            if (_isOwner)
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                onPressed: _mutatingSubs
                                    ? null
                                    : () => _removeSub(sub),
                                child: Icon(CupertinoIcons.minus_circle,
                                    size: 20,
                                    color: CupertinoColors.systemRed
                                        .resolveFrom(context)),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/features/rehearsals/ && flutter analyze`
Expected: PASS, clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rehearsals/screens/rehearsal_detail_screen.dart test/features/rehearsals/rehearsal_subs_section_widget_test.dart
git commit -m "feat(rehearsals): subs section on rehearsal detail screen"
```

---

### Task B4: Long-press invite from the schedule list

**Files:**
- Modify: `lib/features/rehearsals/screens/rehearsals_screen.dart` (`_RehearsalSubTile`, ~line 223)

**Interfaces:**
- Consumes: `showRehearsalSubPicker` (B2), `RehearsalsRepository.addSub/getRehearsalByKey` (B1), `authProvider`/`selectedBandProvider` owner check (same as B3).

- [ ] **Step 1: Implement the long-press action**

Convert `_RehearsalSubTile` from `StatelessWidget` to `ConsumerWidget` (build gains `WidgetRef ref`). Add imports for `auth_provider.dart`, `selected_band_provider.dart`, `rehearsals_repository.dart`, and `../widgets/rehearsal_sub_picker_sheet.dart`. Add to the `GestureDetector`:

```dart
      onLongPress: () {
        final bandId = ref.read(selectedBandProvider).valueOrNull;
        final auth = ref.read(authProvider).valueOrNull;
        final isOwner = bandId != null &&
            auth is AuthAuthenticated &&
            auth.bands.any((b) => b.id == bandId && b.isOwner);
        if (!isOwner || rehearsal.isCancelled) return;

        showCupertinoModalPopup<void>(
          context: context,
          builder: (sheetContext) => CupertinoActionSheet(
            title: Text(_formatDate(rehearsal)),
            actions: [
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _inviteSub(context, ref, bandId);
                },
                child: const Text('Invite Sub…'),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Cancel'),
            ),
          ),
        );
      },
```

And add the handler as a method on `_RehearsalSubTile`:

```dart
  Future<void> _inviteSub(
      BuildContext context, WidgetRef ref, int bandId) async {
    final repo = ref.read(rehearsalsRepositoryProvider);

    try {
      // Virtual occurrences must be materialized first; the by-key endpoint
      // creates the row and returns its real id.
      var id = rehearsal.id;
      if (id == null) {
        final key = rehearsal.eventKey;
        if (key == null) return;
        final detail = await repo.getRehearsalByKey(key);
        id = detail.id;
      }
      if (!context.mounted) return;

      final result = await showRehearsalSubPicker(context, bandId: bandId);
      if (result == null) return;

      await repo.addSub(
        id,
        callListEntryId: result.callListEntryId,
        name: result.name,
        email: result.email,
        phone: result.phone,
        bandRoleId: result.bandRoleId,
      );

      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Sub invited'),
            content: const Text('They\'ll get an email with the details.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(ErrorView.friendlyMessage(e)),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        );
      }
    }
  }
```

(Add the `ErrorView` import: `package:tts_bandmate/shared/widgets/error_view.dart`.)

- [ ] **Step 2: Run analyzer + full Flutter test suite**

Run: `flutter analyze && flutter test`
Expected: clean, all green.

- [ ] **Step 3: Commit**

```bash
git add lib/features/rehearsals/screens/rehearsals_screen.dart
git commit -m "feat(rehearsals): long-press invite-sub action on schedule rows"
```

---

### Task B5: Push tap deep-link for `rehearsal_sub_added`

**Files:**
- Modify: `lib/features/notifications/data/push_route.dart`
- Test: `test/notifications/push_route_test.dart`

**Interfaces:**
- Consumes: backend push payload `{type: 'rehearsal_sub_added', rehearsalId}` (Task A4).
- Produces: tapping an invite push opens `/rehearsals/{id}`. `rehearsal_sub_removed` deliberately keeps **no** destination — a removed sub can no longer view the rehearsal, and deep-linking them into a 403 would be worse than opening nothing. (The pushes are sent `alert = true` / OS-rendered, so `buildBackgroundNotification` and `PushType` need no changes.)

- [ ] **Step 1: Write the failing test**

Append to `test/notifications/push_route_test.dart` (match its existing test style):

```dart
  test('rehearsal_sub_added routes to rehearsal detail', () {
    expect(
      routeForPushData({'type': 'rehearsal_sub_added', 'rehearsalId': '42'}),
      '/rehearsals/42',
    );
  });

  test('rehearsal_sub_removed has no destination', () {
    expect(
      routeForPushData({'type': 'rehearsal_sub_removed', 'rehearsalId': '42'}),
      isNull,
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/notifications/push_route_test.dart`
Expected: first new test FAILS (returns null).

- [ ] **Step 3: Implement**

In `lib/features/notifications/data/push_route.dart`, change the rehearsal type check (line 19) to:

```dart
  const rehearsalTypes = {
    'rehearsal_cancelled',
    'rehearsal_restored',
    'rehearsal_sub_added',
  };
  if (!rehearsalTypes.contains(type)) {
    return null;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/notifications/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/data/push_route.dart test/notifications/push_route_test.dart
git commit -m "feat(rehearsals): deep-link rehearsal_sub_added push taps"
```

---

### Task B6: Final verification + PR

- [ ] **Step 1: Full checks**

Run: `flutter analyze && flutter test`
Expected: no warnings, all tests pass.

- [ ] **Step 2: Push and open PR against main**

```bash
git push -u origin feat/rehearsal-sub-invites
gh pr create --base main --title "feat: invite subs to individual rehearsals" --body "$(cat <<'EOF'
## Summary
- Subs section on the rehearsal detail screen (owner-only add/remove, role badges)
- Sub picker: call lists grouped by instrument + ad-hoc invite-by-email form
- Long-press "Invite Sub…" on schedule rows (materializes virtual occurrences via by-key)
- RehearsalSub model, subs in RehearsalDetail, addSub/removeSub repository methods

Backend: TTS `feat/rehearsal-subs` (must be deployed to staging first).
Spec: docs/superpowers/specs/2026-08-01-rehearsal-sub-invites-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Wait for Copilot review and address comments.**

- [ ] **Step 4: On-device verification** (use the `run-on-device` skill against the local backend): invite from detail screen (call list + ad-hoc), remove, long-press on a virtual schedule row, and — with a sub account — confirm the invited rehearsal appears and others don't. Test at narrow width (~320pt): the subs rows and picker must not overflow.

---

## Residual risks / follow-ups (documented, not tasks)

- A non-owner member with `write:rehearsals` can use the API but sees no invite UI (call lists are owner-only). Acceptable v1 trade-off.
- A sub invited after login needs a token refresh/re-login before the schedules **list** loads (detail deep-links work immediately — no ability middleware on those routes).
- Ad-hoc invitee who registers later isn't auto-linked (spec: out of scope).
