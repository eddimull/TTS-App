# Lodging Domain — Backend + Web Implementation Plan (TTS repo)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote lodging to a first-class band-scoped domain (lodgings + rooms + attachments) with web Inertia pages and mobile API endpoints, replacing the legacy `additional_data.lodging` editor UI.

**Architecture:** Three relational tables (`lodgings`, `lodging_rooms`, `lodging_attachments`); `Lodging` broadcasts via `BroadcastsBandChanges`; new `read:lodging`/`write:lodging` abilities; mobile controller + `LodgingService` formatter pair; Rehearsals-style Inertia pages; attachments served through authenticated routes (NOT the public `/images/` proxy).

**Tech Stack:** Laravel 10, Sanctum, Spatie permissions (teams), Inertia + Vue 3, Vitest, MySQL.

**Repo:** `/home/eddie/github/TTS` — work on a fresh branch `feat/lodging-domain` off `staging`. PR base is `staging` (auto-deploys on merge).

## Global Constraints

- All PHP/artisan/npm commands run inside the container: `docker-compose exec app <cmd>` (hyphenated `docker-compose` in this repo). Never on the host.
- Tests: `docker-compose exec app php artisan test --filter=Lodging` while iterating; full `--parallel` run before the PR. Never call paratest directly.
- Vue tests: `docker-compose exec app npx vitest run <path>`. Assert on `wrapper.text()`, never on `<!--v-if-->` markers.
- Response shape: named top-level keys (`{"lodging": ...}`), **no** `data` wrapper.
- Wire datetimes: `Y-m-d H:i:s` strings, band-local semantics (same as events; no timezone conversion).
- Migration filenames: `2026_08_04_00000N_...` sequential-suffix convention.
- Conventional commits (`feat:`, `test:`, `refactor:`); commit after each task.
- Old `additional_data.lodging` JSON stays in the DB and keeps flowing through `EventDataService::parseAdditionalData` unchanged (old app versions still read it); only the web editor UI and default seeding are removed.

---

### Task 1: Migrations + models

**Files:**
- Create: `database/migrations/2026_08_04_000001_create_lodgings_tables.php`
- Create: `database/migrations/2026_08_04_000002_add_lodging_permission.php`
- Create: `app/Models/Lodging.php`, `app/Models/LodgingRoom.php`, `app/Models/LodgingAttachment.php`
- Modify: `app/Services/Mobile/TokenService.php:10` (RESOURCES const)
- Modify: `app/Models/User.php` (~line 240, `canRead`)
- Test: `tests/Feature/LodgingModelTest.php`

**Interfaces:**
- Produces: `Lodging` (relations `band()`, `booking()`, `event()`, `rooms()`, `attachments()`; uses `BroadcastsBandChanges`, `LogsActivity`, `SoftDeletes`), `LodgingRoom`, `LodgingAttachment` (deleting-hook removes the stored file). Abilities `read:lodging` / `write:lodging` exist in tokens and Spatie permissions. Subs with a current sub assignment pass `canRead('lodging', $bandId)`.

- [ ] **Step 1: Write the failing test**

```php
<?php
// tests/Feature/LodgingModelTest.php
namespace Tests\Feature;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\Lodging;
use App\Models\User;
use App\Services\Mobile\TokenService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class LodgingModelTest extends TestCase
{
    use RefreshDatabase;

    public function test_lodging_has_rooms_and_cascades_delete(): void
    {
        $band = Bands::factory()->create();
        $lodging = Lodging::create([
            'band_id'      => $band->id,
            'name'         => 'Hampton Inn',
            'check_in_at'  => now()->addDay(),
            'check_out_at' => now()->addDays(2),
        ]);
        $lodging->rooms()->create(['label' => 'King', 'confirmation_number' => 'ABC123', 'sort_order' => 0]);

        $this->assertCount(1, $lodging->fresh()->rooms);

        $lodging->forceDelete();
        $this->assertDatabaseCount('lodging_rooms', 0);
    }

    public function test_lodging_can_link_booking(): void
    {
        $band = Bands::factory()->create();
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        $lodging = Lodging::create([
            'band_id'      => $band->id,
            'name'         => 'Hotel',
            'check_in_at'  => now(),
            'check_out_at' => now()->addDay(),
            'booking_id'   => $booking->id,
        ]);
        $this->assertTrue($lodging->booking->is($booking));
        $this->assertTrue($booking->lodgings->first()->is($lodging));
    }

    public function test_token_abilities_include_lodging_for_owner(): void
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $abilities = app(TokenService::class)->buildAbilities($user->fresh());
        $this->assertContains('read:lodging', $abilities);
        $this->assertContains('write:lodging', $abilities);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker-compose exec app php artisan test --filter=LodgingModelTest`
Expected: FAIL — `Class "App\Models\Lodging" not found`

- [ ] **Step 3: Write the tables migration**

```php
<?php
// database/migrations/2026_08_04_000001_create_lodgings_tables.php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('lodgings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('band_id')->constrained()->onDelete('cascade');
            $table->string('name');
            $table->string('address')->nullable();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->dateTime('check_in_at');
            $table->dateTime('check_out_at');
            $table->text('notes')->nullable();
            $table->foreignId('booking_id')->nullable()->constrained('bookings')->nullOnDelete();
            $table->foreignId('event_id')->nullable()->constrained('events')->nullOnDelete();
            $table->timestamps();
            $table->softDeletes();
            $table->index(['band_id', 'check_in_at']);
        });

        Schema::create('lodging_rooms', function (Blueprint $table) {
            $table->id();
            $table->foreignId('lodging_id')->constrained()->onDelete('cascade');
            $table->string('label');
            $table->string('confirmation_number')->nullable();
            $table->text('notes')->nullable();
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();
        });

        Schema::create('lodging_attachments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('lodging_id')->constrained()->onDelete('cascade');
            $table->string('filename');
            $table->string('stored_filename');
            $table->string('mime_type');
            $table->unsignedBigInteger('file_size');
            $table->string('disk');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('lodging_attachments');
        Schema::dropIfExists('lodging_rooms');
        Schema::dropIfExists('lodgings');
    }
};
```

- [ ] **Step 4: Write the permission migration** (copy of `2026_04_28_111143_add_questionnaires_permission.php` with `lodging`)

```php
<?php
// database/migrations/2026_08_04_000002_add_lodging_permission.php
use Illuminate\Database\Migrations\Migration;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Spatie\Permission\PermissionRegistrar;

return new class extends Migration
{
    public function up(): void
    {
        app()[PermissionRegistrar::class]->forgetCachedPermissions();

        Permission::firstOrCreate(['name' => 'read:lodging', 'guard_name' => 'web']);
        Permission::firstOrCreate(['name' => 'write:lodging', 'guard_name' => 'web']);

        $ownerRole = Role::where('name', 'band-owner')->where('guard_name', 'web')->first();
        if ($ownerRole) {
            $ownerRole->givePermissionTo(['read:lodging', 'write:lodging']);
        }

        $memberRole = Role::where('name', 'band-member')->where('guard_name', 'web')->first();
        if ($memberRole) {
            $memberRole->givePermissionTo('read:lodging');
        }

        app()[PermissionRegistrar::class]->forgetCachedPermissions();
    }

    public function down(): void
    {
        app()[PermissionRegistrar::class]->forgetCachedPermissions();
        Permission::where('name', 'read:lodging')->where('guard_name', 'web')->get()->each->delete();
        Permission::where('name', 'write:lodging')->where('guard_name', 'web')->get()->each->delete();
        app()[PermissionRegistrar::class]->forgetCachedPermissions();
    }
};
```

- [ ] **Step 5: Write the models**

```php
<?php
// app/Models/Lodging.php
namespace App\Models;

use App\Models\Traits\BroadcastsBandChanges;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Spatie\Activitylog\LogOptions;
use Spatie\Activitylog\Traits\LogsActivity;

class Lodging extends Model
{
    use HasFactory, SoftDeletes, LogsActivity, BroadcastsBandChanges;

    protected $fillable = [
        'band_id', 'name', 'address', 'latitude', 'longitude',
        'check_in_at', 'check_out_at', 'notes', 'booking_id', 'event_id',
    ];

    protected $casts = [
        'check_in_at'  => 'datetime',
        'check_out_at' => 'datetime',
        'latitude'     => 'float',
        'longitude'    => 'float',
    ];

    public function band()
    {
        return $this->belongsTo(Bands::class, 'band_id');
    }

    public function booking()
    {
        return $this->belongsTo(Bookings::class, 'booking_id');
    }

    public function event()
    {
        return $this->belongsTo(Events::class, 'event_id');
    }

    public function rooms()
    {
        return $this->hasMany(LodgingRoom::class)->orderBy('sort_order');
    }

    public function attachments()
    {
        return $this->hasMany(LodgingAttachment::class);
    }

    public function getActivitylogOptions(): LogOptions
    {
        return LogOptions::defaults()
            ->logOnly([
                'name', 'address', 'check_in_at', 'check_out_at',
                'notes', 'booking_id', 'event_id',
            ])
            ->logOnlyDirty()
            ->dontSubmitEmptyLogs();
    }
}
```

```php
<?php
// app/Models/LodgingRoom.php
namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class LodgingRoom extends Model
{
    use HasFactory;

    protected $fillable = ['lodging_id', 'label', 'confirmation_number', 'notes', 'sort_order'];

    public function lodging()
    {
        return $this->belongsTo(Lodging::class);
    }
}
```

```php
<?php
// app/Models/LodgingAttachment.php
namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Storage;

class LodgingAttachment extends Model
{
    use HasFactory;

    protected $fillable = [
        'lodging_id', 'filename', 'stored_filename', 'mime_type', 'file_size', 'disk',
    ];

    public function lodging()
    {
        return $this->belongsTo(Lodging::class);
    }

    protected static function booted()
    {
        static::deleting(function ($attachment) {
            Storage::disk($attachment->disk)->delete($attachment->stored_filename);
        });
    }
}
```

Note: rooms and attachments do NOT get `BroadcastsBandChanges`. Controllers `$lodging->touch()` after room/attachment mutations so the parent lodging broadcasts one `updated` signal (avoids child-model registry entries in the mobile realtime map).

- [ ] **Step 6: Add inverse relations + factory + abilities + canRead carve-out**

In `app/Models/Bookings.php` add:
```php
    public function lodgings()
    {
        return $this->hasMany(Lodging::class, 'booking_id');
    }
```

In `app/Models/Events.php` add:
```php
    public function lodgings()
    {
        return $this->hasMany(Lodging::class, 'event_id');
    }
```

Create `database/factories/LodgingFactory.php`:
```php
<?php
namespace Database\Factories;

use App\Models\Bands;
use Illuminate\Database\Eloquent\Factories\Factory;

class LodgingFactory extends Factory
{
    public function definition(): array
    {
        $checkIn = $this->faker->dateTimeBetween('+1 week', '+2 weeks');
        return [
            'band_id'      => Bands::factory(),
            'name'         => $this->faker->company() . ' Hotel',
            'address'      => $this->faker->address(),
            'check_in_at'  => $checkIn,
            'check_out_at' => (clone $checkIn)->modify('+2 days'),
        ];
    }
}
```

In `app/Services/Mobile/TokenService.php:10` change:
```php
    private const RESOURCES = ['bookings', 'events', 'media', 'rehearsals', 'charts', 'songs', 'questionnaires', 'lodging'];
```

In `app/Models/User.php::canRead()` (after the existing `rehearsals` carve-out, ~line 265) add:
```php
        // Subs may READ lodging for bands they currently sub for; the
        // controller scopes results to stays linked to their assigned gigs.
        if ($resource === 'lodging' && $this->isSubOfBand($bandId)
            && $this->hasCurrentSubAssignmentForBand($bandId)) {
            return true;
        }
```

- [ ] **Step 7: Migrate and run tests**

Run: `docker-compose exec app php artisan migrate`
Run: `docker-compose exec app php artisan test --filter=LodgingModelTest`
Expected: PASS (3 tests)

- [ ] **Step 8: Commit**

```bash
git add database app/Models app/Services/Mobile/TokenService.php tests/Feature/LodgingModelTest.php
git commit -m "feat(lodging): lodgings/rooms/attachments schema, models, abilities"
```

---

### Task 2: Mobile API — LodgingService + CRUD endpoints

**Files:**
- Create: `app/Services/Mobile/LodgingService.php`
- Create: `app/Http/Controllers/Api/Mobile/LodgingsController.php`
- Create: `app/Http/Requests/Mobile/StoreLodgingRequest.php`, `app/Http/Requests/Mobile/UpdateLodgingRequest.php`
- Modify: `routes/api.php` (mobile group, after the events groups ~line 234)
- Test: `tests/Feature/Api/Mobile/LodgingsTest.php`

**Interfaces:**
- Consumes: `Lodging` model + abilities from Task 1; `EnsureUserInBand` middleware (`mobile.band:read:lodging` / `write:lodging`); band from `$request->input('mobile_band')`.
- Produces wire contract used by web props (Task 4) and the Flutter app:

```json
{
  "lodging": {
    "id": 1, "name": "Hampton Inn", "address": "123 Main St",
    "latitude": 30.4, "longitude": -91.1,
    "check_in_at": "2026-08-14 15:00:00", "check_out_at": "2026-08-16 11:00:00",
    "notes": "Park in back", 
    "booking": {"id": 5, "name": "Smith Wedding"},
    "event": {"id": 9, "title": "Reception", "date": "2026-08-15"},
    "rooms": [{"id": 1, "label": "King", "confirmation_number": "ABC123", "notes": null, "sort_order": 0}],
    "attachments": [{"id": 1, "filename": "map.jpg", "mime_type": "image/jpeg", "file_size": 1234, "url": "https://.../api/mobile/lodging-attachments/1"}]
  },
  "can_write": true
}
```
List: `{"lodgings": [ ...summary objects (no rooms/attachments detail, but room_count + attachment_count)... ], "can_write": bool}`.
- Rooms sync semantics: payload `rooms` array — items with `id` update, without `id` insert, ids absent from payload delete.

- [ ] **Step 1: Write the failing tests**

```php
<?php
// tests/Feature/Api/Mobile/LodgingsTest.php
namespace Tests\Feature\Api\Mobile;

use App\Models\Bands;
use App\Models\Lodging;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class LodgingsTest extends TestCase
{
    use RefreshDatabase;

    private function createOwnerWithBand(): array
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);
        $token = $user->createToken('test-device')->plainTextToken;
        return compact('user', 'band', 'token');
    }

    public function test_index_requires_band_header(): void
    {
        ['band' => $band, 'token' => $token] = $this->createOwnerWithBand();
        $this->withToken($token)
            ->getJson("/api/mobile/bands/{$band->id}/lodgings")
            ->assertStatus(422);
    }

    public function test_index_returns_403_for_non_member(): void
    {
        ['band' => $band] = $this->createOwnerWithBand();
        $stranger = User::factory()->create();
        $token = $stranger->createToken('test-device')->plainTextToken;
        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/lodgings")
            ->assertStatus(403);
    }

    public function test_index_lists_band_lodgings_upcoming_first(): void
    {
        ['band' => $band, 'token' => $token] = $this->createOwnerWithBand();
        Lodging::factory()->create([
            'band_id' => $band->id, 'name' => 'Later Hotel',
            'check_in_at' => now()->addDays(20), 'check_out_at' => now()->addDays(21),
        ]);
        Lodging::factory()->create([
            'band_id' => $band->id, 'name' => 'Sooner Hotel',
            'check_in_at' => now()->addDays(5), 'check_out_at' => now()->addDays(6),
        ]);
        // Another band's lodging must not leak.
        Lodging::factory()->create(['name' => 'Other Band Hotel']);

        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/lodgings")
            ->assertOk()
            ->json();

        $names = array_column($response['lodgings'], 'name');
        $this->assertSame(['Sooner Hotel', 'Later Hotel'], $names);
        $this->assertTrue($response['can_write']);
    }

    public function test_store_creates_lodging_with_rooms(): void
    {
        ['band' => $band, 'token' => $token] = $this->createOwnerWithBand();

        $checkIn  = now()->addDays(10)->format('Y-m-d') . ' 15:00:00';
        $checkOut = now()->addDays(12)->format('Y-m-d') . ' 11:00:00';

        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->postJson("/api/mobile/bands/{$band->id}/lodgings", [
                'name'         => 'Hampton Inn',
                'address'      => '123 Main St',
                'latitude'     => 30.4,
                'longitude'    => -91.1,
                'check_in_at'  => $checkIn,
                'check_out_at' => $checkOut,
                'notes'        => 'Park in back',
                'rooms'        => [
                    ['label' => 'King', 'confirmation_number' => 'ABC123'],
                    ['label' => 'Double Queen', 'notes' => 'near elevator'],
                ],
            ])
            ->assertStatus(201)
            ->json();

        $this->assertSame('Hampton Inn', $response['lodging']['name']);
        $this->assertCount(2, $response['lodging']['rooms']);
        $this->assertDatabaseHas('lodging_rooms', ['label' => 'King', 'confirmation_number' => 'ABC123']);
    }

    public function test_update_syncs_rooms_by_id(): void
    {
        ['band' => $band, 'token' => $token] = $this->createOwnerWithBand();
        $lodging = Lodging::factory()->create(['band_id' => $band->id]);
        $keep   = $lodging->rooms()->create(['label' => 'King', 'sort_order' => 0]);
        $lodging->rooms()->create(['label' => 'Doomed', 'sort_order' => 1]);

        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->patchJson("/api/mobile/bands/{$band->id}/lodgings/{$lodging->id}", [
                'rooms' => [
                    ['id' => $keep->id, 'label' => 'King Renamed'],
                    ['label' => 'Brand New'],
                ],
            ])
            ->assertOk()
            ->json();

        $labels = array_column($response['lodging']['rooms'], 'label');
        $this->assertSame(['King Renamed', 'Brand New'], $labels);
        $this->assertDatabaseMissing('lodging_rooms', ['label' => 'Doomed']);
    }

    public function test_member_without_write_cannot_store(): void
    {
        ['band' => $band] = $this->createOwnerWithBand();
        $member = User::factory()->create();
        $band->members()->create(['user_id' => $member->id]);
        $token = $member->createToken('test-device')->plainTextToken;

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->postJson("/api/mobile/bands/{$band->id}/lodgings", [
                'name'         => 'Nope',
                'check_in_at'  => now()->addDay()->format('Y-m-d H:i:s'),
                'check_out_at' => now()->addDays(2)->format('Y-m-d H:i:s'),
            ])
            ->assertStatus(403);
    }

    public function test_destroy_soft_deletes(): void
    {
        ['band' => $band, 'token' => $token] = $this->createOwnerWithBand();
        $lodging = Lodging::factory()->create(['band_id' => $band->id]);

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->deleteJson("/api/mobile/bands/{$band->id}/lodgings/{$lodging->id}")
            ->assertOk();

        $this->assertSoftDeleted('lodgings', ['id' => $lodging->id]);
    }
}
```

Note: check `Bands` model for the members relation name used by `$band->members()->create(...)` — `EventsTest.php` uses `$band->owners()->create(...)`; mirror whatever member equivalent exists (grep `function members` in `app/Models/Bands.php`; if it's `belongsToMany`, use `$band->members()->attach($member->id)`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker-compose exec app php artisan test --filter=LodgingsTest`
Expected: FAIL — 404s (routes not defined)

- [ ] **Step 3: Write FormRequests**

```php
<?php
// app/Http/Requests/Mobile/StoreLodgingRequest.php
namespace App\Http\Requests\Mobile;

use Illuminate\Foundation\Http\FormRequest;

class StoreLodgingRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // Auth handled by middleware (auth:sanctum + mobile.band:write:lodging)
    }

    public function rules(): array
    {
        return [
            'name'                       => 'required|string|max:255',
            'address'                    => 'nullable|string|max:255',
            'latitude'                   => 'nullable|numeric|between:-90,90',
            'longitude'                  => 'nullable|numeric|between:-180,180',
            'check_in_at'                => 'required|date_format:Y-m-d H:i:s',
            'check_out_at'               => 'required|date_format:Y-m-d H:i:s|after:check_in_at',
            'notes'                      => 'nullable|string',
            'booking_id'                 => 'nullable|integer|exists:bookings,id',
            'event_id'                   => 'nullable|integer|exists:events,id',
            'rooms'                      => 'sometimes|array',
            'rooms.*.label'              => 'required|string|max:255',
            'rooms.*.confirmation_number'=> 'nullable|string|max:255',
            'rooms.*.notes'              => 'nullable|string',
        ];
    }
}
```

```php
<?php
// app/Http/Requests/Mobile/UpdateLodgingRequest.php
namespace App\Http\Requests\Mobile;

use Illuminate\Foundation\Http\FormRequest;

class UpdateLodgingRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // Auth handled by middleware (auth:sanctum + mobile.band:write:lodging)
    }

    public function rules(): array
    {
        // PATCH semantics: everything optional, validated when present.
        return [
            'name'                       => 'sometimes|required|string|max:255',
            'address'                    => 'sometimes|nullable|string|max:255',
            'latitude'                   => 'sometimes|nullable|numeric|between:-90,90',
            'longitude'                  => 'sometimes|nullable|numeric|between:-180,180',
            'check_in_at'                => 'sometimes|required|date_format:Y-m-d H:i:s',
            'check_out_at'               => 'sometimes|required|date_format:Y-m-d H:i:s',
            'notes'                      => 'sometimes|nullable|string',
            'booking_id'                 => 'sometimes|nullable|integer|exists:bookings,id',
            'event_id'                   => 'sometimes|nullable|integer|exists:events,id',
            'rooms'                      => 'sometimes|array',
            'rooms.*.id'                 => 'sometimes|integer',
            'rooms.*.label'              => 'required|string|max:255',
            'rooms.*.confirmation_number'=> 'nullable|string|max:255',
            'rooms.*.notes'              => 'nullable|string',
        ];
    }
}
```

- [ ] **Step 4: Write LodgingService**

```php
<?php
// app/Services/Mobile/LodgingService.php
namespace App\Services\Mobile;

use App\Models\Lodging;
use App\Models\LodgingAttachment;

class LodgingService
{
    public function formatSummary(Lodging $lodging): array
    {
        return [
            'id'               => $lodging->id,
            'name'             => $lodging->name,
            'address'          => $lodging->address,
            'check_in_at'      => $lodging->check_in_at?->format('Y-m-d H:i:s'),
            'check_out_at'     => $lodging->check_out_at?->format('Y-m-d H:i:s'),
            'room_count'       => $lodging->rooms_count ?? $lodging->rooms()->count(),
            'attachment_count' => $lodging->attachments_count ?? $lodging->attachments()->count(),
            'booking_id'       => $lodging->booking_id,
            'event_id'         => $lodging->event_id,
        ];
    }

    public function formatDetail(Lodging $lodging): array
    {
        $lodging->loadMissing(['rooms', 'attachments', 'booking:id,name', 'event:id,title,date']);

        return [
            'id'           => $lodging->id,
            'name'         => $lodging->name,
            'address'      => $lodging->address,
            'latitude'     => $lodging->latitude,
            'longitude'    => $lodging->longitude,
            'check_in_at'  => $lodging->check_in_at?->format('Y-m-d H:i:s'),
            'check_out_at' => $lodging->check_out_at?->format('Y-m-d H:i:s'),
            'notes'        => $lodging->notes,
            'booking'      => $lodging->booking ? ['id' => $lodging->booking->id, 'name' => $lodging->booking->name] : null,
            'event'        => $lodging->event ? [
                'id'    => $lodging->event->id,
                'title' => $lodging->event->title,
                'date'  => $lodging->event->date,
            ] : null,
            'rooms'        => $lodging->rooms->map(fn ($r) => [
                'id'                  => $r->id,
                'label'               => $r->label,
                'confirmation_number' => $r->confirmation_number,
                'notes'               => $r->notes,
                'sort_order'          => $r->sort_order,
            ])->values()->toArray(),
            'attachments'  => $lodging->attachments->map(fn ($a) => $this->formatAttachment($a))->values()->toArray(),
        ];
    }

    public function formatAttachment(LodgingAttachment $attachment): array
    {
        return [
            'id'        => $attachment->id,
            'filename'  => $attachment->filename,
            'mime_type' => $attachment->mime_type,
            'file_size' => $attachment->file_size,
            // Sanctum-authenticated serve route (Task 3) — NOT the public /images/ proxy.
            'url'       => url('/api/mobile/lodging-attachments/' . $attachment->id),
        ];
    }

    /**
     * Sync the rooms set: items with id update, items without id insert,
     * db rows whose ids are absent from the payload are deleted.
     */
    public function syncRooms(Lodging $lodging, array $rooms): void
    {
        $keptIds = [];
        foreach (array_values($rooms) as $i => $room) {
            $attributes = [
                'label'               => $room['label'],
                'confirmation_number' => $room['confirmation_number'] ?? null,
                'notes'               => $room['notes'] ?? null,
                'sort_order'          => $i,
            ];
            if (!empty($room['id'])) {
                $existing = $lodging->rooms()->find($room['id']);
                if ($existing) {
                    $existing->update($attributes);
                    $keptIds[] = $existing->id;
                    continue;
                }
            }
            $keptIds[] = $lodging->rooms()->create($attributes)->id;
        }
        $lodging->rooms()->whereNotIn('id', $keptIds)->delete();
    }
}
```

- [ ] **Step 5: Write the controller**

```php
<?php
// app/Http/Controllers/Api/Mobile/LodgingsController.php
namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Http\Requests\Mobile\StoreLodgingRequest;
use App\Http\Requests\Mobile\UpdateLodgingRequest;
use App\Models\Bookings;
use App\Models\Lodging;
use App\Services\Mobile\LodgingService;
use App\Services\UserEventsService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class LodgingsController extends Controller
{
    public function __construct(private readonly LodgingService $lodgingService)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $band = $request->input('mobile_band');
        $user = $request->user();

        $query = Lodging::where('band_id', $band->id)
            ->withCount(['rooms', 'attachments'])
            ->orderBy('check_in_at');

        $this->scopeForSubs($query, $user, $band);

        return response()->json([
            'lodgings'  => $query->get()->map(fn ($l) => $this->lodgingService->formatSummary($l))->values(),
            'can_write' => $user->canWrite('lodging', $band->id),
        ]);
    }

    public function show(Request $request, Lodging $lodging): JsonResponse
    {
        $band = $request->input('mobile_band');
        abort_if($lodging->band_id !== $band->id, 404);
        $user = $request->user();

        if (!$user->bands()->contains('id', $band->id) && !$this->subCanSee($lodging, $user)) {
            abort(404);
        }

        return response()->json([
            'lodging'   => $this->lodgingService->formatDetail($lodging),
            'can_write' => $user->canWrite('lodging', $band->id),
        ]);
    }

    public function store(StoreLodgingRequest $request): JsonResponse
    {
        $band = $request->input('mobile_band');
        $data = $request->validated();
        $rooms = $data['rooms'] ?? [];
        unset($data['rooms']);

        $this->assertLinksBelongToBand($data, $band->id);

        $lodging = Lodging::create($data + ['band_id' => $band->id]);
        $this->lodgingService->syncRooms($lodging, $rooms);

        return response()->json(['lodging' => $this->lodgingService->formatDetail($lodging->fresh())], 201);
    }

    public function update(UpdateLodgingRequest $request, Lodging $lodging): JsonResponse
    {
        $band = $request->input('mobile_band');
        abort_if($lodging->band_id !== $band->id, 404);

        $data = $request->validated();
        $rooms = $data['rooms'] ?? null;
        unset($data['rooms']);

        $this->assertLinksBelongToBand($data, $band->id);

        if ($data !== []) {
            $lodging->update($data);
        }
        if ($rooms !== null) {
            $this->lodgingService->syncRooms($lodging, $rooms);
            $lodging->touch(); // broadcast one parent update for room changes
        }

        return response()->json(['lodging' => $this->lodgingService->formatDetail($lodging->fresh())]);
    }

    public function destroy(Request $request, Lodging $lodging): JsonResponse
    {
        $band = $request->input('mobile_band');
        abort_if($lodging->band_id !== $band->id, 404);

        $lodging->delete();

        return response()->json(['message' => 'Lodging deleted.']);
    }

    /** Reject booking_id/event_id pointing outside this band. */
    private function assertLinksBelongToBand(array $data, int $bandId): void
    {
        if (!empty($data['booking_id'])) {
            abort_unless(
                Bookings::where('id', $data['booking_id'])->where('band_id', $bandId)->exists(),
                422,
                'Booking does not belong to this band.'
            );
        }
        if (!empty($data['event_id'])) {
            $event = \App\Models\Events::find($data['event_id']);
            abort_unless($event && (int) ($event->eventable?->band_id) === $bandId, 422,
                'Event does not belong to this band.');
        }
    }

    /** Sub-only users see only stays linked to their assigned gigs. */
    private function scopeForSubs($query, $user, $band): void
    {
        if ($user->bands()->contains('id', $band->id)) {
            return; // full member/owner — no scoping
        }
        $eventIds = app(UserEventsService::class)->getEventIds(Carbon::now()->subYear());
        $bookingIds = \App\Models\Events::whereIn('id', $eventIds)
            ->where('eventable_type', Bookings::class)
            ->pluck('eventable_id');

        $query->where(function ($q) use ($eventIds, $bookingIds) {
            $q->whereIn('event_id', $eventIds)
              ->orWhereIn('booking_id', $bookingIds);
        });
    }

    private function subCanSee(Lodging $lodging, $user): bool
    {
        if (!$lodging->event_id && !$lodging->booking_id) {
            return false;
        }
        $eventIds = app(UserEventsService::class)->getEventIds(Carbon::now()->subYear());
        if ($lodging->event_id && $eventIds->contains($lodging->event_id)) {
            return true;
        }
        if ($lodging->booking_id) {
            return \App\Models\Events::whereIn('id', $eventIds)
                ->where('eventable_type', Bookings::class)
                ->where('eventable_id', $lodging->booking_id)
                ->exists();
        }
        return false;
    }
}
```

Check `UserEventsService::getEventIds()` return type (collection vs array) at `app/Services/UserEventsService.php:24-32` and adapt `contains`/`whereIn` accordingly. Note the mandatory `setPermissionsTeamId(0)` prelude is inside `UserEventsService`, so calling it is safe from mobile.

- [ ] **Step 6: Register routes** in `routes/api.php`, after the events write group (~line 234):

```php
        // ── Lodging (read) ─────────────────────────────────────────────
        Route::middleware('mobile.band:read:lodging')->scopeBindings()->group(function () {
            Route::get('/bands/{band}/lodgings', [\App\Http\Controllers\Api\Mobile\LodgingsController::class, 'index'])->name('mobile.lodgings.index');
            Route::get('/bands/{band}/lodgings/{lodging}', [\App\Http\Controllers\Api\Mobile\LodgingsController::class, 'show'])->name('mobile.lodgings.show');
        });

        // ── Lodging (write) ────────────────────────────────────────────
        Route::middleware('mobile.band:write:lodging')->scopeBindings()->group(function () {
            Route::post('/bands/{band}/lodgings', [\App\Http\Controllers\Api\Mobile\LodgingsController::class, 'store'])->name('mobile.lodgings.store');
            Route::patch('/bands/{band}/lodgings/{lodging}', [\App\Http\Controllers\Api\Mobile\LodgingsController::class, 'update'])->name('mobile.lodgings.update');
            Route::delete('/bands/{band}/lodgings/{lodging}', [\App\Http\Controllers\Api\Mobile\LodgingsController::class, 'destroy'])->name('mobile.lodgings.destroy');
        });
```

Match the fully-qualified-class style used by neighbouring routes in the file (some use `use` imports at top — follow whatever `routes/api.php` already does).

- [ ] **Step 7: Run tests**

Run: `docker-compose exec app php artisan test --filter=LodgingsTest`
Expected: PASS (7 tests)

- [ ] **Step 8: Commit**

```bash
git add app/Http app/Services/Mobile/LodgingService.php routes/api.php tests/Feature/Api/Mobile/LodgingsTest.php
git commit -m "feat(lodging): mobile CRUD API with nested room sync"
```

---

### Task 3: Attachments — upload, delete, authenticated serve (mobile + web routes)

**Files:**
- Create: `app/Http/Controllers/Api/Mobile/LodgingAttachmentsController.php`
- Create: `app/Http/Requests/Mobile/UploadLodgingAttachmentRequest.php`
- Modify: `routes/api.php` (inside the lodging write group + one sanctum-only serve route)
- Test: `tests/Feature/Api/Mobile/LodgingAttachmentsTest.php`

**Interfaces:**
- Consumes: `LodgingAttachment` model (Task 1), `LodgingService::formatAttachment` (Task 2).
- Produces: `POST /api/mobile/bands/{band}/lodgings/{lodging}/attachments` (multipart field `file`) → 201 `{"attachment": {...}}`; `DELETE .../attachments/{attachment}` → `{"message": "Attachment deleted."}`; `GET /api/mobile/lodging-attachments/{attachment}` → raw bytes with Content-Type (sanctum auth + canRead check). Storage path: `{band->site_name}/lodging_uploads/{uuid}.{ext}` on `config('filesystems.default')`.

- [ ] **Step 1: Write the failing tests**

```php
<?php
// tests/Feature/Api/Mobile/LodgingAttachmentsTest.php
namespace Tests\Feature\Api\Mobile;

use App\Models\Bands;
use App\Models\Lodging;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class LodgingAttachmentsTest extends TestCase
{
    use RefreshDatabase;

    private function createOwnerWithLodging(): array
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);
        $lodging = Lodging::factory()->create(['band_id' => $band->id]);
        $token = $user->createToken('test-device')->plainTextToken;
        return compact('user', 'band', 'lodging', 'token');
    }

    public function test_upload_stores_file_and_returns_attachment(): void
    {
        Storage::fake(config('filesystems.default'));
        ['band' => $band, 'lodging' => $lodging, 'token' => $token] = $this->createOwnerWithLodging();

        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->post("/api/mobile/bands/{$band->id}/lodgings/{$lodging->id}/attachments", [
                'file' => UploadedFile::fake()->image('confirmation.jpg'),
            ])
            ->assertStatus(201)
            ->json();

        $this->assertSame('confirmation.jpg', $response['attachment']['filename']);
        $this->assertStringContainsString('/api/mobile/lodging-attachments/', $response['attachment']['url']);
        $this->assertDatabaseHas('lodging_attachments', ['lodging_id' => $lodging->id]);
        Storage::disk(config('filesystems.default'))
            ->assertExists($lodging->attachments()->first()->stored_filename);
    }

    public function test_serve_returns_bytes_for_member_and_403_for_stranger(): void
    {
        Storage::fake(config('filesystems.default'));
        ['band' => $band, 'lodging' => $lodging, 'token' => $token] = $this->createOwnerWithLodging();

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->post("/api/mobile/bands/{$band->id}/lodgings/{$lodging->id}/attachments", [
                'file' => UploadedFile::fake()->image('map.jpg'),
            ])->assertStatus(201);

        $attachment = $lodging->attachments()->first();

        $this->withToken($token)
            ->get("/api/mobile/lodging-attachments/{$attachment->id}")
            ->assertOk()
            ->assertHeader('Content-Type', 'image/jpeg');

        $stranger = User::factory()->create();
        $strangerToken = $stranger->createToken('test-device')->plainTextToken;
        $this->withToken($strangerToken)
            ->get("/api/mobile/lodging-attachments/{$attachment->id}")
            ->assertStatus(403);
    }

    public function test_delete_removes_row_and_file(): void
    {
        Storage::fake(config('filesystems.default'));
        ['band' => $band, 'lodging' => $lodging, 'token' => $token] = $this->createOwnerWithLodging();

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->post("/api/mobile/bands/{$band->id}/lodgings/{$lodging->id}/attachments", [
                'file' => UploadedFile::fake()->image('gone.jpg'),
            ])->assertStatus(201);

        $attachment = $lodging->attachments()->first();
        $storedPath = $attachment->stored_filename;

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->deleteJson("/api/mobile/bands/{$band->id}/lodgings/{$lodging->id}/attachments/{$attachment->id}")
            ->assertOk();

        $this->assertDatabaseMissing('lodging_attachments', ['id' => $attachment->id]);
        Storage::disk(config('filesystems.default'))->assertMissing($storedPath);
    }

    public function test_attachment_from_other_lodging_404s(): void
    {
        Storage::fake(config('filesystems.default'));
        ['band' => $band, 'lodging' => $lodging, 'token' => $token] = $this->createOwnerWithLodging();
        $otherLodging = Lodging::factory()->create(['band_id' => $band->id]);
        $foreign = $otherLodging->attachments()->create([
            'filename' => 'x.jpg', 'stored_filename' => 'x/x.jpg',
            'mime_type' => 'image/jpeg', 'file_size' => 1, 'disk' => config('filesystems.default'),
        ]);

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->deleteJson("/api/mobile/bands/{$band->id}/lodgings/{$lodging->id}/attachments/{$foreign->id}")
            ->assertStatus(404);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker-compose exec app php artisan test --filter=LodgingAttachmentsTest`
Expected: FAIL — 404s

- [ ] **Step 3: Write request + controller**

```php
<?php
// app/Http/Requests/Mobile/UploadLodgingAttachmentRequest.php
namespace App\Http\Requests\Mobile;

use Illuminate\Foundation\Http\FormRequest;

class UploadLodgingAttachmentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // Auth handled by middleware (auth:sanctum + mobile.band:write:lodging)
    }

    public function rules(): array
    {
        return ['file' => 'required|file|max:10240']; // 10MB, matches event attachments
    }
}
```

```php
<?php
// app/Http/Controllers/Api/Mobile/LodgingAttachmentsController.php
namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Http\Requests\Mobile\UploadLodgingAttachmentRequest;
use App\Models\Lodging;
use App\Models\LodgingAttachment;
use App\Services\Mobile\LodgingService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class LodgingAttachmentsController extends Controller
{
    public function __construct(private readonly LodgingService $lodgingService)
    {
    }

    public function store(UploadLodgingAttachmentRequest $request, Lodging $lodging): JsonResponse
    {
        $band = $request->input('mobile_band');
        abort_if($lodging->band_id !== $band->id, 404);

        $file      = $request->file('file');
        $disk      = config('filesystems.default');
        $extension = $file->getClientOriginalExtension();
        $filename  = Str::uuid() . ($extension ? '.' . $extension : '');
        $path      = $file->storeAs($band->site_name . '/lodging_uploads', $filename, $disk);

        $attachment = LodgingAttachment::create([
            'lodging_id'      => $lodging->id,
            'filename'        => $file->getClientOriginalName(),
            'stored_filename' => $path,
            'mime_type'       => $file->getMimeType(),
            'file_size'       => $file->getSize(),
            'disk'            => $disk,
        ]);
        $lodging->touch(); // broadcast parent update

        return response()->json(['attachment' => $this->lodgingService->formatAttachment($attachment)], 201);
    }

    public function destroy(Request $request, Lodging $lodging, LodgingAttachment $attachment): JsonResponse
    {
        $band = $request->input('mobile_band');
        abort_if($lodging->band_id !== $band->id, 404);
        abort_if($attachment->lodging_id !== $lodging->id, 404);

        $attachment->delete(); // model hook removes the stored file
        $lodging->touch();

        return response()->json(['message' => 'Attachment deleted.']);
    }

    /**
     * Serve bytes with auth. Deliberately NOT the public /images/ proxy —
     * lodging attachments can contain confirmation numbers.
     */
    public function show(Request $request, LodgingAttachment $attachment)
    {
        $user = $request->user();
        $bandId = $attachment->lodging->band_id;
        if (!$user || !$user->canRead('lodging', $bandId)) {
            abort(403, 'You do not have permission to view this file');
        }

        try {
            $file = Storage::disk($attachment->disk)->get($attachment->stored_filename);
            return response($file)
                ->header('Content-Type', $attachment->mime_type)
                ->header('Content-Disposition', 'inline; filename="' . $attachment->filename . '"')
                ->header('Cache-Control', 'private, max-age=3600');
        } catch (\Exception $e) {
            abort(404, 'File not found');
        }
    }
}
```

- [ ] **Step 4: Register routes**

Inside the lodging **write** group from Task 2 add:
```php
            Route::post('/bands/{band}/lodgings/{lodging}/attachments', [\App\Http\Controllers\Api\Mobile\LodgingAttachmentsController::class, 'store'])->name('mobile.lodgings.attachments.store');
            Route::delete('/bands/{band}/lodgings/{lodging}/attachments/{attachment}', [\App\Http\Controllers\Api\Mobile\LodgingAttachmentsController::class, 'destroy'])->name('mobile.lodgings.attachments.destroy');
```
Note: `{lodging}/{attachment}` scoping is done manually via `abort_if` in the controller (the nested binding may not scope through `lodging` — the events attachment routes do the same, see `Api/Mobile/EventsController::deleteAttachment`).

In the plain `auth:sanctum` section of the mobile group (near the event attachment routes ~line 86) add:
```php
        Route::get('/lodging-attachments/{attachment}', [\App\Http\Controllers\Api\Mobile\LodgingAttachmentsController::class, 'show'])->name('mobile.lodging-attachments.show');
```
The serve route binds `{attachment}` to `LodgingAttachment` — confirm implicit binding resolves (parameter name must match the controller signature `$attachment`; add `->whereNumber('attachment')`).

- [ ] **Step 5: Run tests**

Run: `docker-compose exec app php artisan test --filter=LodgingAttachmentsTest`
Expected: PASS (4 tests)

- [ ] **Step 6: Commit**

```bash
git add app/Http routes/api.php tests/Feature/Api/Mobile/LodgingAttachmentsTest.php
git commit -m "feat(lodging): attachment upload/delete + authenticated serve"
```

---

### Task 4: Sub visibility test + event/booking detail lodging summaries

**Files:**
- Modify: `app/Services/Mobile/EventDataService.php` (`formatForShow`, ~line 399 props array)
- Modify: `app/Services/Mobile/BookingService.php` (booking detail formatter — find the method that builds the booking show payload)
- Test: `tests/Feature/Api/Mobile/LodgingSubVisibilityTest.php`, extend existing event detail test

**Interfaces:**
- Consumes: `LodgingService::formatSummary` (Task 2), `Events::lodgings()` / `Bookings::lodgings()` (Task 1).
- Produces: `lodgings` key (array of summary objects) on the mobile event detail and booking detail payloads.

- [ ] **Step 1: Write the failing sub-visibility test**

```php
<?php
// tests/Feature/Api/Mobile/LodgingSubVisibilityTest.php
namespace Tests\Feature\Api\Mobile;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\Events;
use App\Models\EventTypes;
use App\Models\Lodging;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class LodgingSubVisibilityTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Role::firstOrCreate(['name' => 'sub', 'guard_name' => 'web']);
    }

    private function createBandWithSubAndEvent(): array
    {
        $owner = User::factory()->create();
        $band  = Bands::factory()->create();
        $band->owners()->create(['user_id' => $owner->id]);

        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        $event   = Events::factory()->create([
            'eventable_id'   => $booking->id,
            'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id'  => EventTypes::factory()->create()->id,
            'date'           => now()->addDays(7)->format('Y-m-d'),
        ]);

        $sub = User::factory()->create();
        $band->bandSub()->attach($sub->id);           // band_subs pivot (User::bandSub inverse)
        $sub->ensureGlobalSubRole();                  // global team-0 sub role
        DB::table('event_subs')->insert([
            'event_id' => $event->id, 'user_id' => $sub->id, 'pending' => false,
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $subToken = $sub->createToken('test-device')->plainTextToken;

        return compact('band', 'booking', 'event', 'sub', 'subToken');
    }

    public function test_sub_sees_only_linked_lodgings(): void
    {
        ['band' => $band, 'event' => $event, 'subToken' => $subToken] = $this->createBandWithSubAndEvent();

        Lodging::factory()->create([
            'band_id' => $band->id, 'name' => 'Linked Hotel', 'event_id' => $event->id,
        ]);
        Lodging::factory()->create([
            'band_id' => $band->id, 'name' => 'Unlinked Hotel',
        ]);

        $response = $this->withToken($subToken)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/lodgings")
            ->assertOk()
            ->json();

        $names = array_column($response['lodgings'], 'name');
        $this->assertSame(['Linked Hotel'], $names);
        $this->assertFalse($response['can_write']);
    }

    public function test_sub_sees_booking_linked_lodging(): void
    {
        ['band' => $band, 'booking' => $booking, 'subToken' => $subToken] = $this->createBandWithSubAndEvent();

        Lodging::factory()->create([
            'band_id' => $band->id, 'name' => 'Booking Hotel', 'booking_id' => $booking->id,
        ]);

        $response = $this->withToken($subToken)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/lodgings")
            ->assertOk()
            ->json();

        $this->assertSame(['Booking Hotel'], array_column($response['lodgings'], 'name'));
    }

    public function test_sub_cannot_open_unlinked_lodging_detail(): void
    {
        ['band' => $band, 'subToken' => $subToken] = $this->createBandWithSubAndEvent();
        $unlinked = Lodging::factory()->create(['band_id' => $band->id]);

        $this->withToken($subToken)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/lodgings/{$unlinked->id}")
            ->assertStatus(404);
    }
}
```

Verify `$band->bandSub()` — the pivot relation lives on `User` (`User::bandSub`); the band-side relation may be named differently (grep `band_subs` in `app/Models/Bands.php`). Use whichever side exists, e.g. `DB::table('band_subs')->insert(['band_id' => $band->id, 'user_id' => $sub->id, ...])` if there is no convenient relation. Also confirm `ensureGlobalSubRole()` is a public instance method (`User.php:78-97`).

- [ ] **Step 2: Run to verify failure**

Run: `docker-compose exec app php artisan test --filter=LodgingSubVisibilityTest`
Expected: FAIL if scoping/carve-out has a gap; if it passes immediately, verify by breaking `scopeForSubs` temporarily.

- [ ] **Step 3: Fix any scoping gaps until green**

Likely gaps: `getEventIds()` return type mismatch (array vs Collection — wrap with `collect()`), the `canRead` carve-out helper name, and the middleware 403 happening before scoping (sub without assignment should get 403 from `EnsureUserInBand` — that's correct behavior).

- [ ] **Step 4: Add lodging summaries to event + booking detail payloads**

In `app/Services/Mobile/EventDataService.php` `formatForShow` (props array around line 399), add:
```php
            'lodgings'        => $event->lodgings()->withCount(['rooms', 'attachments'])->orderBy('check_in_at')->get()
                                       ->map(fn ($l) => app(LodgingService::class)->formatSummary($l))->values()->toArray(),
```
(Import `App\Services\Mobile\LodgingService`, or constructor-inject if `EventDataService` already uses DI.)

In `app/Services/Mobile/BookingService.php`, find the booking-detail formatter (the method feeding the mobile booking show endpoint) and add the same `lodgings` key using `$booking->lodgings()`.

Extend an existing event-detail test (e.g. in `tests/Feature/Api/Mobile/EventsTest.php`) with:
```php
    public function test_event_detail_includes_linked_lodgings(): void
    {
        ['band' => $band, 'event' => $event, 'token' => $token] = array_intersect_key(
            $this->createUserWithBandAndEvent(), array_flip(['band', 'event', 'token']));

        \App\Models\Lodging::factory()->create([
            'band_id' => $band->id, 'name' => 'Event Hotel', 'event_id' => $event->id,
        ]);

        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/events/{$event->id}")   // match the actual show route in routes/api.php
            ->assertOk()->json();

        $this->assertSame('Event Hotel', $response['event']['lodgings'][0]['name']);
    }
```
Adjust the show URL and response key to the actual event-detail route/shape (check `routes/api.php` and `EventDataService::formatForShow` envelope before writing).

- [ ] **Step 5: Run the full lodging filter + the touched events tests**

Run: `docker-compose exec app php artisan test --filter=Lodging && docker-compose exec app php artisan test --filter=EventsTest`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/Services tests
git commit -m "feat(lodging): sub visibility scoping + lodging summaries on event/booking detail"
```

---

### Task 5: Web routes + LodgingController (Inertia)

**Files:**
- Create: `routes/lodging.php`
- Create: `app/Http/Controllers/LodgingController.php`
- Create: `app/Http/Requests/StoreLodgingWebRequest.php`, `app/Http/Requests/UpdateLodgingWebRequest.php` (same rules as the Mobile pair — copy the classes, keep web names distinct)
- Modify: `routes/web.php` (~line 58-72, add `require __DIR__ . '/lodging.php';`)
- Test: `tests/Feature/LodgingWebTest.php`

**Interfaces:**
- Consumes: models + `LodgingService` from earlier tasks; `User::canRead('lodging', $bandId)` / `canWrite`.
- Produces route names used by Vue (Task 6): `lodgings.index` (no params), `bands.lodgings.create`, `bands.lodgings.store`, `lodgings.show`, `lodgings.edit`, `lodgings.update`, `lodgings.destroy`, `lodgings.attachments.upload`, `lodgings.attachments.show`, `lodgings.attachments.download`, `lodgings.attachments.destroy`. Inertia pages: `Lodging/Index`, `Lodging/Form`, `Lodging/Show`.

- [ ] **Step 1: Write the failing test**

```php
<?php
// tests/Feature/LodgingWebTest.php
namespace Tests\Feature;

use App\Models\Bands;
use App\Models\Lodging;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class LodgingWebTest extends TestCase
{
    use RefreshDatabase;

    public function test_index_renders_for_band_owner(): void
    {
        $user = User::factory()->create(['email_verified_at' => now()]);
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);
        Lodging::factory()->create(['band_id' => $band->id, 'name' => 'Visible Hotel']);

        $this->actingAs($user)
            ->get(route('lodgings.index'))
            ->assertOk()
            ->assertInertia(fn ($page) => $page->component('Lodging/Index'));
    }

    public function test_store_creates_and_redirects(): void
    {
        $user = User::factory()->create(['email_verified_at' => now()]);
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $this->actingAs($user)
            ->post(route('bands.lodgings.store', $band), [
                'name'         => 'Web Hotel',
                'check_in_at'  => now()->addDays(3)->format('Y-m-d H:i:s'),
                'check_out_at' => now()->addDays(4)->format('Y-m-d H:i:s'),
                'rooms'        => [['label' => 'King']],
            ])
            ->assertRedirect();

        $this->assertDatabaseHas('lodgings', ['name' => 'Web Hotel', 'band_id' => $band->id]);
        $this->assertDatabaseHas('lodging_rooms', ['label' => 'King']);
    }

    public function test_show_403s_for_stranger(): void
    {
        $stranger = User::factory()->create(['email_verified_at' => now()]);
        $lodging  = Lodging::factory()->create();

        $this->actingAs($stranger)
            ->get(route('lodgings.show', $lodging))
            ->assertStatus(403);
    }
}
```

If the codebase lacks `assertInertia` (check for `inertia-laravel` testing helpers in other web tests), fall back to `->assertOk()` + `->assertSee('Lodging')` style used by neighbouring tests — grep `tests/Feature` for `assertInertia` first and mirror.

- [ ] **Step 2: Run to verify failure**

Run: `docker-compose exec app php artisan test --filter=LodgingWebTest`
Expected: FAIL — route not defined

- [ ] **Step 3: Write routes**

```php
<?php
// routes/lodging.php
use App\Http\Controllers\LodgingController;
use Illuminate\Support\Facades\Route;

Route::middleware(['auth', 'verified'])->group(function () {
    // Cross-band index (nav entry, mirrors rehearsal-schedules.index)
    Route::get('/lodgings', [LodgingController::class, 'index'])->name('lodgings.index');

    Route::prefix('bands/{band}')->group(function () {
        Route::get('/lodgings/create', [LodgingController::class, 'create'])->name('bands.lodgings.create');
        Route::post('/lodgings', [LodgingController::class, 'store'])->name('bands.lodgings.store');
    });

    // Attachment routes BEFORE /lodgings/{lodging} so 'attachments' never
    // binds as a lodging id; belt-and-braces with whereNumber below.
    Route::post('/lodgings/{lodging}/attachments', [LodgingController::class, 'uploadAttachment'])->name('lodgings.attachments.upload');
    Route::get('/lodgings/attachments/{attachment}', [LodgingController::class, 'showAttachment'])->name('lodgings.attachments.show');
    Route::get('/lodgings/attachments/{attachment}/download', [LodgingController::class, 'downloadAttachment'])->name('lodgings.attachments.download');
    Route::delete('/lodgings/attachments/{attachment}', [LodgingController::class, 'destroyAttachment'])->name('lodgings.attachments.destroy');

    Route::get('/lodgings/{lodging}', [LodgingController::class, 'show'])->whereNumber('lodging')->name('lodgings.show');
    Route::get('/lodgings/{lodging}/edit', [LodgingController::class, 'edit'])->whereNumber('lodging')->name('lodgings.edit');
    Route::patch('/lodgings/{lodging}', [LodgingController::class, 'update'])->whereNumber('lodging')->name('lodgings.update');
    Route::delete('/lodgings/{lodging}', [LodgingController::class, 'destroy'])->whereNumber('lodging')->name('lodgings.destroy');
});
```

In `routes/web.php` (with the other requires, ~line 58-72) add:
```php
require __DIR__ . '/lodging.php';
```

- [ ] **Step 4: Write the controller**

```php
<?php
// app/Http/Controllers/LodgingController.php
namespace App\Http\Controllers;

use App\Http\Requests\StoreLodgingWebRequest;
use App\Http\Requests\UpdateLodgingWebRequest;
use App\Models\Bands;
use App\Models\Lodging;
use App\Models\LodgingAttachment;
use App\Services\Mobile\LodgingService;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class LodgingController extends Controller
{
    public function __construct(private readonly LodgingService $lodgingService)
    {
    }

    /** Cross-band index: every band the user can read lodging for. */
    public function index()
    {
        $user = auth()->user();
        $bands = $user->allBands()->map(function ($band) use ($user) {
            if (!$user->canRead('lodging', $band->id)) {
                return null;
            }
            $lodgings = Lodging::where('band_id', $band->id)
                ->withCount(['rooms', 'attachments'])
                ->orderBy('check_in_at')
                ->get()
                ->map(fn ($l) => $this->lodgingService->formatSummary($l))->values();
            return [
                'id'       => $band->id,
                'name'     => $band->name,
                'canWrite' => $user->canWrite('lodging', $band->id),
                'lodgings' => $lodgings,
            ];
        })->filter()->values();

        return inertia('Lodging/Index', ['bands' => $bands]);
    }

    public function create(Bands $band)
    {
        $this->authorizeWrite($band->id);

        return inertia('Lodging/Form', [
            'band'     => ['id' => $band->id, 'name' => $band->name],
            'lodging'  => null,
            'bookings' => $band->bookings()->orderByDesc('date')->get(['id', 'name', 'date']),
            'events'   => $this->bandEventOptions($band),
        ]);
    }

    public function store(StoreLodgingWebRequest $request, Bands $band)
    {
        $this->authorizeWrite($band->id);

        $data = $request->validated();
        $rooms = $data['rooms'] ?? [];
        unset($data['rooms']);

        $lodging = Lodging::create($data + ['band_id' => $band->id]);
        $this->lodgingService->syncRooms($lodging, $rooms);

        return redirect()->route('lodgings.show', $lodging)->with('success', 'Lodging created');
    }

    public function show(Lodging $lodging)
    {
        $this->authorizeRead($lodging->band_id);
        $user = auth()->user();

        return inertia('Lodging/Show', [
            'band'     => ['id' => $lodging->band_id, 'name' => $lodging->band->name],
            'lodging'  => $this->formatForWeb($lodging),
            'canWrite' => $user->canWrite('lodging', $lodging->band_id),
        ]);
    }

    public function edit(Lodging $lodging)
    {
        $this->authorizeWrite($lodging->band_id);
        $band = $lodging->band;

        return inertia('Lodging/Form', [
            'band'     => ['id' => $band->id, 'name' => $band->name],
            'lodging'  => $this->formatForWeb($lodging),
            'bookings' => $band->bookings()->orderByDesc('date')->get(['id', 'name', 'date']),
            'events'   => $this->bandEventOptions($band),
        ]);
    }

    public function update(UpdateLodgingWebRequest $request, Lodging $lodging)
    {
        $this->authorizeWrite($lodging->band_id);

        $data = $request->validated();
        $rooms = $data['rooms'] ?? null;
        unset($data['rooms']);

        if ($data !== []) {
            $lodging->update($data);
        }
        if ($rooms !== null) {
            $this->lodgingService->syncRooms($lodging, $rooms);
            $lodging->touch();
        }

        return redirect()->route('lodgings.show', $lodging)->with('success', 'Lodging updated');
    }

    public function destroy(Lodging $lodging)
    {
        $this->authorizeWrite($lodging->band_id);
        $lodging->delete();

        return redirect()->route('lodgings.index')->with('success', 'Lodging deleted');
    }

    public function uploadAttachment(Lodging $lodging)
    {
        $this->authorizeWrite($lodging->band_id);
        request()->validate(['files.*' => 'required|file|max:10240']);

        $band = $lodging->band;
        $disk = config('filesystems.default');
        foreach (request()->file('files', []) as $file) {
            $extension = $file->getClientOriginalExtension();
            $filename  = Str::uuid() . ($extension ? '.' . $extension : '');
            $path      = $file->storeAs($band->site_name . '/lodging_uploads', $filename, $disk);
            LodgingAttachment::create([
                'lodging_id'      => $lodging->id,
                'filename'        => $file->getClientOriginalName(),
                'stored_filename' => $path,
                'mime_type'       => $file->getMimeType(),
                'file_size'       => $file->getSize(),
                'disk'            => $disk,
            ]);
        }
        $lodging->touch();

        return response()->json(['attachments' => $lodging->attachments()->get()
            ->map(fn ($a) => $this->formatWebAttachment($a))->values()]);
    }

    public function showAttachment(LodgingAttachment $attachment)
    {
        $this->authorizeRead($attachment->lodging->band_id);
        try {
            $file = Storage::disk($attachment->disk)->get($attachment->stored_filename);
            return response($file)
                ->header('Content-Type', $attachment->mime_type)
                ->header('Content-Disposition', 'inline; filename="' . $attachment->filename . '"')
                ->header('Cache-Control', 'private, max-age=3600');
        } catch (\Exception $e) {
            abort(404, 'File not found');
        }
    }

    public function downloadAttachment(LodgingAttachment $attachment)
    {
        $this->authorizeRead($attachment->lodging->band_id);
        try {
            return Storage::disk($attachment->disk)->download($attachment->stored_filename, $attachment->filename);
        } catch (\Exception $e) {
            abort(404, 'File not found');
        }
    }

    public function destroyAttachment(LodgingAttachment $attachment)
    {
        $this->authorizeWrite($attachment->lodging->band_id);
        $lodging = $attachment->lodging;
        $attachment->delete();
        $lodging->touch();

        return response()->json(['message' => 'Attachment deleted.']);
    }

    // ── helpers ──────────────────────────────────────────────────────────

    private function authorizeRead(int $bandId): void
    {
        abort_unless(auth()->user()?->canRead('lodging', $bandId), 403, 'Unauthorized');
    }

    private function authorizeWrite(int $bandId): void
    {
        abort_unless(auth()->user()?->canWrite('lodging', $bandId), 403, 'Unauthorized');
    }

    private function formatForWeb(Lodging $lodging): array
    {
        $detail = $this->lodgingService->formatDetail($lodging);
        // Web serves attachments through session-auth web routes, not sanctum.
        $detail['attachments'] = $lodging->attachments->map(fn ($a) => $this->formatWebAttachment($a))->values()->toArray();
        return $detail;
    }

    private function formatWebAttachment(LodgingAttachment $a): array
    {
        return [
            'id'           => $a->id,
            'filename'     => $a->filename,
            'mime_type'    => $a->mime_type,
            'file_size'    => $a->file_size,
            'url'          => route('lodgings.attachments.show', $a),
            'download_url' => route('lodgings.attachments.download', $a),
        ];
    }

    /** Upcoming + recent events for the link picker. */
    private function bandEventOptions(Bands $band): array
    {
        return \App\Models\Events::query()
            ->whereHasMorph('eventable', [\App\Models\Bookings::class], fn ($q) => $q->where('band_id', $band->id))
            ->where('date', '>=', now()->subMonths(3)->toDateString())
            ->orderBy('date')
            ->get(['id', 'title', 'date'])
            ->map(fn ($e) => ['id' => $e->id, 'title' => $e->title, 'date' => $e->date])
            ->toArray();
    }
}
```

Verify: `Bands::bookings()` relation exists (grep `function bookings` in `app/Models/Bands.php`); `whereHasMorph` needs the morph map string used in `eventable_type` (`'App\Models\Bookings'`) — check how other code queries events-by-band and copy it (e.g. from `UserEventsService`). Bookings `name`/`date` column names — grep the `bookings` table columns in `database/schema/mysql-schema.sql` and adjust (`date` may be `start_date` or similar).

- [ ] **Step 5: Web FormRequests** — copy `Mobile/StoreLodgingRequest` and `Mobile/UpdateLodgingRequest` bodies into `app/Http/Requests/StoreLodgingWebRequest.php` / `UpdateLodgingWebRequest.php` (namespace `App\Http\Requests`; identical rules; `authorize(): bool { return true; }` since the controller checks canWrite).

- [ ] **Step 6: Run tests**

Run: `docker-compose exec app php artisan test --filter=LodgingWebTest`
Expected: PASS (3 tests)

- [ ] **Step 7: Commit**

```bash
git add routes app/Http tests/Feature/LodgingWebTest.php
git commit -m "feat(lodging): web routes + Inertia controller"
```

---

### Task 6: Vue pages — Index, Form, Show + nav link

**Files:**
- Create: `resources/js/Pages/Lodging/Index.vue`, `resources/js/Pages/Lodging/Form.vue`, `resources/js/Pages/Lodging/Show.vue`
- Modify: `resources/js/config/navigation.js` (scheduling group)
- Test: `resources/js/tests/components/lodgingform.test.js`

**Interfaces:**
- Consumes: route names + props from Task 5. Existing components: `BreezeAuthenticatedLayout` (`@/Layouts/Authenticated.vue`), `Container`, `Button`, `Input`, `InputError`, `Label`, `TextArea` (`@/Components/`), `LocationAutocomplete` (`@/Components/LocationAutocomplete.vue` — v-model gets name; full Places payload incl. `result.geometry.location.lat/lng` + `result.formatted_address` on `@location-selected`).
- Produces: pages rendered by `inertia('Lodging/Index'|'Lodging/Form'|'Lodging/Show')`.

- [ ] **Step 1: Nav link** — in `resources/js/config/navigation.js`, scheduling group after Rehearsals:

```js
      {
        label: 'Lodging',
        routeName: 'lodgings.index',
        activeMatch: (route) => route.includes('lodging')
      }
```
No `permission` key — `filterNavItemsByPermission` shows unguarded items to everyone; per-band visibility is enforced server-side in the index.

- [ ] **Step 2: Index page** — mirror `Pages/Rehearsals/Index.vue` structure (layout wrapper `:1-8`, per-band sections, card grid `:40-47`, create CTA `:24-29`). Cards show name, `check_in_at`–`check_out_at` (format with luxon `DateTime.fromSQL(l.check_in_at).toFormat('EEE, MMM d h:mm a')`), room count, and a linked-booking/event chip when `booking_id`/`event_id` set. Each card is a `<Link :href="route('lodgings.show', l.id)">`. Create button per band gated on `b.canWrite` → `route('bands.lodgings.create', { band: b.id })`. Card classes: `bg-white dark:bg-slate-800 rounded-lg shadow-md p-4`.

- [ ] **Step 3: Form page (create + edit)** — mirror `RehearsalForm.vue:378-411` useForm pattern:

```js
const props = defineProps({ band: Object, lodging: Object, bookings: Array, events: Array });

const form = useForm({
    name:         props.lodging?.name || '',
    address:      props.lodging?.address || '',
    latitude:     props.lodging?.latitude ?? null,
    longitude:    props.lodging?.longitude ?? null,
    check_in_at:  props.lodging?.check_in_at || '',
    check_out_at: props.lodging?.check_out_at || '',
    notes:        props.lodging?.notes || '',
    booking_id:   props.lodging?.booking?.id ?? null,
    event_id:     props.lodging?.event?.id ?? null,
    rooms:        props.lodging?.rooms?.map(r => ({ ...r })) || [],
});

const submit = () => {
    if (props.lodging) {
        form.patch(route('lodgings.update', props.lodging.id));
    } else {
        form.post(route('bands.lodgings.store', { band: props.band.id }));
    }
};

const addRoom = () => form.rooms.push({ label: '', confirmation_number: '', notes: '' });
const removeRoom = (i) => form.rooms.splice(i, 1);
```

Fields:
- `name`: `Input` + `Label` + `InputError`.
- Address: `LocationAutocomplete` with `v-model="form.address"` and
```js
const onLocationSelected = (payload) => {
    const r = payload.result ?? payload;
    form.address   = r.formatted_address ?? form.address;
    form.latitude  = r.geometry?.location?.lat ?? null;
    form.longitude = r.geometry?.location?.lng ?? null;
};
```
(Verify payload shape against the `/api/getLocationDetails` response before relying on `result.geometry` — see `LocationAutocomplete.vue:172-175`.)
- Check-in / check-out: paired `type="date"` + `type="time"` Inputs per field (Rehearsals style, `RehearsalForm.vue:79-115`), composed into `Y-m-d H:i:s` on submit:
```js
const composeDateTime = (d, t) => (d && t) ? `${d} ${t}:00` : '';
```
Hold `check_in_date/check_in_time/check_out_date/check_out_time` as local refs (initialized by splitting `props.lodging?.check_in_at`), compose in `submit()` before posting.
- `notes`: `TextArea`.
- Room rows: v-for over `form.rooms` with `Input`s for label + confirmation_number + notes and an X-remove button per row (idiom: `NotesSection.vue:94-113`), plus an "Add room" `Button` → `addRoom()`.
- Booking/event pickers: two plain `<select>` elements (styled `w-full p-2 border rounded dark:bg-slate-700 dark:text-gray-50`) over `props.bookings` / `props.events`, each with a "None" option mapping to `null`.
- Attachments (edit mode only, `v-if="props.lodging"`): hidden multi-file input + button (`NotesSection.vue:69-86`), axios POST FormData `files[]` to `route('lodgings.attachments.upload', props.lodging.id)` (`NotesSection.vue:442-465` pattern), list existing with delete via `route('lodgings.attachments.destroy', a.id)`. On create, show a hint "Save first to add images" instead of the uploader (simplest; skip the deferred-upload machinery).
- Delete button (edit mode, confirm dialog) → `form.delete(route('lodgings.destroy', props.lodging.id))`.

- [ ] **Step 4: Show page** — PrimeVue `Card` sections like `Events/Show.vue`:
  - Header card: name, formatted check-in/check-out (include weekday), notes, Edit button when `canWrite` → `route('lodgings.edit', lodging.id)`.
  - Address row: text + a "Directions" anchor `:href="'https://maps.google.com/?q=' + (lodging.latitude && lodging.longitude ? lodging.latitude + ',' + lodging.longitude : encodeURIComponent(lodging.address))"` `target="_blank"`.
  - Rooms card: table-ish rows label / confirmation # / notes.
  - Linked booking/event card with `Link`s to their pages (booking: `route('Booking Events', ...)`-style — grep how `BookingDetails.vue` links to a booking page and copy; event: check how event show links are built in `Components/Event/Card`).
  - Images card: thumbnail grid of image-mime attachments (`Events/Show.vue:142-166` pattern) using `attachment.url`, click → open `attachment.url` in new tab (skip lightbox for v1); non-image files listed with `download_url` links.

- [ ] **Step 5: Component test**

```js
// resources/js/tests/components/lodgingform.test.js
import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';

global.route = vi.fn((name) => `/mock-route/${name}`);

vi.mock('@inertiajs/vue3', async () => {
  const { reactive } = await import('vue');
  return {
    useForm: (initial) => {
      const form = reactive({ ...initial, errors: {}, processing: false });
      form.put = vi.fn(); form.post = vi.fn(); form.patch = vi.fn();
      form.delete = vi.fn(); form.reset = vi.fn(); form.clearErrors = vi.fn();
      return form;
    },
    Link: { template: '<a><slot /></a>' },
  };
});

import LodgingForm from '@/Pages/Lodging/Form.vue';

const band = { id: 1, name: 'Test Band' };

describe('Lodging Form', () => {
  it('renders create mode with an empty rooms list and an add-room button', () => {
    const wrapper = mount(LodgingForm, {
      props: { band, lodging: null, bookings: [], events: [] },
    });
    expect(wrapper.text()).toContain('Add room');
    expect(wrapper.text()).not.toContain('Confirmation');
  });

  it('adds a room row when Add room is clicked', async () => {
    const wrapper = mount(LodgingForm, {
      props: { band, lodging: null, bookings: [], events: [] },
    });
    await wrapper.find('[data-testid="add-room"]').trigger('click');
    expect(wrapper.findAll('[data-testid="room-row"]').length).toBe(1);
  });

  it('prefills fields in edit mode', () => {
    const wrapper = mount(LodgingForm, {
      props: {
        band,
        lodging: {
          id: 9, name: 'Hampton Inn', address: '123 Main St',
          check_in_at: '2030-01-10 15:00:00', check_out_at: '2030-01-12 11:00:00',
          notes: '', booking: null, event: null,
          rooms: [{ id: 1, label: 'King', confirmation_number: 'ABC', notes: '' }],
          attachments: [],
        },
        bookings: [], events: [],
      },
    });
    expect(wrapper.find('input#name').element.value).toBe('Hampton Inn');
    expect(wrapper.findAll('[data-testid="room-row"]').length).toBe(1);
  });
});
```
Add `data-testid="add-room"` / `data-testid="room-row"` attributes in the component. If `LocationAutocomplete` makes network calls on mount, stub it: `global: { stubs: { LocationAutocomplete: { template: '<input />' } } }`.

- [ ] **Step 6: Run tests**

Run: `docker-compose exec app npx vitest run resources/js/tests/components/lodgingform.test.js`
Expected: PASS (3 tests)

- [ ] **Step 7: Commit**

```bash
git add resources/js
git commit -m "feat(lodging): web Index/Form/Show pages + nav link"
```

---

### Task 7: Booking/Event page cards + legacy lodging UI removal

**Files:**
- Modify: `resources/js/Pages/Events/Show.vue:249-282` (replace old lodging card), `:542` (`hasLodging`)
- Modify: `resources/js/Pages/Bookings/Components/BookingDetails.vue` (add lodging card)
- Modify: `resources/js/Pages/Bookings/Components/EventEditor.vue:197-206, 273, 403` (remove LodgingSection)
- Modify: `resources/js/Pages/Bookings/Components/EventDetails.vue:189-222, 448, 497-499` (remove read-only lodging mirror)
- Modify: `resources/js/Components/Event/Card/Body.vue:674-679` (remove `Lodging Provided` lookup)
- Delete: `resources/js/Pages/Bookings/Components/EventEditor/LodgingSection.vue`
- Modify: `app/Http/Controllers/BookingsController.php:162-167` (stop seeding lodging defaults), `app/Console/Commands/DevSetupCommand.php:815`
- Modify: the controller methods that render `Events/Show` and `Bookings/Show` — add `lodgings` props
- Test: extend `tests/Feature/LodgingWebTest.php`

**Interfaces:**
- Consumes: `Events::lodgings()` / `Bookings::lodgings()`, `LodgingService::formatSummary`.
- Produces: `lodgings` prop on Events/Show and the booking props consumed by BookingDetails; legacy `additional_data.lodging` UI fully gone from web (data untouched; `AdditionalData.vue:85` exclusion stays; `EventDataService` mobile parse stays).

- [ ] **Step 1: Backend props.** In the controller method rendering `Events/Show` (grep `Events/Show` in `app/Http/Controllers`), add to the Inertia props:
```php
            'lodgings' => $event->lodgings()->withCount(['rooms', 'attachments'])->orderBy('check_in_at')->get()
                                ->map(fn ($l) => app(\App\Services\Mobile\LodgingService::class)->formatSummary($l))->values(),
```
Same for the booking show path (grep `Bookings/Show`): `'lodgings' => $booking->lodgings()...` — trace how props flow into `BookingDetails.vue` (it may read from a `booking` object; attach `lodgings` wherever sibling data like contacts lives).

- [ ] **Step 2: New Events/Show card.** Replace the old lodging `Card` (`Events/Show.vue:249-282`) with:
```vue
      <Card v-if="lodgings.length" class="mb-4">
        <template #title>Lodging</template>
        <template #content>
          <div class="space-y-2 text-sm">
            <a
              v-for="l in lodgings"
              :key="l.id"
              :href="route('lodgings.show', l.id)"
              class="flex items-start justify-between gap-2 hover:underline"
            >
              <span>{{ l.name }}</span>
              <span class="text-gray-500 dark:text-gray-400">{{ formatStayRange(l) }}</span>
            </a>
          </div>
        </template>
      </Card>
```
with `const props = defineProps({ ..., lodgings: { type: Array, default: () => [] } })` and a `formatStayRange` helper using luxon (`DateTime.fromSQL`). Remove the `hasLodging` computed at `:542`.

- [ ] **Step 3: BookingDetails card.** Add a plain-div card (`bg-white dark:bg-slate-800 rounded-lg shadow-md p-4`) listing linked lodgings the same way, placed near the Schedule & Venue card. Register the new prop in `Bookings/Show.vue`'s `useBandRealtime` refresh list (`Show.vue:62-72`) with model `'lodging'`.

- [ ] **Step 4: Remove legacy editor UI.**
  - `EventEditor.vue`: delete the SectionCard block `:197-206`, the import at `:273`, the `lodging: true` key at `:403`.
  - `EventDetails.vue`: delete the read-only mirror `:189-222`, `hasLodging` computed `:497-499`, `openSections.lodging` `:448`.
  - `Body.vue:674-679`: delete the `Lodging Provided` lookup and whatever renders from it.
  - Delete `LodgingSection.vue`.
  - `BookingsController.php:162-167`: delete the `'lodging' => [...]` seed block. `DevSetupCommand.php:815`: same.
  - Leave `AdditionalData.vue:85` exclusion, `UpdateBookingEventRequest`/`Mobile/UpdateEventRequest` validation, and `EventDataService` parse/write untouched (old data + old app versions).

- [ ] **Step 5: Verify nothing else referenced the removed pieces**

Run: `grep -rn "LodgingSection" resources/js/ && grep -rn "openSections.lodging" resources/js/`
Expected: no hits. Then run the full Vue suite: `docker-compose exec app npx vitest run` — fix any broken tests that asserted on the old lodging fields (e.g. `eventcardbody` tests).

- [ ] **Step 6: Feature test for props**

Add to `tests/Feature/LodgingWebTest.php`:
```php
    public function test_event_show_receives_lodgings_prop(): void
    {
        $user = User::factory()->create(['email_verified_at' => now()]);
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);
        $booking = \App\Models\Bookings::factory()->create(['band_id' => $band->id]);
        $event = \App\Models\Events::factory()->create([
            'eventable_id' => $booking->id, 'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id' => \App\Models\EventTypes::factory()->create()->id,
            'date' => now()->addDays(5)->format('Y-m-d'),
        ]);
        Lodging::factory()->create(['band_id' => $band->id, 'event_id' => $event->id, 'name' => 'Prop Hotel']);

        // Use the actual web route for an event show page (grep routes/events.php).
        $this->actingAs($user)
            ->get(route('events.show', $event))
            ->assertOk()
            ->assertSee('Prop Hotel');
    }
```
Adjust route name to the real one in `routes/events.php`.

- [ ] **Step 7: Run everything and commit**

Run: `docker-compose exec app php artisan test --filter=Lodging` then `docker-compose exec app php artisan test --parallel` and `docker-compose exec app npx vitest run`
Expected: all PASS (re-run known-flaky files sequentially if CalendarFeedTest/band_roles flake).

```bash
git add resources/js app tests
git commit -m "feat(lodging): booking/event lodging cards, remove legacy lodging editor UI"
```

---

### Task 8: PR

- [ ] **Step 1:** Push branch and open PR with base `staging`:
```bash
git push -u origin feat/lodging-domain
gh pr create --base staging --title "feat: first-class lodging domain (rooms, attachments, mobile API, web UI)" --body "$(cat <<'EOF'
## Summary
- New band-scoped lodging domain: lodgings + lodging_rooms + lodging_attachments
- Mobile API: CRUD with nested room sync, attachment upload/delete, sanctum-authenticated image serving
- New read:lodging/write:lodging abilities (token + Spatie permissions); subs read stays linked to their gigs
- Web: Lodging index/form/show pages, nav link, booking/event lodging cards
- Removed legacy additional_data.lodging editor UI (data preserved; mobile wire contract unchanged)

## Test plan
- [ ] php artisan test --parallel green
- [ ] npx vitest run green
- [ ] Manual: create lodging with rooms + image on web, view on booking page

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
- [ ] **Step 2:** Wait for the Copilot auto-review and address its comments before calling the PR done.
- [ ] **Step 3:** Remember: merging to staging auto-deploys. Backend must merge and deploy **before** the mobile app PR ships (token abilities + endpoints).
