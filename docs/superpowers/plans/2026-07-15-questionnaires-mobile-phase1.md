# Questionnaires Mobile — Phase 1 (Templates CRUD + Builder) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship questionnaire template CRUD (list, create-with-preset, full field builder, preview, archive/restore/delete) on mobile — a new `/api/mobile` surface in TTS plus a new `lib/features/questionnaires/` slice in tts_bandmate.

**Architecture:** Backend adds a thin `Api\Mobile\QuestionnairesController` over the existing questionnaire services; the web controller's private field-upsert/preset-clone helpers move into a shared `QuestionnaireTemplateService` so both controllers call one implementation. Mobile follows the Personnel slice pattern: hand-written models → Dio repository → Riverpod `AsyncNotifier.family` providers → Cupertino screens, with a builder that mirrors the web bulk-save contract (client temp-ids, server-rewritten visibility references).

**Tech Stack:** Laravel 10 (Sanctum, Spatie permissions), Flutter/Dart (Riverpod v2, GoRouter, Dio, Cupertino).

**Spec:** `docs/superpowers/specs/2026-07-15-questionnaires-mobile-design.md`

## Global Constraints

- TTS repo: never run `php`/`artisan`/`composer` on the host — always `docker-compose exec app …`.
- TTS PRs target `staging`; mobile PRs target `main`.
- Backend branch: `feat/mobile-questionnaires-api` (off `staging`). Mobile branch: `feat/questionnaires-mobile` (already exists).
- Mobile: Cupertino widgets only; hand-written `fromJson` (no codegen); use `context.secondaryText` (from `package:tts_bandmate/core/theme/context_colors.dart`), never raw `CupertinoColors.secondaryLabel` in a `color:`.
- Mobile test naming: `test('test_<behavior>', …)`, `addTearDown(container.dispose)`, force initial build with `await container.read(provider(…).future)` before mutations.
- Token abilities are baked into issued tokens — after Task 1 lands, on-device testing requires re-login.
- Wire contract (frozen, matches web): PUT fields payload uses `client_id` (`id-<dbId>` for existing, `tmp-<n>` for new); `visibility_rule.depends_on` carries a `client_id` on write, a numeric DB id on read; positions are `(index+1)*10`.
- Commit after every green task; commit messages end with the standard Claude trailers.

---

## Backend tasks (repo `/home/eddie/github/TTS`)

### Task 1: Branch + token ability for questionnaires

**Files:**
- Modify: `/home/eddie/github/TTS/app/Services/Mobile/TokenService.php` (the `RESOURCES` const, ~line 10)
- Test: `/home/eddie/github/TTS/tests/Unit/Mobile/TokenServiceQuestionnairesTest.php` (create; if a TokenService test already exists under `tests/`, add the test there instead)

**Interfaces:**
- Consumes: `TokenService::buildAbilities(User $user): array` (existing).
- Produces: tokens for questionnaire-permitted users now include `read:questionnaires` / `write:questionnaires` — Tasks 3–4's `mobile.band:*:questionnaires` middleware depends on this.

- [ ] **Step 1: Create the branch**

```bash
cd /home/eddie/github/TTS && git checkout staging && git pull && git checkout -b feat/mobile-questionnaires-api
```

- [ ] **Step 2: Write the failing test**

```php
<?php

namespace Tests\Unit\Mobile;

use App\Models\BandOwners;
use App\Models\Bands;
use App\Models\User;
use App\Services\Mobile\TokenService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TokenServiceQuestionnairesTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_token_includes_questionnaire_abilities(): void
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        BandOwners::create(['user_id' => $user->id, 'band_id' => $band->id]);

        $abilities = app(TokenService::class)->buildAbilities($user->fresh());

        $this->assertContains('read:questionnaires', $abilities);
        $this->assertContains('write:questionnaires', $abilities);
    }
}
```

(If `BandOwners::create` needs different columns, copy the exact owner-attach lines from `tests/Feature/Api/Mobile/RosterMobileTest.php` `setUp()`.)

- [ ] **Step 3: Run test to verify it fails**

Run: `docker-compose exec app php artisan test --filter=TokenServiceQuestionnairesTest`
Expected: FAIL — `read:questionnaires` not in array.

- [ ] **Step 4: Implement**

In `TokenService.php` change:

```php
private const RESOURCES = ['bookings', 'events', 'media', 'rehearsals', 'charts', 'songs'];
```

to:

```php
private const RESOURCES = ['bookings', 'events', 'media', 'rehearsals', 'charts', 'songs', 'questionnaires'];
```

- [ ] **Step 5: Run test to verify it passes**

Run: `docker-compose exec app php artisan test --filter=TokenServiceQuestionnairesTest`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(mobile): add questionnaires to mobile token abilities"
```

### Task 2: Extract QuestionnaireTemplateService (shared with web controller)

**Files:**
- Create: `/home/eddie/github/TTS/app/Services/QuestionnaireTemplateService.php`
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/QuestionnairesController.php` (`store()` ~67–88, `cloneFieldsFromPreset()` ~90–107, `update()` ~198–213, `validateBulkSavePayload()` ~266–315, `upsertFields()` ~322–377)
- Test: existing web questionnaire feature tests (find with `docker-compose exec app php artisan test --filter=Questionnaire` — no new tests; this is a pure refactor guarded by the existing suite)

**Interfaces:**
- Consumes: `QuestionnaireFieldTypeRegistry`, `QuestionnaireMappingRegistry`, `FieldSettingsValidator`, `QuestionnairePresetRegistry` (all existing, constructor-injected).
- Produces (Tasks 3–4 call these):
  - `applyPreset(Questionnaires $questionnaire, string $presetKey): void` — no-op when preset unknown
  - `validateFieldsPayload(array $fields): void` — throws `ValidationException` keyed `fields.{i}.…`
  - `upsertFields(Questionnaires $questionnaire, array $fields): void` — must run inside a caller-owned `DB::transaction`

- [ ] **Step 1: Run the existing questionnaire suite to get a green baseline**

Run: `docker-compose exec app php artisan test --filter=Questionnaire`
Expected: PASS (record the test count).

- [ ] **Step 2: Create the service by MOVING the three private methods**

Create `app/Services/QuestionnaireTemplateService.php` with this skeleton, then cut-paste the method bodies **verbatim** from `QuestionnairesController` (`cloneFieldsFromPreset` → `applyPreset`, `validateBulkSavePayload` → `validateFieldsPayload`, `upsertFields` → `upsertFields`). Keep every line of the bodies identical; only the visibility changes to `public` and `$this->settingsValidator` etc. now resolve against this class's constructor properties.

```php
<?php

namespace App\Services;

use App\Models\Questionnaires;

class QuestionnaireTemplateService
{
    public function __construct(
        private QuestionnaireFieldTypeRegistry $typeRegistry,
        private QuestionnaireMappingRegistry $mappingRegistry,
        private FieldSettingsValidator $settingsValidator,
        private QuestionnairePresetRegistry $presetRegistry,
    ) {
    }

    /** Clone a preset's field definitions onto a freshly created questionnaire. */
    public function applyPreset(Questionnaires $questionnaire, string $presetKey): void
    {
        // moved body of QuestionnairesController::cloneFieldsFromPreset()
        // (guard first: if (! $this->presetRegistry->exists($presetKey)) return;)
    }

    /** @throws \Illuminate\Validation\ValidationException */
    public function validateFieldsPayload(array $fields): void
    {
        // moved body of QuestionnairesController::validateBulkSavePayload()
    }

    /** Diff-based upsert; caller wraps in DB::transaction. */
    public function upsertFields(Questionnaires $questionnaire, array $fields): void
    {
        // moved body of QuestionnairesController::upsertFields()
    }
}
```

If the moved bodies reference controller-only helpers, move those too (keep them private on the service). Match the original signatures' extra parameters exactly — if `upsertFields` took `(Questionnaires $questionnaire, array $fields)` already, nothing changes; if it took validated request data, keep that shape.

- [ ] **Step 3: Refactor the web controller to delegate**

In `QuestionnairesController`: add `QuestionnaireTemplateService $templateService` to the constructor; replace the bodies of the three private methods' call sites — `store()` calls `$this->templateService->applyPreset($questionnaire, $presetKey)`, `update()` calls `$this->templateService->validateFieldsPayload(...)` and `$this->templateService->upsertFields(...)` — and delete the three private methods (and any helpers that moved).

- [ ] **Step 4: Run the suite to verify the refactor is behavior-preserving**

Run: `docker-compose exec app php artisan test --filter=Questionnaire`
Expected: PASS with the same test count as Step 1.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: extract QuestionnaireTemplateService from web controller"
```

### Task 3: Mobile read endpoints (index, catalog, show)

**Files:**
- Create: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/QuestionnairesController.php`
- Modify: `/home/eddie/github/TTS/routes/api.php` (inside the mobile `auth:sanctum` group, after the setlist-prompt-templates block ~line 401)
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/QuestionnaireMobileTest.php` (create)

**Interfaces:**
- Consumes: `QuestionnaireTemplateService` (Task 2), registries' `catalog()` methods, `Bands::questionnaires()` relation, `mobile.band` middleware (`EnsureUserInBand`).
- Produces (the mobile app's read contract):
  - `GET /api/mobile/bands/{band}/questionnaires` → 200 `{"questionnaires": [{id, name, description, archived_at, instances_count, updated_at}]}`
  - `GET /api/mobile/bands/{band}/questionnaires/catalog` → 200 `{"field_types": [...], "mapping_targets": [...], "presets": [...]}` (registry `catalog()` output verbatim)
  - `GET /api/mobile/bands/{band}/questionnaires/{questionnaire}` → 200 `{"questionnaire": {id, name, description, archived_at, instances_count, updated_at, fields: [{id, type, label, help_text, required, position, settings, visibility_rule, mapping_target}]}}` — fields ordered by position; cross-band → 404

- [ ] **Step 1: Write the failing tests**

Create `tests/Feature/Api/Mobile/QuestionnaireMobileTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\BandMembers;
use App\Models\BandOwners;
use App\Models\Bands;
use App\Models\Questionnaires;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class QuestionnaireMobileTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;
    private User $member;
    private Bands $band;
    private string $ownerToken;
    private string $memberToken;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = User::factory()->create();
        $this->member = User::factory()->create();
        $this->band = Bands::factory()->create();
        BandOwners::create(['user_id' => $this->owner->id, 'band_id' => $this->band->id]);
        BandMembers::create(['user_id' => $this->member->id, 'band_id' => $this->band->id]);

        // Member needs the Spatie permission the middleware re-checks per band.
        setPermissionsTeamId($this->band->id);
        $this->member->assignRole('band-member');
        // Fallback if the role isn't migrated in tests:
        // $this->member->givePermissionTo('read:questionnaires');

        $this->ownerToken = $this->owner->createToken(
            'test-device', ['mobile', 'read:questionnaires', 'write:questionnaires']
        )->plainTextToken;
        $this->memberToken = $this->member->createToken(
            'test-device', ['mobile', 'read:questionnaires']
        )->plainTextToken;
    }

    private function asOwner(): array
    {
        return [
            'Authorization' => "Bearer {$this->ownerToken}",
            'X-Band-ID' => $this->band->id,
            'Accept' => 'application/json',
        ];
    }

    private function asMember(): array
    {
        return [
            'Authorization' => "Bearer {$this->memberToken}",
            'X-Band-ID' => $this->band->id,
            'Accept' => 'application/json',
        ];
    }

    private function makeQuestionnaire(array $attrs = []): Questionnaires
    {
        $q = new Questionnaires();
        $q->band_id = $this->band->id;
        $q->name = $attrs['name'] ?? 'Wedding Intake';
        $q->description = $attrs['description'] ?? null;
        $q->archived_at = $attrs['archived_at'] ?? null;
        $q->save();

        return $q;
    }

    public function test_owner_can_list_questionnaires(): void
    {
        $this->makeQuestionnaire(['name' => 'Wedding Intake']);

        $this->withHeaders($this->asOwner())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaires")
            ->assertOk()
            ->assertJsonCount(1, 'questionnaires')
            ->assertJsonPath('questionnaires.0.name', 'Wedding Intake')
            ->assertJsonPath('questionnaires.0.instances_count', 0);
    }

    public function test_member_can_list_questionnaires(): void
    {
        $this->makeQuestionnaire();

        $this->withHeaders($this->asMember())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaires")
            ->assertOk()
            ->assertJsonCount(1, 'questionnaires');
    }

    public function test_catalog_returns_registries(): void
    {
        $response = $this->withHeaders($this->asOwner())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaires/catalog")
            ->assertOk()
            ->assertJsonCount(13, 'field_types')
            ->assertJsonCount(7, 'mapping_targets');

        $presetKeys = array_column($response->json('presets'), 'key');
        $this->assertContains('wedding', $presetKeys);
    }

    public function test_show_returns_fields_in_position_order(): void
    {
        $q = $this->makeQuestionnaire();
        $q->fields()->create(['type' => 'short_text', 'label' => 'Second', 'position' => 20, 'required' => false]);
        $q->fields()->create(['type' => 'short_text', 'label' => 'First', 'position' => 10, 'required' => true]);

        $this->withHeaders($this->asOwner())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$q->id}")
            ->assertOk()
            ->assertJsonPath('questionnaire.fields.0.label', 'First')
            ->assertJsonPath('questionnaire.fields.0.required', true)
            ->assertJsonPath('questionnaire.fields.1.label', 'Second');
    }

    public function test_show_cross_band_questionnaire_is_404(): void
    {
        $otherBand = Bands::factory()->create();
        $foreign = new Questionnaires();
        $foreign->band_id = $otherBand->id;
        $foreign->name = 'Foreign';
        $foreign->save();

        $this->withHeaders($this->asOwner())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$foreign->id}")
            ->assertStatus(404);
    }

    public function test_token_without_ability_is_403(): void
    {
        $bareToken = $this->owner->createToken('bare-device', ['mobile'])->plainTextToken;

        $this->withHeaders([
            'Authorization' => "Bearer {$bareToken}",
            'X-Band-ID' => $this->band->id,
            'Accept' => 'application/json',
        ])->getJson("/api/mobile/bands/{$this->band->id}/questionnaires")
            ->assertStatus(403);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker-compose exec app php artisan test --filter=QuestionnaireMobileTest`
Expected: FAIL — 404s (routes don't exist).

- [ ] **Step 3: Add routes**

In `routes/api.php`, after the setlist-prompt-templates write group (~line 401), inside the mobile `auth:sanctum` group:

```php
// Questionnaires (band-scoped templates)
Route::middleware('mobile.band:read:questionnaires')->group(function () {
    Route::get('/bands/{band}/questionnaires', [App\Http\Controllers\Api\Mobile\QuestionnairesController::class, 'index'])->name('mobile.questionnaires.index');
    // Literal segment before {questionnaire} to avoid ambiguity
    Route::get('/bands/{band}/questionnaires/catalog', [App\Http\Controllers\Api\Mobile\QuestionnairesController::class, 'catalog'])->name('mobile.questionnaires.catalog');
    Route::get('/bands/{band}/questionnaires/{questionnaire}', [App\Http\Controllers\Api\Mobile\QuestionnairesController::class, 'show'])->name('mobile.questionnaires.show');
});
```

- [ ] **Step 4: Create the controller with the read methods**

`app/Http/Controllers/Api/Mobile/QuestionnairesController.php`:

```php
<?php

namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Models\Bands;
use App\Models\Questionnaires;
use App\Services\QuestionnaireFieldTypeRegistry;
use App\Services\QuestionnaireMappingRegistry;
use App\Services\QuestionnairePresetRegistry;
use App\Services\QuestionnaireTemplateService;

class QuestionnairesController extends Controller
{
    public function __construct(
        private QuestionnaireFieldTypeRegistry $typeRegistry,
        private QuestionnaireMappingRegistry $mappingRegistry,
        private QuestionnairePresetRegistry $presetRegistry,
        private QuestionnaireTemplateService $templateService,
    ) {
    }

    public function index(Bands $band)
    {
        $questionnaires = $band->questionnaires()
            ->withCount('instances')
            ->orderBy('name')
            ->get()
            ->map(fn (Questionnaires $q) => $this->summary($q));

        return response()->json(['questionnaires' => $questionnaires]);
    }

    public function catalog(Bands $band)
    {
        return response()->json([
            'field_types' => $this->typeRegistry->catalog(),
            'mapping_targets' => $this->mappingRegistry->catalog(),
            'presets' => $this->presetRegistry->catalog(),
        ]);
    }

    public function show(Bands $band, Questionnaires $questionnaire)
    {
        $this->ensureBelongsToBand($band, $questionnaire);
        $questionnaire->load('fields')->loadCount('instances');

        return response()->json(['questionnaire' => $this->detail($questionnaire)]);
    }

    private function ensureBelongsToBand(Bands $band, Questionnaires $questionnaire): void
    {
        abort_if($questionnaire->band_id !== $band->id, 404, 'Questionnaire does not belong to this band');
    }

    private function summary(Questionnaires $q): array
    {
        return [
            'id' => $q->id,
            'name' => $q->name,
            'description' => $q->description,
            'archived_at' => $q->archived_at?->toIso8601String(),
            'instances_count' => $q->instances_count ?? 0,
            'updated_at' => $q->updated_at?->toIso8601String(),
        ];
    }

    private function detail(Questionnaires $q): array
    {
        return $this->summary($q) + [
            'fields' => $q->fields->map(fn ($f) => [
                'id' => $f->id,
                'type' => $f->type,
                'label' => $f->label,
                'help_text' => $f->help_text,
                'required' => (bool) $f->required,
                'position' => $f->position,
                'settings' => $f->settings,
                'visibility_rule' => $f->visibility_rule,
                'mapping_target' => $f->mapping_target,
            ])->values()->all(),
        ];
    }
}
```

(The `fields` relation is already `orderBy('position')` on the model. `instances_count` comes from `withCount`/`loadCount`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `docker-compose exec app php artisan test --filter=QuestionnaireMobileTest`
Expected: PASS (6 tests). If `assignRole('band-member')` throws RoleDoesNotExist, switch to the `givePermissionTo` fallback shown in the setUp comment.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(mobile): questionnaire read endpoints (index, catalog, show)"
```

### Task 4: Mobile write endpoints (store, update, archive, restore, destroy)

**Files:**
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/QuestionnairesController.php`
- Modify: `/home/eddie/github/TTS/routes/api.php` (right after Task 3's read group)
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/QuestionnaireMobileTest.php`

**Interfaces:**
- Consumes: `QuestionnaireTemplateService::applyPreset/validateFieldsPayload/upsertFields` (Task 2), `UpdateQuestionnaireRequest` (existing web FormRequest — reused verbatim; its `authorize()` reads the bound `{questionnaire}` route param, which mobile routes also bind).
- Produces (the mobile app's write contract):
  - `POST /questionnaires` `{name, description?, preset_key?}` → 201 `{"questionnaire": <detail>}` (preset fields cloned)
  - `PUT /questionnaires/{questionnaire}` `{name, description, fields: [...]}` → 200 `{"questionnaire": <detail>}` (same payload contract as web builder)
  - `POST …/archive` / `POST …/restore` → 200 `{"questionnaire": <detail>}`
  - `DELETE …` → 200 `{"message": …}`; with instances → **409** `{"message": "This questionnaire has been sent and cannot be deleted. Archive it instead."}`

- [ ] **Step 1: Add the failing tests**

Append to `QuestionnaireMobileTest.php` (inside the class):

```php
    public function test_owner_can_create_blank_questionnaire(): void
    {
        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaires", [
                'name' => 'New Intake',
                'description' => 'For weddings',
            ])
            ->assertStatus(201)
            ->assertJsonPath('questionnaire.name', 'New Intake')
            ->assertJsonPath('questionnaire.fields', []);

        $this->assertDatabaseHas('questionnaires', [
            'band_id' => $this->band->id,
            'name' => 'New Intake',
        ]);
    }

    public function test_create_with_preset_clones_fields(): void
    {
        $response = $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaires", [
                'name' => 'Wedding',
                'preset_key' => 'wedding',
            ])
            ->assertStatus(201);

        $this->assertNotEmpty($response->json('questionnaire.fields'));
    }

    public function test_member_cannot_create(): void
    {
        $this->withHeaders($this->asMember())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaires", ['name' => 'Nope'])
            ->assertStatus(403);
    }

    public function test_update_upserts_fields_and_rewrites_visibility(): void
    {
        $q = $this->makeQuestionnaire();

        $response = $this->withHeaders($this->asOwner())
            ->putJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$q->id}", [
                'name' => 'Renamed',
                'description' => null,
                'fields' => [
                    [
                        'id' => null, 'client_id' => 'tmp-1', 'type' => 'yes_no',
                        'label' => 'Onsite ceremony?', 'help_text' => null,
                        'required' => true, 'position' => 10,
                        'settings' => null, 'visibility_rule' => null, 'mapping_target' => 'wedding.onsite',
                    ],
                    [
                        'id' => null, 'client_id' => 'tmp-2', 'type' => 'short_text',
                        'label' => 'Ceremony details', 'help_text' => null,
                        'required' => false, 'position' => 20,
                        'settings' => null,
                        'visibility_rule' => ['depends_on' => 'tmp-1', 'operator' => 'equals', 'value' => 'yes'],
                        'mapping_target' => null,
                    ],
                ],
            ])
            ->assertOk()
            ->assertJsonPath('questionnaire.name', 'Renamed')
            ->assertJsonCount(2, 'questionnaire.fields');

        $fields = $response->json('questionnaire.fields');
        // depends_on must be rewritten from client_id to the persisted DB id.
        $this->assertSame($fields[0]['id'], $fields[1]['visibility_rule']['depends_on']);
    }

    public function test_update_deletes_missing_fields(): void
    {
        $q = $this->makeQuestionnaire();
        $keep = $q->fields()->create(['type' => 'short_text', 'label' => 'Keep', 'position' => 10, 'required' => false]);
        $drop = $q->fields()->create(['type' => 'short_text', 'label' => 'Drop', 'position' => 20, 'required' => false]);

        $this->withHeaders($this->asOwner())
            ->putJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$q->id}", [
                'name' => $q->name,
                'description' => null,
                'fields' => [[
                    'id' => $keep->id, 'client_id' => "id-{$keep->id}", 'type' => 'short_text',
                    'label' => 'Keep', 'help_text' => null, 'required' => false, 'position' => 10,
                    'settings' => null, 'visibility_rule' => null, 'mapping_target' => null,
                ]],
            ])
            ->assertOk()
            ->assertJsonCount(1, 'questionnaire.fields');

        $this->assertDatabaseMissing('questionnaire_fields', ['id' => $drop->id]);
    }

    public function test_update_rejects_dropdown_without_options(): void
    {
        $q = $this->makeQuestionnaire();

        $this->withHeaders($this->asOwner())
            ->putJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$q->id}", [
                'name' => $q->name,
                'description' => null,
                'fields' => [[
                    'id' => null, 'client_id' => 'tmp-1', 'type' => 'dropdown',
                    'label' => 'Pick one', 'help_text' => null, 'required' => false, 'position' => 10,
                    'settings' => null, 'visibility_rule' => null, 'mapping_target' => null,
                ]],
            ])
            ->assertStatus(422);
    }

    public function test_archive_and_restore(): void
    {
        $q = $this->makeQuestionnaire();

        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$q->id}/archive")
            ->assertOk();
        $this->assertNotNull($q->fresh()->archived_at);

        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$q->id}/restore")
            ->assertOk()
            ->assertJsonPath('questionnaire.archived_at', null);
        $this->assertNull($q->fresh()->archived_at);
    }

    public function test_destroy_soft_deletes(): void
    {
        $q = $this->makeQuestionnaire();

        $this->withHeaders($this->asOwner())
            ->deleteJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$q->id}")
            ->assertOk();

        $this->assertSoftDeleted('questionnaires', ['id' => $q->id]);
    }

    public function test_destroy_with_instances_is_409(): void
    {
        $q = $this->makeQuestionnaire();
        $booking = \App\Models\Bookings::factory()->create(['band_id' => $this->band->id]);
        $contact = \App\Models\Contacts::factory()->create();

        \App\Models\QuestionnaireInstances::create([
            'questionnaire_id' => $q->id,
            'booking_id' => $booking->id,
            'recipient_contact_id' => $contact->id,
            'sent_by_user_id' => $this->owner->id,
            'name' => $q->name,
            'description' => '',
            'status' => \App\Models\QuestionnaireInstances::STATUS_SENT,
            'sent_at' => now(),
        ]);

        $this->withHeaders($this->asOwner())
            ->deleteJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$q->id}")
            ->assertStatus(409);

        $this->assertDatabaseHas('questionnaires', ['id' => $q->id, 'deleted_at' => null]);
    }
```

(If `Bookings`/`Contacts` factories need extra required attributes, copy the factory invocations from any existing mobile bookings feature test. If `QuestionnaireInstances` mass-assignment is guarded, use property assignment + `save()` like `makeQuestionnaire()`.)

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `docker-compose exec app php artisan test --filter=QuestionnaireMobileTest`
Expected: Task 3's 6 tests PASS; the 9 new ones FAIL (405/404 — routes missing).

- [ ] **Step 3: Add the write routes**

In `routes/api.php`, directly after the read group from Task 3:

```php
Route::middleware('mobile.band:write:questionnaires')->group(function () {
    Route::post('/bands/{band}/questionnaires', [App\Http\Controllers\Api\Mobile\QuestionnairesController::class, 'store'])->name('mobile.questionnaires.store');
    Route::put('/bands/{band}/questionnaires/{questionnaire}', [App\Http\Controllers\Api\Mobile\QuestionnairesController::class, 'update'])->name('mobile.questionnaires.update');
    Route::post('/bands/{band}/questionnaires/{questionnaire}/archive', [App\Http\Controllers\Api\Mobile\QuestionnairesController::class, 'archive'])->name('mobile.questionnaires.archive');
    Route::post('/bands/{band}/questionnaires/{questionnaire}/restore', [App\Http\Controllers\Api\Mobile\QuestionnairesController::class, 'restore'])->name('mobile.questionnaires.restore');
    Route::delete('/bands/{band}/questionnaires/{questionnaire}', [App\Http\Controllers\Api\Mobile\QuestionnairesController::class, 'destroy'])->name('mobile.questionnaires.destroy');
});
```

- [ ] **Step 4: Add the write methods to the mobile controller**

Add imports `use App\Http\Requests\UpdateQuestionnaireRequest;`, `use Illuminate\Http\Request;`, `use Illuminate\Support\Facades\DB;`, then:

```php
    public function store(Request $request, Bands $band)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:120',
            'description' => 'nullable|string',
            'preset_key' => 'nullable|string|max:60',
        ]);

        $questionnaire = DB::transaction(function () use ($band, $validated) {
            $q = new Questionnaires();
            $q->band_id = $band->id; // must be set before name: slug de-dupes per band
            $q->name = $validated['name'];
            $q->description = $validated['description'] ?? null;
            $q->save();

            if (! empty($validated['preset_key'])) {
                $this->templateService->applyPreset($q, $validated['preset_key']);
            }

            return $q;
        });

        $questionnaire->load('fields')->loadCount('instances');

        return response()->json(['questionnaire' => $this->detail($questionnaire)], 201);
    }

    public function update(UpdateQuestionnaireRequest $request, Bands $band, Questionnaires $questionnaire)
    {
        $this->ensureBelongsToBand($band, $questionnaire);
        $validated = $request->validated();

        $this->templateService->validateFieldsPayload($validated['fields']);

        DB::transaction(function () use ($questionnaire, $validated) {
            $questionnaire->update([
                'name' => $validated['name'],
                'description' => $validated['description'] ?? null,
            ]);
            $this->templateService->upsertFields($questionnaire, $validated['fields']);
        });

        $questionnaire->refresh()->load('fields')->loadCount('instances');

        return response()->json(['questionnaire' => $this->detail($questionnaire)]);
    }

    public function archive(Bands $band, Questionnaires $questionnaire)
    {
        $this->ensureBelongsToBand($band, $questionnaire);
        $questionnaire->archived_at = now();
        $questionnaire->save();
        $questionnaire->load('fields')->loadCount('instances');

        return response()->json(['questionnaire' => $this->detail($questionnaire)]);
    }

    public function restore(Bands $band, Questionnaires $questionnaire)
    {
        $this->ensureBelongsToBand($band, $questionnaire);
        $questionnaire->archived_at = null;
        $questionnaire->save();
        $questionnaire->load('fields')->loadCount('instances');

        return response()->json(['questionnaire' => $this->detail($questionnaire)]);
    }

    public function destroy(Bands $band, Questionnaires $questionnaire)
    {
        $this->ensureBelongsToBand($band, $questionnaire);

        if ($questionnaire->instances()->exists()) {
            return response()->json([
                'message' => 'This questionnaire has been sent and cannot be deleted. Archive it instead.',
            ], 409);
        }

        $questionnaire->delete();

        return response()->json(['message' => 'Questionnaire deleted']);
    }
```

Adjust the `update()` call signatures to whatever exact shapes Task 2 produced (e.g. if `validateFieldsPayload` also takes the questionnaire, pass it). If `$questionnaire->update([...])` is blocked by guarded attributes, use property assignment + `save()` like `store()`.

- [ ] **Step 5: Run the full mobile questionnaire test file**

Run: `docker-compose exec app php artisan test --filter=QuestionnaireMobileTest`
Expected: PASS (15 tests).

- [ ] **Step 6: Run the wider questionnaire + mobile suites for regressions**

Run: `docker-compose exec app php artisan test --filter=Questionnaire`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(mobile): questionnaire write endpoints (store, update, archive, restore, destroy)"
```

---

## Mobile tasks (repo `/home/eddie/github/tts_bandmate`, branch `feat/questionnaires-mobile`)

### Task 5: API endpoints, wire models + model tests

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/core/network/api_endpoints.dart` (new section before the closing `}` at ~line 271)
- Create: `lib/features/questionnaires/data/models/questionnaire_field.dart`
- Create: `lib/features/questionnaires/data/models/questionnaire.dart`
- Create: `lib/features/questionnaires/data/models/questionnaire_catalog.dart`
- Test: `test/features/questionnaires/questionnaire_models_test.dart`

**Interfaces:**
- Produces (used by every later task):
  - `ApiEndpoints.mobileBandQuestionnaires(int bandId)`, `mobileBandQuestionnaireCatalog(int bandId)`, `mobileBandQuestionnaire(int bandId, int questionnaireId)`, `mobileBandQuestionnaireArchive(...)`, `mobileBandQuestionnaireRestore(...)`
  - `VisibilityRule{String dependsOn, String operator, dynamic value}` with `fromJson`/`toJson` — `dependsOn` is ALWAYS a String (server ints stringified)
  - `FieldOption{String label, String value}`
  - `QuestionnaireField{int id, String type, String label, String? helpText, bool required, int position, Map<String,dynamic>? settings, VisibilityRule? visibilityRule, String? mappingTarget}` + `List<FieldOption> get options`
  - `Questionnaire{int id, String name, String? description, DateTime? archivedAt, int instancesCount, DateTime? updatedAt, List<QuestionnaireField> fields}` + `bool get isArchived` + `copyWith`
  - `FieldTypeDef{String type, String label, bool isInput, List<String> requiredSettings}`, `MappingTargetDef{String key, String label, List<String> compatibleFieldTypes}`, `PresetDef{String key, String name, String description, int fieldCount}`, `QuestionnaireCatalog{List<FieldTypeDef> fieldTypes, List<MappingTargetDef> mappingTargets, List<PresetDef> presets}`

- [ ] **Step 1: Add the endpoint builders**

In `api_endpoints.dart`, before the closing brace of the class:

```dart
  // Questionnaires
  static String mobileBandQuestionnaires(int bandId) =>
      '/api/mobile/bands/$bandId/questionnaires';
  static String mobileBandQuestionnaireCatalog(int bandId) =>
      '/api/mobile/bands/$bandId/questionnaires/catalog';
  static String mobileBandQuestionnaire(int bandId, int questionnaireId) =>
      '/api/mobile/bands/$bandId/questionnaires/$questionnaireId';
  static String mobileBandQuestionnaireArchive(int bandId, int questionnaireId) =>
      '/api/mobile/bands/$bandId/questionnaires/$questionnaireId/archive';
  static String mobileBandQuestionnaireRestore(int bandId, int questionnaireId) =>
      '/api/mobile/bands/$bandId/questionnaires/$questionnaireId/restore';
```

- [ ] **Step 2: Write the failing model tests**

`test/features/questionnaires/questionnaire_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_catalog.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_field.dart';

void main() {
  group('QuestionnaireField.fromJson', () {
    test('test_parses_all_fields', () {
      final field = QuestionnaireField.fromJson({
        'id': 5,
        'type': 'dropdown',
        'label': 'Package',
        'help_text': 'Pick one',
        'required': true,
        'position': 20,
        'settings': {
          'options': [
            {'label': 'Gold', 'value': 'gold'},
          ],
        },
        'visibility_rule': {'depends_on': 3, 'operator': 'equals', 'value': 'yes'},
        'mapping_target': 'wedding.onsite',
      });
      expect(field.id, 5);
      expect(field.type, 'dropdown');
      expect(field.helpText, 'Pick one');
      expect(field.required, true);
      expect(field.options.single.label, 'Gold');
      expect(field.options.single.value, 'gold');
      expect(field.visibilityRule!.dependsOn, '3'); // int stringified
      expect(field.visibilityRule!.operator, 'equals');
      expect(field.mappingTarget, 'wedding.onsite');
    });

    test('test_null_coalesces_optional_fields', () {
      final field = QuestionnaireField.fromJson({'id': 1, 'type': 'short_text', 'label': 'Name'});
      expect(field.helpText, null);
      expect(field.required, false);
      expect(field.position, 0);
      expect(field.settings, null);
      expect(field.options, isEmpty);
      expect(field.visibilityRule, null);
      expect(field.mappingTarget, null);
    });
  });

  group('Questionnaire.fromJson', () {
    test('test_parses_detail_with_fields', () {
      final q = Questionnaire.fromJson({
        'id': 1,
        'name': 'Wedding Intake',
        'description': 'For weddings',
        'archived_at': null,
        'instances_count': 2,
        'updated_at': '2026-07-15T10:00:00+00:00',
        'fields': [
          {'id': 10, 'type': 'header', 'label': 'Basics', 'position': 10},
        ],
      });
      expect(q.id, 1);
      expect(q.name, 'Wedding Intake');
      expect(q.isArchived, false);
      expect(q.instancesCount, 2);
      expect(q.fields.single.type, 'header');
    });

    test('test_archived_flag', () {
      final q = Questionnaire.fromJson({
        'id': 2,
        'name': 'Old',
        'archived_at': '2026-01-01T00:00:00+00:00',
      });
      expect(q.isArchived, true);
      expect(q.fields, isEmpty);
      expect(q.instancesCount, 0);
    });
  });

  group('QuestionnaireCatalog.fromJson', () {
    test('test_parses_catalogs', () {
      final catalog = QuestionnaireCatalog.fromJson({
        'field_types': [
          {'type': 'dropdown', 'label': 'Dropdown', 'is_input': true, 'required_settings': ['options']},
          {'type': 'header', 'label': 'Header', 'is_input': false, 'required_settings': []},
        ],
        'mapping_targets': [
          {'key': 'wedding.onsite', 'label': 'Onsite ceremony', 'compatible_field_types': ['yes_no']},
        ],
        'presets': [
          {'key': 'wedding', 'name': 'Wedding', 'description': 'Full wedding intake', 'field_count': 20},
        ],
      });
      expect(catalog.fieldTypes.first.requiredSettings, ['options']);
      expect(catalog.fieldTypes.last.isInput, false);
      expect(catalog.mappingTargets.single.compatibleFieldTypes, ['yes_no']);
      expect(catalog.presets.single.key, 'wedding');
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/questionnaires/questionnaire_models_test.dart`
Expected: FAIL — imports don't resolve.

- [ ] **Step 4: Implement the models**

`lib/features/questionnaires/data/models/questionnaire_field.dart`:

```dart
/// A visibility rule. [dependsOn] is always a String: the server sends the
/// referenced field's DB id (stringified here); the editor sends client ids
/// ('id-<dbId>' / 'tmp-<n>') which the server rewrites on save.
class VisibilityRule {
  const VisibilityRule({
    required this.dependsOn,
    required this.operator,
    this.value,
  });

  final String dependsOn;
  final String operator; // equals | not_equals | contains | empty | not_empty
  final dynamic value;

  factory VisibilityRule.fromJson(Map<String, dynamic> json) {
    return VisibilityRule(
      dependsOn: '${json['depends_on']}',
      operator: json['operator'] as String? ?? 'equals',
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson() =>
      {'depends_on': dependsOn, 'operator': operator, 'value': value};

  VisibilityRule copyWith({String? dependsOn, String? operator, dynamic value}) {
    return VisibilityRule(
      dependsOn: dependsOn ?? this.dependsOn,
      operator: operator ?? this.operator,
      value: value,
    );
  }
}

class FieldOption {
  const FieldOption({required this.label, required this.value});

  final String label;
  final String value;

  factory FieldOption.fromJson(Map<String, dynamic> json) => FieldOption(
        label: json['label'] as String? ?? '',
        value: '${json['value'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

class QuestionnaireField {
  const QuestionnaireField({
    required this.id,
    required this.type,
    required this.label,
    this.helpText,
    required this.required,
    required this.position,
    this.settings,
    this.visibilityRule,
    this.mappingTarget,
  });

  final int id;
  final String type;
  final String label;
  final String? helpText;
  final bool required;
  final int position;
  final Map<String, dynamic>? settings;
  final VisibilityRule? visibilityRule;
  final String? mappingTarget;

  List<FieldOption> get options {
    final raw = settings?['options'] as List<dynamic>? ?? [];
    return raw
        .map((o) => FieldOption.fromJson(o as Map<String, dynamic>))
        .toList();
  }

  factory QuestionnaireField.fromJson(Map<String, dynamic> json) {
    final rawRule = json['visibility_rule'] as Map<String, dynamic>?;
    return QuestionnaireField(
      id: (json['id'] as num).toInt(),
      type: json['type'] as String? ?? 'short_text',
      label: json['label'] as String? ?? '',
      helpText: json['help_text'] as String?,
      required: (json['required'] as bool?) ?? false,
      position: (json['position'] as num?)?.toInt() ?? 0,
      settings: json['settings'] as Map<String, dynamic>?,
      visibilityRule: rawRule == null ? null : VisibilityRule.fromJson(rawRule),
      mappingTarget: json['mapping_target'] as String?,
    );
  }
}
```

`lib/features/questionnaires/data/models/questionnaire.dart`:

```dart
import 'questionnaire_field.dart';

class Questionnaire {
  const Questionnaire({
    required this.id,
    required this.name,
    this.description,
    this.archivedAt,
    required this.instancesCount,
    this.updatedAt,
    this.fields = const [],
  });

  final int id;
  final String name;
  final String? description;
  final DateTime? archivedAt;
  final int instancesCount;
  final DateTime? updatedAt;
  final List<QuestionnaireField> fields;

  bool get isArchived => archivedAt != null;

  factory Questionnaire.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'] as List<dynamic>? ?? [];
    return Questionnaire(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      archivedAt: json['archived_at'] == null
          ? null
          : DateTime.tryParse(json['archived_at'] as String),
      instancesCount: (json['instances_count'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'] as String),
      fields: rawFields
          .map((f) => QuestionnaireField.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }

  Questionnaire copyWith({
    String? name,
    String? description,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    int? instancesCount,
    List<QuestionnaireField>? fields,
  }) {
    return Questionnaire(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      instancesCount: instancesCount ?? this.instancesCount,
      updatedAt: updatedAt,
      fields: fields ?? this.fields,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Questionnaire &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Questionnaire(id: $id, name: $name)';
}
```

`lib/features/questionnaires/data/models/questionnaire_catalog.dart`:

```dart
class FieldTypeDef {
  const FieldTypeDef({
    required this.type,
    required this.label,
    required this.isInput,
    this.requiredSettings = const [],
  });

  final String type;
  final String label;
  final bool isInput;
  final List<String> requiredSettings;

  factory FieldTypeDef.fromJson(Map<String, dynamic> json) => FieldTypeDef(
        type: json['type'] as String? ?? '',
        label: json['label'] as String? ?? '',
        isInput: (json['is_input'] as bool?) ?? true,
        requiredSettings: (json['required_settings'] as List<dynamic>? ?? [])
            .map((s) => s as String)
            .toList(),
      );
}

class MappingTargetDef {
  const MappingTargetDef({
    required this.key,
    required this.label,
    this.compatibleFieldTypes = const [],
  });

  final String key;
  final String label;
  final List<String> compatibleFieldTypes;

  factory MappingTargetDef.fromJson(Map<String, dynamic> json) =>
      MappingTargetDef(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        compatibleFieldTypes:
            (json['compatible_field_types'] as List<dynamic>? ?? [])
                .map((t) => t as String)
                .toList(),
      );
}

class PresetDef {
  const PresetDef({
    required this.key,
    required this.name,
    required this.description,
    required this.fieldCount,
  });

  final String key;
  final String name;
  final String description;
  final int fieldCount;

  factory PresetDef.fromJson(Map<String, dynamic> json) => PresetDef(
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        fieldCount: (json['field_count'] as num?)?.toInt() ?? 0,
      );
}

class QuestionnaireCatalog {
  const QuestionnaireCatalog({
    this.fieldTypes = const [],
    this.mappingTargets = const [],
    this.presets = const [],
  });

  final List<FieldTypeDef> fieldTypes;
  final List<MappingTargetDef> mappingTargets;
  final List<PresetDef> presets;

  factory QuestionnaireCatalog.fromJson(Map<String, dynamic> json) =>
      QuestionnaireCatalog(
        fieldTypes: (json['field_types'] as List<dynamic>? ?? [])
            .map((t) => FieldTypeDef.fromJson(t as Map<String, dynamic>))
            .toList(),
        mappingTargets: (json['mapping_targets'] as List<dynamic>? ?? [])
            .map((t) => MappingTargetDef.fromJson(t as Map<String, dynamic>))
            .toList(),
        presets: (json['presets'] as List<dynamic>? ?? [])
            .map((p) => PresetDef.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/questionnaires/questionnaire_models_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(questionnaires): wire models + API endpoints"
```

### Task 6: Visibility evaluator (Dart port) + tests

**Files:**
- Create: `lib/features/questionnaires/logic/visibility_evaluator.dart`
- Test: `test/features/questionnaires/visibility_evaluator_test.dart`

**Interfaces:**
- Consumes: `VisibilityRule` (Task 5).
- Produces: `VisibilityFieldRef{String id, VisibilityRule? rule}` and `bool isFieldVisible(String fieldId, List<VisibilityFieldRef> allFields, Map<String, dynamic> responses)` — used by the Preview screen (Task 12) with editor client ids, and later by Phase 2's responses screen with stringified DB ids.

- [ ] **Step 1: Write the failing tests**

`test/features/questionnaires/visibility_evaluator_test.dart` (cases mirror `resources/js/Pages/Contact/Questionnaire/visibility.js` in TTS):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_field.dart';
import 'package:tts_bandmate/features/questionnaires/logic/visibility_evaluator.dart';

VisibilityFieldRef ref(String id, {VisibilityRule? rule}) =>
    VisibilityFieldRef(id: id, rule: rule);

void main() {
  test('test_no_rule_is_visible', () {
    expect(isFieldVisible('a', [ref('a')], {}), true);
  });

  test('test_unknown_field_is_visible', () {
    expect(isFieldVisible('missing', [ref('a')], {}), true);
  });

  test('test_missing_rule_target_is_visible', () {
    final fields = [
      ref('b', rule: const VisibilityRule(dependsOn: 'gone', operator: 'equals', value: 'x')),
    ];
    expect(isFieldVisible('b', fields, {}), true);
  });

  test('test_equals_matches_string_coercion', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'equals', value: 'yes')),
    ];
    expect(isFieldVisible('b', fields, {'a': 'yes'}), true);
    expect(isFieldVisible('b', fields, {'a': 'no'}), false);
    expect(isFieldVisible('b', fields, {}), false);
  });

  test('test_equals_with_array_value_uses_contains', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'equals', value: 'gold')),
    ];
    expect(isFieldVisible('b', fields, {'a': ['gold', 'silver']}), true);
    expect(isFieldVisible('b', fields, {'a': ['silver']}), false);
  });

  test('test_not_equals', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'not_equals', value: 'yes')),
    ];
    expect(isFieldVisible('b', fields, {'a': 'no'}), true);
    expect(isFieldVisible('b', fields, {'a': 'yes'}), false);
  });

  test('test_contains_string_and_array', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'contains', value: 'and'),),
    ];
    expect(isFieldVisible('b', fields, {'a': 'band night'}), true);
    expect(isFieldVisible('b', fields, {'a': 'quiet'}), false);
    expect(isFieldVisible('b', fields, {'a': ['grand entrance', 'exit']}), true);
    expect(isFieldVisible('b', fields, {'a': ['exit']}), false);
  });

  test('test_empty_and_not_empty', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'empty')),
      ref('c', rule: const VisibilityRule(dependsOn: 'a', operator: 'not_empty')),
    ];
    expect(isFieldVisible('b', fields, {}), true);
    expect(isFieldVisible('b', fields, {'a': ''}), true);
    expect(isFieldVisible('b', fields, {'a': <String>[]}), true);
    expect(isFieldVisible('b', fields, {'a': 'x'}), false);
    expect(isFieldVisible('c', fields, {'a': 'x'}), true);
    expect(isFieldVisible('c', fields, {}), false);
  });

  test('test_hidden_dependency_cascades', () {
    // c depends on b; b depends on a and is hidden -> c hidden too.
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'equals', value: 'yes')),
      ref('c', rule: const VisibilityRule(dependsOn: 'b', operator: 'not_empty')),
    ];
    expect(isFieldVisible('c', fields, {'a': 'no', 'b': 'filled'}), false);
    expect(isFieldVisible('c', fields, {'a': 'yes', 'b': 'filled'}), true);
  });

  test('test_unknown_operator_hides', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'bogus', value: 'x')),
    ];
    expect(isFieldVisible('b', fields, {'a': 'x'}), false);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/questionnaires/visibility_evaluator_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement the evaluator**

`lib/features/questionnaires/logic/visibility_evaluator.dart`:

```dart
import '../data/models/questionnaire_field.dart';

/// Dart port of TTS resources/js/Pages/Contact/Questionnaire/visibility.js
/// (which mirrors app/Services/QuestionnaireVisibilityEvaluator.php).
/// Any behavior change here MUST match those two files.
class VisibilityFieldRef {
  const VisibilityFieldRef({required this.id, this.rule});

  final String id;
  final VisibilityRule? rule;
}

bool isFieldVisible(
  String fieldId,
  List<VisibilityFieldRef> allFields,
  Map<String, dynamic> responses,
) {
  final field = _find(fieldId, allFields);
  if (field == null) return true;
  return _fieldIsVisible(field, allFields, responses);
}

bool _fieldIsVisible(
  VisibilityFieldRef field,
  List<VisibilityFieldRef> allFields,
  Map<String, dynamic> responses,
) {
  final rule = field.rule;
  if (rule == null) return true;

  final target = _find(rule.dependsOn, allFields);
  if (target == null) return true;

  if (!_fieldIsVisible(target, allFields, responses)) return false;

  return _evaluate(rule, responses[rule.dependsOn]);
}

VisibilityFieldRef? _find(String id, List<VisibilityFieldRef> allFields) {
  for (final f in allFields) {
    if (f.id == id) return f;
  }
  return null;
}

bool _evaluate(VisibilityRule rule, dynamic value) {
  final expected = rule.value;
  switch (rule.operator) {
    case 'equals':
      return _valueEquals(value, expected);
    case 'not_equals':
      return !_valueEquals(value, expected);
    case 'contains':
      return _valueContains(value, expected);
    case 'empty':
      return _valueIsEmpty(value);
    case 'not_empty':
      return !_valueIsEmpty(value);
    default:
      return false;
  }
}

bool _valueEquals(dynamic value, dynamic expected) {
  if (value is List) return value.contains(expected);
  return '$value' == '$expected';
}

bool _valueContains(dynamic value, dynamic expected) {
  final needle = '$expected';
  if (value is List) {
    return value.any((item) => item is String && item.contains(needle));
  }
  return value is String && value.contains(needle);
}

bool _valueIsEmpty(dynamic value) {
  if (value is List) return value.isEmpty;
  return value == null || value == '';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/questionnaires/visibility_evaluator_test.dart`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(questionnaires): visibility evaluator port"
```

### Task 7: Repository + list/detail/catalog providers + tests

**Files:**
- Create: `lib/features/questionnaires/data/questionnaires_repository.dart`
- Create: `lib/features/questionnaires/providers/questionnaires_provider.dart`
- Test: `test/features/questionnaires/questionnaires_provider_test.dart`

**Interfaces:**
- Consumes: `apiClientProvider` (from `lib/core/providers/core_providers.dart`), `ApiEndpoints` builders + models (Task 5).
- Produces:
  - `QuestionnairesRepository(Dio dio)` with:
    - `Future<List<Questionnaire>> getQuestionnaires(int bandId)`
    - `Future<QuestionnaireCatalog> getCatalog(int bandId)`
    - `Future<Questionnaire> getQuestionnaire(int bandId, int questionnaireId)`
    - `Future<Questionnaire> createQuestionnaire(int bandId, {required String name, String? description, String? presetKey})`
    - `Future<Questionnaire> updateQuestionnaire(int bandId, int questionnaireId, {required String name, String? description, required List<Map<String, dynamic>> fields})`
    - `Future<Questionnaire> archiveQuestionnaire(int bandId, int questionnaireId)` / `restoreQuestionnaire(...)`
    - `Future<void> deleteQuestionnaire(int bandId, int questionnaireId)` (DioException with response 409 propagates)
  - `questionnairesRepositoryProvider` (plain `Provider`)
  - `questionnairesProvider` = `AsyncNotifierProvider.family<QuestionnairesNotifier, List<Questionnaire>, int>` with `refresh()`, `Future<Questionnaire> create({name, description, presetKey})` (appends + returns created), `archive(int id)` / `restoreArchived(int id)` (optimistic replace), `delete(int id)` (removes)
  - `questionnaireDetailProvider` = `FutureProvider.family<Questionnaire, ({int bandId, int questionnaireId})>`
  - `questionnaireCatalogProvider` = `FutureProvider.family<QuestionnaireCatalog, int>`

- [ ] **Step 1: Write the failing provider tests**

`test/features/questionnaires/questionnaires_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_catalog.dart';
import 'package:tts_bandmate/features/questionnaires/data/questionnaires_repository.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaires_provider.dart';

class FakeQuestionnairesRepository implements QuestionnairesRepository {
  FakeQuestionnairesRepository({this.questionnaires = const []});

  List<Questionnaire> questionnaires;
  String? createdName;
  String? createdPresetKey;
  int? archivedId;
  int? deletedId;
  int _nextId = 100;

  @override
  Future<List<Questionnaire>> getQuestionnaires(int bandId) async =>
      questionnaires;

  @override
  Future<QuestionnaireCatalog> getCatalog(int bandId) async =>
      const QuestionnaireCatalog();

  @override
  Future<Questionnaire> getQuestionnaire(int bandId, int questionnaireId) async =>
      questionnaires.firstWhere((q) => q.id == questionnaireId);

  @override
  Future<Questionnaire> createQuestionnaire(
    int bandId, {
    required String name,
    String? description,
    String? presetKey,
  }) async {
    createdName = name;
    createdPresetKey = presetKey;
    return Questionnaire(
      id: _nextId++,
      name: name,
      description: description,
      instancesCount: 0,
    );
  }

  @override
  Future<Questionnaire> updateQuestionnaire(
    int bandId,
    int questionnaireId, {
    required String name,
    String? description,
    required List<Map<String, dynamic>> fields,
  }) async =>
      questionnaires.firstWhere((q) => q.id == questionnaireId);

  @override
  Future<Questionnaire> archiveQuestionnaire(int bandId, int questionnaireId) async {
    archivedId = questionnaireId;
    final q = questionnaires.firstWhere((q) => q.id == questionnaireId);
    return q.copyWith(archivedAt: DateTime.utc(2026, 7, 15));
  }

  @override
  Future<Questionnaire> restoreQuestionnaire(int bandId, int questionnaireId) async {
    final q = questionnaires.firstWhere((q) => q.id == questionnaireId);
    return q.copyWith(clearArchivedAt: true);
  }

  @override
  Future<void> deleteQuestionnaire(int bandId, int questionnaireId) async {
    deletedId = questionnaireId;
  }
}

const _q = Questionnaire(id: 1, name: 'Wedding Intake', instancesCount: 0);

void main() {
  ProviderContainer makeContainer(FakeQuestionnairesRepository repo) {
    return ProviderContainer(
      overrides: [
        questionnairesRepositoryProvider.overrideWithValue(repo),
      ],
    );
  }

  group('QuestionnairesNotifier', () {
    test('test_build_loads_questionnaires', () async {
      final repo = FakeQuestionnairesRepository(questionnaires: [_q]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final list = await container.read(questionnairesProvider(1).future);
      expect(list.single.name, 'Wedding Intake');
    });

    test('test_create_appends_and_returns_created', () async {
      final repo = FakeQuestionnairesRepository(questionnaires: [_q]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(questionnairesProvider(1).future);

      final created = await container
          .read(questionnairesProvider(1).notifier)
          .create(name: 'New', presetKey: 'wedding');

      expect(created.name, 'New');
      expect(repo.createdPresetKey, 'wedding');
      expect(container.read(questionnairesProvider(1)).value!.length, 2);
    });

    test('test_archive_replaces_in_list', () async {
      final repo = FakeQuestionnairesRepository(questionnaires: [_q]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(questionnairesProvider(1).future);

      await container.read(questionnairesProvider(1).notifier).archive(1);

      expect(repo.archivedId, 1);
      expect(container.read(questionnairesProvider(1)).value!.single.isArchived, true);
    });

    test('test_delete_removes_from_list', () async {
      final repo = FakeQuestionnairesRepository(questionnaires: [_q]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(questionnairesProvider(1).future);

      await container.read(questionnairesProvider(1).notifier).delete(1);

      expect(repo.deletedId, 1);
      expect(container.read(questionnairesProvider(1)).value, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/questionnaires/questionnaires_provider_test.dart`
Expected: FAIL — imports don't resolve.

- [ ] **Step 3: Implement the repository**

`lib/features/questionnaires/data/questionnaires_repository.dart`:

```dart
import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/questionnaire.dart';
import 'models/questionnaire_catalog.dart';

class QuestionnairesRepository {
  QuestionnairesRepository(this._dio);

  final Dio _dio;

  Future<List<Questionnaire>> getQuestionnaires(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaires(bandId),
    );
    final list = response.data!['questionnaires'] as List<dynamic>;
    return list
        .map((q) => Questionnaire.fromJson(q as Map<String, dynamic>))
        .toList();
  }

  Future<QuestionnaireCatalog> getCatalog(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireCatalog(bandId),
    );
    return QuestionnaireCatalog.fromJson(response.data!);
  }

  Future<Questionnaire> getQuestionnaire(int bandId, int questionnaireId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaire(bandId, questionnaireId),
    );
    return Questionnaire.fromJson(
        response.data!['questionnaire'] as Map<String, dynamic>);
  }

  Future<Questionnaire> createQuestionnaire(
    int bandId, {
    required String name,
    String? description,
    String? presetKey,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaires(bandId),
      data: {
        'name': name,
        if (description != null) 'description': description,
        if (presetKey != null) 'preset_key': presetKey,
      },
    );
    return Questionnaire.fromJson(
        response.data!['questionnaire'] as Map<String, dynamic>);
  }

  Future<Questionnaire> updateQuestionnaire(
    int bandId,
    int questionnaireId, {
    required String name,
    String? description,
    required List<Map<String, dynamic>> fields,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaire(bandId, questionnaireId),
      data: {
        'name': name,
        'description': description,
        'fields': fields,
      },
    );
    return Questionnaire.fromJson(
        response.data!['questionnaire'] as Map<String, dynamic>);
  }

  Future<Questionnaire> archiveQuestionnaire(int bandId, int questionnaireId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireArchive(bandId, questionnaireId),
    );
    return Questionnaire.fromJson(
        response.data!['questionnaire'] as Map<String, dynamic>);
  }

  Future<Questionnaire> restoreQuestionnaire(int bandId, int questionnaireId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireRestore(bandId, questionnaireId),
    );
    return Questionnaire.fromJson(
        response.data!['questionnaire'] as Map<String, dynamic>);
  }

  Future<void> deleteQuestionnaire(int bandId, int questionnaireId) async {
    await _dio.delete<void>(
      ApiEndpoints.mobileBandQuestionnaire(bandId, questionnaireId),
    );
  }
}
```

- [ ] **Step 4: Implement the providers**

`lib/features/questionnaires/providers/questionnaires_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/questionnaire.dart';
import '../data/models/questionnaire_catalog.dart';
import '../data/questionnaires_repository.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final questionnairesRepositoryProvider = Provider<QuestionnairesRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return QuestionnairesRepository(dio);
});

// ── List notifier ─────────────────────────────────────────────────────────────

class QuestionnairesNotifier extends AsyncNotifier<List<Questionnaire>> {
  QuestionnairesNotifier(this._bandId);

  final int _bandId;

  QuestionnairesRepository get _repo =>
      ref.read(questionnairesRepositoryProvider);

  @override
  Future<List<Questionnaire>> build() => _repo.getQuestionnaires(_bandId);

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getQuestionnaires(_bandId));
  }

  Future<Questionnaire> create({
    required String name,
    String? description,
    String? presetKey,
  }) async {
    final created = await _repo.createQuestionnaire(
      _bandId,
      name: name,
      description: description,
      presetKey: presetKey,
    );
    final current = state.value ?? [];
    state = AsyncValue.data([...current, created]);
    return created;
  }

  Future<void> archive(int questionnaireId) async {
    final updated = await _repo.archiveQuestionnaire(_bandId, questionnaireId);
    _replace(updated);
  }

  Future<void> restoreArchived(int questionnaireId) async {
    final updated = await _repo.restoreQuestionnaire(_bandId, questionnaireId);
    _replace(updated);
  }

  Future<void> delete(int questionnaireId) async {
    await _repo.deleteQuestionnaire(_bandId, questionnaireId);
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.where((q) => q.id != questionnaireId).toList(),
    );
  }

  void _replace(Questionnaire updated) {
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.map((q) => q.id == updated.id ? updated : q).toList(),
    );
  }
}

final questionnairesProvider = AsyncNotifierProvider.family<
    QuestionnairesNotifier, List<Questionnaire>, int>(
  (arg) => QuestionnairesNotifier(arg),
);

// ── Detail + catalog ──────────────────────────────────────────────────────────

final questionnaireDetailProvider = FutureProvider.family<Questionnaire,
    ({int bandId, int questionnaireId})>(
  (ref, args) async {
    final repo = ref.watch(questionnairesRepositoryProvider);
    return repo.getQuestionnaire(args.bandId, args.questionnaireId);
  },
);

final questionnaireCatalogProvider =
    FutureProvider.family<QuestionnaireCatalog, int>(
  (ref, bandId) async {
    final repo = ref.watch(questionnairesRepositoryProvider);
    return repo.getCatalog(bandId);
  },
);
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/questionnaires/questionnaires_provider_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(questionnaires): repository + list/detail/catalog providers"
```

### Task 8: Editor state (EditorField + notifier) + tests

**Files:**
- Create: `lib/features/questionnaires/providers/questionnaire_editor_provider.dart`
- Test: `test/features/questionnaires/questionnaire_editor_provider_test.dart`

**Interfaces:**
- Consumes: `questionnairesRepositoryProvider`, `questionnairesProvider`, `questionnaireDetailProvider` (Task 7); `VisibilityRule` (Task 5).
- Produces (Tasks 10–12 build UI on exactly these):
  - `EditorField{String clientId, int? id, String type, String label, String? helpText, bool required, int position, Map<String, dynamic>? settings, VisibilityRule? visibilityRule, String? mappingTarget}` with `copyWith(... bool clearHelpText/clearSettings/clearVisibilityRule/clearMappingTarget flags ...)` and `Map<String, dynamic> toPayload()`
  - `List<EditorField> editorFieldsFromQuestionnaire(Questionnaire q)` — top-level; maps DB ids to `id-<dbId>` client ids, including inside visibility rules (used by Preview for saved questionnaires too)
  - `QuestionnaireEditorState{String name, String? description, List<EditorField> fields, bool dirty}`
  - `QuestionnaireEditorNotifier` methods: `setName(String)`, `setDescription(String?)`, `addField(String type)` (returns the new `EditorField`), `updateField(EditorField updated)` (matched by clientId), `duplicateField(String clientId)`, `removeField(String clientId)` (clears rules referencing it), `reorder(int oldIndex, int newIndex)` (ReorderableListView semantics), `Future<void> save()`
  - `questionnaireEditorProvider` = `AsyncNotifierProvider.family<QuestionnaireEditorNotifier, QuestionnaireEditorState, ({int bandId, int questionnaireId})>`

- [ ] **Step 1: Write the failing tests**

`test/features/questionnaires/questionnaire_editor_provider_test.dart` (reuses `FakeQuestionnairesRepository` — extract it to `test/features/questionnaires/fake_questionnaires_repository.dart` and import from both test files; move the class verbatim from Task 7's test file plus this override recorder):

```dart
// Add to FakeQuestionnairesRepository:
//   String? updatedName;
//   List<Map<String, dynamic>>? updatedFields;
// and in updateQuestionnaire, before returning:
//   updatedName = name;
//   updatedFields = fields;
```

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_field.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaire_editor_provider.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaires_provider.dart';
import 'fake_questionnaires_repository.dart';

const _key = (bandId: 1, questionnaireId: 1);

final _saved = Questionnaire(
  id: 1,
  name: 'Wedding Intake',
  instancesCount: 0,
  fields: [
    QuestionnaireField.fromJson({
      'id': 5, 'type': 'yes_no', 'label': 'Onsite?', 'position': 10, 'required': true,
    }),
    QuestionnaireField.fromJson({
      'id': 6, 'type': 'short_text', 'label': 'Details', 'position': 20,
      'visibility_rule': {'depends_on': 5, 'operator': 'equals', 'value': 'yes'},
    }),
  ],
);

void main() {
  ProviderContainer makeContainer(FakeQuestionnairesRepository repo) {
    return ProviderContainer(
      overrides: [questionnairesRepositoryProvider.overrideWithValue(repo)],
    );
  }

  test('test_load_maps_ids_to_client_ids', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);

    final state = await container.read(questionnaireEditorProvider(_key).future);

    expect(state.dirty, false);
    expect(state.fields[0].clientId, 'id-5');
    expect(state.fields[1].visibilityRule!.dependsOn, 'id-5');
  });

  test('test_addField_marks_dirty_and_defaults_settings', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireEditorProvider(_key).future);
    final notifier = container.read(questionnaireEditorProvider(_key).notifier);

    final added = notifier.addField('dropdown');

    expect(added.clientId, startsWith('tmp-'));
    expect(added.settings, {'options': <Map<String, dynamic>>[]});
    final state = container.read(questionnaireEditorProvider(_key)).value!;
    expect(state.dirty, true);
    expect(state.fields.length, 3);
  });

  test('test_removeField_clears_dependent_rules', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireEditorProvider(_key).future);
    final notifier = container.read(questionnaireEditorProvider(_key).notifier);

    notifier.removeField('id-5');

    final state = container.read(questionnaireEditorProvider(_key)).value!;
    expect(state.fields.length, 1);
    expect(state.fields.single.visibilityRule, null);
  });

  test('test_reorder_moves_down_with_index_shift', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireEditorProvider(_key).future);
    final notifier = container.read(questionnaireEditorProvider(_key).notifier);

    notifier.reorder(0, 2); // ReorderableListView "move first below second"

    final state = container.read(questionnaireEditorProvider(_key)).value!;
    expect(state.fields.map((f) => f.clientId).toList(), ['id-6', 'id-5']);
    expect(state.dirty, true);
  });

  test('test_save_sends_payload_and_resets_dirty', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireEditorProvider(_key).future);
    final notifier = container.read(questionnaireEditorProvider(_key).notifier);

    notifier.setName('Renamed');
    await notifier.save();

    expect(repo.updatedName, 'Renamed');
    final sent = repo.updatedFields!;
    expect(sent[0]['client_id'], 'id-5');
    expect(sent[0]['position'], 10);
    expect(sent[1]['position'], 20);
    expect(sent[1]['visibility_rule'], {
      'depends_on': 'id-5', 'operator': 'equals', 'value': 'yes',
    });
    expect(container.read(questionnaireEditorProvider(_key)).value!.dirty, false);
  });

  test('test_duplicateField_strips_id_and_copies', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireEditorProvider(_key).future);
    final notifier = container.read(questionnaireEditorProvider(_key).notifier);

    notifier.duplicateField('id-5');

    final state = container.read(questionnaireEditorProvider(_key)).value!;
    expect(state.fields.length, 3);
    final copy = state.fields[1]; // inserted right after the original
    expect(copy.id, null);
    expect(copy.clientId, startsWith('tmp-'));
    expect(copy.label, 'Onsite? (copy)');
  });
}
```

- [ ] **Step 2: Extract the fake repository**

Move `FakeQuestionnairesRepository` from Task 7's test into `test/features/questionnaires/fake_questionnaires_repository.dart` (add the `updatedName`/`updatedFields` recorders noted above), and import it from `questionnaires_provider_test.dart`. Re-run Task 7's tests: `flutter test test/features/questionnaires/questionnaires_provider_test.dart` — PASS.

- [ ] **Step 3: Run new tests to verify they fail**

Run: `flutter test test/features/questionnaires/questionnaire_editor_provider_test.dart`
Expected: FAIL — `questionnaire_editor_provider.dart` missing.

- [ ] **Step 4: Implement the editor provider**

`lib/features/questionnaires/providers/questionnaire_editor_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/questionnaire.dart';
import '../data/models/questionnaire_field.dart';
import 'questionnaires_provider.dart';

/// A field being edited. [clientId] is 'id-<dbId>' for persisted fields and
/// 'tmp-<n>' for new ones; visibility rules reference clientIds and the server
/// rewrites them to DB ids on save (same contract as the web builder).
class EditorField {
  const EditorField({
    required this.clientId,
    this.id,
    required this.type,
    required this.label,
    this.helpText,
    required this.required,
    required this.position,
    this.settings,
    this.visibilityRule,
    this.mappingTarget,
  });

  final String clientId;
  final int? id;
  final String type;
  final String label;
  final String? helpText;
  final bool required;
  final int position;
  final Map<String, dynamic>? settings;
  final VisibilityRule? visibilityRule;
  final String? mappingTarget;

  List<FieldOption> get options {
    final raw = settings?['options'] as List<dynamic>? ?? [];
    return raw
        .map((o) => FieldOption.fromJson(o as Map<String, dynamic>))
        .toList();
  }

  EditorField copyWith({
    String? type,
    String? label,
    String? helpText,
    bool clearHelpText = false,
    bool? required,
    int? position,
    Map<String, dynamic>? settings,
    bool clearSettings = false,
    VisibilityRule? visibilityRule,
    bool clearVisibilityRule = false,
    String? mappingTarget,
    bool clearMappingTarget = false,
  }) {
    return EditorField(
      clientId: clientId,
      id: id,
      type: type ?? this.type,
      label: label ?? this.label,
      helpText: clearHelpText ? null : (helpText ?? this.helpText),
      required: required ?? this.required,
      position: position ?? this.position,
      settings: clearSettings ? null : (settings ?? this.settings),
      visibilityRule:
          clearVisibilityRule ? null : (visibilityRule ?? this.visibilityRule),
      mappingTarget:
          clearMappingTarget ? null : (mappingTarget ?? this.mappingTarget),
    );
  }

  Map<String, dynamic> toPayload() => {
        'id': id,
        'client_id': clientId,
        'type': type,
        'label': label,
        'help_text': helpText,
        'required': required,
        'position': position,
        'settings': settings,
        'visibility_rule': visibilityRule?.toJson(),
        'mapping_target': mappingTarget,
      };
}

/// Maps a saved questionnaire's fields into editor fields, converting DB ids
/// (including visibility_rule.depends_on) to 'id-<dbId>' client ids.
List<EditorField> editorFieldsFromQuestionnaire(Questionnaire q) {
  return q.fields.map((f) {
    final rule = f.visibilityRule;
    return EditorField(
      clientId: 'id-${f.id}',
      id: f.id,
      type: f.type,
      label: f.label,
      helpText: f.helpText,
      required: f.required,
      position: f.position,
      settings: f.settings,
      visibilityRule: rule == null
          ? null
          : VisibilityRule(
              dependsOn: 'id-${rule.dependsOn}',
              operator: rule.operator,
              value: rule.value,
            ),
      mappingTarget: f.mappingTarget,
    );
  }).toList();
}

class QuestionnaireEditorState {
  const QuestionnaireEditorState({
    required this.name,
    this.description,
    required this.fields,
    required this.dirty,
  });

  final String name;
  final String? description;
  final List<EditorField> fields;
  final bool dirty;

  QuestionnaireEditorState copyWith({
    String? name,
    String? description,
    bool clearDescription = false,
    List<EditorField>? fields,
    bool? dirty,
  }) {
    return QuestionnaireEditorState(
      name: name ?? this.name,
      description:
          clearDescription ? null : (description ?? this.description),
      fields: fields ?? this.fields,
      dirty: dirty ?? this.dirty,
    );
  }
}

class QuestionnaireEditorNotifier
    extends AsyncNotifier<QuestionnaireEditorState> {
  QuestionnaireEditorNotifier(this._key);

  final ({int bandId, int questionnaireId}) _key;
  int _nextClientId = 0;

  @override
  Future<QuestionnaireEditorState> build() async {
    final q = await ref
        .read(questionnairesRepositoryProvider)
        .getQuestionnaire(_key.bandId, _key.questionnaireId);
    return QuestionnaireEditorState(
      name: q.name,
      description: q.description,
      fields: editorFieldsFromQuestionnaire(q),
      dirty: false,
    );
  }

  QuestionnaireEditorState get _s => state.value!;

  void _emit(QuestionnaireEditorState next) {
    state = AsyncValue.data(next);
  }

  void setName(String name) =>
      _emit(_s.copyWith(name: name, dirty: true));

  void setDescription(String? description) => _emit(_s.copyWith(
        description: description,
        clearDescription: description == null,
        dirty: true,
      ));

  EditorField addField(String type) {
    final field = EditorField(
      clientId: 'tmp-${++_nextClientId}',
      type: type,
      label: '',
      required: false,
      position: (_s.fields.length + 1) * 10,
      settings: _defaultSettings(type),
    );
    _emit(_s.copyWith(fields: [..._s.fields, field], dirty: true));
    return field;
  }

  Map<String, dynamic>? _defaultSettings(String type) {
    switch (type) {
      case 'dropdown':
      case 'multi_select':
      case 'checkbox_group':
        return {'options': <Map<String, dynamic>>[]};
      case 'song_picker':
        return {'purpose': 'general'};
      default:
        return null;
    }
  }

  void updateField(EditorField updated) {
    _emit(_s.copyWith(
      fields: _s.fields
          .map((f) => f.clientId == updated.clientId ? updated : f)
          .toList(),
      dirty: true,
    ));
  }

  void duplicateField(String clientId) {
    final index = _s.fields.indexWhere((f) => f.clientId == clientId);
    if (index == -1) return;
    final original = _s.fields[index];
    final copy = EditorField(
      clientId: 'tmp-${++_nextClientId}',
      type: original.type,
      label: '${original.label} (copy)',
      helpText: original.helpText,
      required: original.required,
      position: original.position,
      settings: original.settings == null
          ? null
          : Map<String, dynamic>.from(original.settings!),
      visibilityRule: original.visibilityRule,
      mappingTarget: original.mappingTarget,
    );
    final fields = [..._s.fields]..insert(index + 1, copy);
    _emit(_s.copyWith(fields: fields, dirty: true));
  }

  void removeField(String clientId) {
    final fields = _s.fields
        .where((f) => f.clientId != clientId)
        .map((f) => f.visibilityRule?.dependsOn == clientId
            ? f.copyWith(clearVisibilityRule: true)
            : f)
        .toList();
    _emit(_s.copyWith(fields: fields, dirty: true));
  }

  void reorder(int oldIndex, int newIndex) {
    final fields = [..._s.fields];
    if (oldIndex < 0 || oldIndex >= fields.length) return;
    // ReorderableListView semantics: when moving down, target index shifts.
    if (oldIndex < newIndex) newIndex -= 1;
    final item = fields.removeAt(oldIndex);
    if (newIndex < 0) newIndex = 0;
    if (newIndex > fields.length) newIndex = fields.length;
    fields.insert(newIndex, item);
    _emit(_s.copyWith(fields: fields, dirty: true));
  }

  Future<void> save() async {
    final s = _s;
    final payload = <Map<String, dynamic>>[];
    for (var i = 0; i < s.fields.length; i++) {
      payload.add(s.fields[i].copyWith(position: (i + 1) * 10).toPayload());
    }
    final updated = await ref
        .read(questionnairesRepositoryProvider)
        .updateQuestionnaire(
          _key.bandId,
          _key.questionnaireId,
          name: s.name,
          description: s.description,
          fields: payload,
        );
    ref.invalidate(questionnairesProvider(_key.bandId));
    ref.invalidate(questionnaireDetailProvider(_key));
    _emit(QuestionnaireEditorState(
      name: updated.name,
      description: updated.description,
      fields: editorFieldsFromQuestionnaire(updated),
      dirty: false,
    ));
  }
}

final questionnaireEditorProvider = AsyncNotifierProvider.family<
    QuestionnaireEditorNotifier,
    QuestionnaireEditorState,
    ({int bandId, int questionnaireId})>(
  (arg) => QuestionnaireEditorNotifier(arg),
);
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/questionnaires/`
Expected: PASS (all questionnaire test files).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(questionnaires): editor state provider with bulk-save contract"
```

### Task 9: Menu entry, routes, list screen + create sheet

**Files:**
- Modify: `lib/features/more/screens/operations_screen.dart` (add NavRow after Media, NOT owner-gated — members have read access)
- Modify: `lib/core/config/router.dart` (`_kShellPrefixes` + shell route + editor route)
- Create: `lib/features/questionnaires/screens/questionnaires_screen.dart`
- Create: `lib/features/questionnaires/widgets/create_questionnaire_sheet.dart`

**Interfaces:**
- Consumes: `questionnairesProvider`, `questionnaireCatalogProvider` (Task 7), `questionnaireDetailProvider`, `editorFieldsFromQuestionnaire` (Task 8; preview navigation lands in Task 12).
- Produces: routes `/questionnaires` (shell) and `/questionnaires/:id/edit`; `QuestionnairesScreen` (list) and `CreateQuestionnaireSheet`. Task 10's `QuestionnaireEditorScreen({required int questionnaireId})` is navigated to here — create it as a stub in this task so the route compiles, filled in by Task 10.

- [ ] **Step 1: Add the NavRow**

In `operations_screen.dart`, after the Media `NavRow` (all members see it; write actions are gated inside the screens):

```dart
          NavRow(
            title: 'Questionnaires',
            leading: Icon(CupertinoIcons.doc_text,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/questionnaires'),
          ),
```

- [ ] **Step 2: Add routes**

In `router.dart`:
- Add `'/questionnaires',` to `_kShellPrefixes`.
- Add import: `import '../../features/questionnaires/screens/questionnaires_screen.dart';` and `import '../../features/questionnaires/screens/questionnaire_editor_screen.dart';`
- Inside the ShellRoute's `routes`, after the `/finances` GoRoute:

```dart
          GoRoute(
            path: '/questionnaires',
            builder: (_, __) => const QuestionnairesScreen(),
          ),
```

- Outside the shell (near the payout-flow detail routes):

```dart
      GoRoute(
        path: '/questionnaires/:id/edit',
        builder: (_, state) => QuestionnaireEditorScreen(
          questionnaireId: int.parse(state.pathParameters['id']!),
        ),
      ),
```

- [ ] **Step 3: Create the editor screen stub (filled in by Task 10)**

`lib/features/questionnaires/screens/questionnaire_editor_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuestionnaireEditorScreen extends ConsumerStatefulWidget {
  const QuestionnaireEditorScreen({super.key, required this.questionnaireId});

  final int questionnaireId;

  @override
  ConsumerState<QuestionnaireEditorScreen> createState() =>
      _QuestionnaireEditorScreenState();
}

class _QuestionnaireEditorScreenState
    extends ConsumerState<QuestionnaireEditorScreen> {
  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('Edit Questionnaire')),
      child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
    );
  }
}
```

- [ ] **Step 4: Create the list screen**

`lib/features/questionnaires/screens/questionnaires_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../features/auth/data/models/band_summary.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/questionnaire.dart';
import '../providers/questionnaires_provider.dart';
import '../widgets/create_questionnaire_sheet.dart';

class QuestionnairesScreen extends ConsumerWidget {
  const QuestionnairesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const navBarTitle = Text('Questionnaires');
    final authState = ref.watch(authProvider).value;
    final bandId = ref.watch(selectedBandProvider).value;
    final bands = authState is AuthAuthenticated
        ? authState.bands
        : const <BandSummary>[];
    final currentBand =
        bandId == null ? null : bands.where((b) => b.id == bandId).firstOrNull;
    final isOwner = currentBand?.isOwner ?? false;

    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    final listAsync = ref.watch(questionnairesProvider(bandId));

    if (listAsync.isLoading && !listAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    if (listAsync.hasError && !listAsync.hasValue) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(
          child: Center(
            child: Text(
              'Failed to load questionnaires.',
              style: TextStyle(color: context.secondaryText),
            ),
          ),
        ),
      );
    }

    final all = listAsync.value!;
    final active = all.where((q) => !q.isArchived).toList();
    final archived = all.where((q) => q.isArchived).toList();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: navBarTitle,
        trailing: isOwner
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showCreateSheet(context, bandId),
                child: const Icon(CupertinoIcons.add),
              )
            : null,
      ),
      child: SafeArea(
        child: all.isEmpty
            ? Center(
                child: Text(
                  isOwner
                      ? 'No questionnaires yet. Tap + to create one.'
                      : 'No questionnaires yet.',
                  style: TextStyle(color: context.secondaryText),
                ),
              )
            : ListView(
                children: [
                  if (active.isNotEmpty)
                    CupertinoListSection.insetGrouped(
                      children: [
                        for (final q in active)
                          _QuestionnaireRow(
                              questionnaire: q, bandId: bandId, isOwner: isOwner),
                      ],
                    ),
                  if (archived.isNotEmpty)
                    CupertinoListSection.insetGrouped(
                      header: const Text('Archived'),
                      children: [
                        for (final q in archived)
                          _QuestionnaireRow(
                              questionnaire: q, bandId: bandId, isOwner: isOwner),
                      ],
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _showCreateSheet(BuildContext context, int bandId) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CreateQuestionnaireSheet(bandId: bandId),
    );
  }
}

class _QuestionnaireRow extends ConsumerWidget {
  const _QuestionnaireRow({
    required this.questionnaire,
    required this.bandId,
    required this.isOwner,
  });

  final Questionnaire questionnaire;
  final int bandId;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = questionnaire;
    return GestureDetector(
      onLongPress: () => _showActions(context, ref),
      child: CupertinoListTile(
        title: Text(q.name),
        subtitle: Text(
          q.instancesCount == 0
              ? 'Never sent'
              : 'Sent ${q.instancesCount} time${q.instancesCount == 1 ? '' : 's'}',
        ),
        trailing: const CupertinoListTileChevron(),
        onTap: () {
          if (isOwner) {
            context.push('/questionnaires/${q.id}/edit');
          } else {
            _showActions(context, ref);
          }
        },
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final q = questionnaire;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(q.name),
        actions: [
          if (isOwner)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                context.push('/questionnaires/${q.id}/edit');
              },
              child: const Text('Edit'),
            ),
          // Task 12 adds a Preview action here.
          if (isOwner && !q.isArchived)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                await ref
                    .read(questionnairesProvider(bandId).notifier)
                    .archive(q.id);
              },
              child: const Text('Archive'),
            ),
          if (isOwner && q.isArchived)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                await ref
                    .read(questionnairesProvider(bandId).notifier)
                    .restoreArchived(q.id);
              },
              child: const Text('Restore'),
            ),
          if (isOwner)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                await _confirmDelete(context, ref);
              },
              child: const Text('Delete'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Delete questionnaire?'),
        content: Text('"${questionnaire.name}" will be permanently removed.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(questionnairesProvider(bandId).notifier)
          .delete(questionnaire.id);
    } catch (_) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Cannot delete'),
          content: const Text(
              'This questionnaire has been sent and can\'t be deleted — archive it instead.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}
```

Note: `const navBarTitle` inside `build` must be declared as `const Text navBarTitle = Text('Questionnaires');` — adjust if the analyzer complains about const usage in the scaffold lines (mirror `rosters_list_screen.dart`, which declares `const navBar = CupertinoNavigationBar(...)` whole).

- [ ] **Step 5: Create the create-sheet**

`lib/features/questionnaires/widgets/create_questionnaire_sheet.dart` (modeled on `invite_sub_sheet.dart`):

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/questionnaire_catalog.dart';
import '../providers/questionnaires_provider.dart';

class CreateQuestionnaireSheet extends ConsumerStatefulWidget {
  const CreateQuestionnaireSheet({super.key, required this.bandId});

  final int bandId;

  @override
  ConsumerState<CreateQuestionnaireSheet> createState() =>
      _CreateQuestionnaireSheetState();
}

class _CreateQuestionnaireSheetState
    extends ConsumerState<CreateQuestionnaireSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  PresetDef? _preset;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created =
          await ref.read(questionnairesProvider(widget.bandId).notifier).create(
                name: _name.text.trim(),
                description: _description.text.trim().isEmpty
                    ? null
                    : _description.text.trim(),
                presetKey: _preset?.key,
              );
      if (mounted) {
        Navigator.of(context).pop();
        context.push('/questionnaires/${created.id}/edit');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to create questionnaire. Please try again.';
        });
      }
    }
  }

  Future<void> _pickPreset(List<PresetDef> presets) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Start from'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _preset = null);
              Navigator.of(sheetContext).pop();
            },
            child: const Text('Blank'),
          ),
          for (final p in presets)
            CupertinoActionSheetAction(
              onPressed: () {
                setState(() => _preset = p);
                Navigator.of(sheetContext).pop();
              },
              child: Text('${p.name} (${p.fieldCount} fields)'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(questionnaireCatalogProvider(widget.bandId));
    final presets = catalogAsync.value?.presets ?? const <PresetDef>[];

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Text('New Questionnaire',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const CupertinoActivityIndicator()
                        : const Text('Create'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _name,
                placeholder: 'Name',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _description,
                placeholder: 'Description (optional)',
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 8),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _saving ? null : () => _pickPreset(presets),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Start from'),
                    Text(
                      _preset?.name ?? 'Blank',
                      style: TextStyle(color: context.secondaryText),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                      color: CupertinoColors.destructiveRed, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Analyze and run the test suite**

Run: `flutter analyze && flutter test`
Expected: no analyzer issues in changed files; all tests pass.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(questionnaires): menu entry, routes, list screen + create sheet"
```

### Task 10: Builder (editor) screen

**Files:**
- Rewrite: `lib/features/questionnaires/screens/questionnaire_editor_screen.dart` (replace Task 9's stub)

**Interfaces:**
- Consumes: `questionnaireEditorProvider` + `EditorField` (Task 8), `questionnaireCatalogProvider` (Task 7). Navigates to `FieldEditorScreen` (Task 11) and `QuestionnairePreviewScreen` (Task 12) — reference them; if implementing tasks strictly in order, gate those two pushes behind `// Task 11/12` comments and add them when the files exist, or implement 10–12 in one working session before running analyze.
- Produces: the full builder UI: name/description editing, reorderable field list, add-field type picker, dirty-tracked save, discard confirm.

- [ ] **Step 1: Implement the editor screen**

Replace the stub with:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Material, MaterialType, ReorderableListView, ReorderableDragStartListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/questionnaire_catalog.dart';
import '../providers/questionnaire_editor_provider.dart';
import 'field_editor_screen.dart';
import 'questionnaire_preview_screen.dart';

class QuestionnaireEditorScreen extends ConsumerStatefulWidget {
  const QuestionnaireEditorScreen({super.key, required this.questionnaireId});

  final int questionnaireId;

  @override
  ConsumerState<QuestionnaireEditorScreen> createState() =>
      _QuestionnaireEditorScreenState();
}

class _QuestionnaireEditorScreenState
    extends ConsumerState<QuestionnaireEditorScreen> {
  TextEditingController? _name;
  TextEditingController? _description;
  bool _saving = false;

  @override
  void dispose() {
    _name?.dispose();
    _description?.dispose();
    super.dispose();
  }

  ({int bandId, int questionnaireId})? get _key {
    final bandId = ref.read(selectedBandProvider).value;
    if (bandId == null) return null;
    return (bandId: bandId, questionnaireId: widget.questionnaireId);
  }

  @override
  Widget build(BuildContext context) {
    final bandId = ref.watch(selectedBandProvider).value;
    const navBarTitle = Text('Edit Questionnaire');

    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    final key = (bandId: bandId, questionnaireId: widget.questionnaireId);
    final editorAsync = ref.watch(questionnaireEditorProvider(key));

    if (editorAsync.isLoading && !editorAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    if (editorAsync.hasError && !editorAsync.hasValue) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(
          child: Center(
            child: Text(
              'Failed to load questionnaire.',
              style: TextStyle(color: context.secondaryText),
            ),
          ),
        ),
      );
    }

    final state = editorAsync.value!;
    final notifier = ref.read(questionnaireEditorProvider(key).notifier);

    // Controllers are created once from the loaded state, then own the text.
    _name ??= TextEditingController(text: state.name);
    _description ??= TextEditingController(text: state.description ?? '');

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && mounted) Navigator.of(context).pop();
      },
      child: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: navBarTitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _openPreview(state),
                child: const Icon(CupertinoIcons.eye, size: 22),
              ),
              CupertinoButton(
                padding: const EdgeInsets.only(left: 8),
                onPressed:
                    state.dirty && !_saving ? () => _save(notifier) : null,
                child: _saving
                    ? const CupertinoActivityIndicator()
                    : const Text('Save'),
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CupertinoTextField(
                      controller: _name,
                      placeholder: 'Name',
                      onChanged: notifier.setName,
                    ),
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: _description,
                      placeholder: 'Description (optional)',
                      minLines: 1,
                      maxLines: 3,
                      onChanged: (v) =>
                          notifier.setDescription(v.isEmpty ? null : v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: state.fields.isEmpty
                    ? Center(
                        child: Text(
                          'No fields yet. Add one below.',
                          style: TextStyle(color: context.secondaryText),
                        ),
                      )
                    // ReorderableListView is Material-only; wrap with a
                    // transparent Material so no ink bleeds onto Cupertino.
                    : Material(
                        type: MaterialType.transparency,
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: state.fields.length,
                          onReorder: notifier.reorder,
                          itemBuilder: (_, i) => _FieldRow(
                            key: ValueKey(state.fields[i].clientId),
                            field: state.fields[i],
                            index: i,
                            onTap: () => _openFieldEditor(state, i),
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: CupertinoButton.filled(
                  onPressed: _addField,
                  child: const Text('Add field'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(QuestionnaireEditorNotifier notifier) async {
    setState(() => _saving = true);
    try {
      await notifier.save();
    } catch (_) {
      if (mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Save failed'),
            content: const Text(
                'Check that every field has a label and choice fields have options.'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _addField() async {
    final key = _key;
    if (key == null) return;
    final catalog =
        await ref.read(questionnaireCatalogProvider(key.bandId).future);
    if (!mounted) return;

    final inputTypes = catalog.fieldTypes.where((t) => t.isInput).toList();
    final displayTypes = catalog.fieldTypes.where((t) => !t.isInput).toList();

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Add field'),
        actions: [
          for (final t in [...inputTypes, ...displayTypes])
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                final notifier =
                    ref.read(questionnaireEditorProvider(key).notifier);
                notifier.addField(t.type);
                final state =
                    ref.read(questionnaireEditorProvider(key)).value!;
                _openFieldEditor(state, state.fields.length - 1);
              },
              child: Text(t.isInput ? t.label : '${t.label} (display)'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _openFieldEditor(QuestionnaireEditorState state, int index) {
    final key = _key;
    if (key == null) return;
    final field = state.fields[index];
    final notifier = ref.read(questionnaireEditorProvider(key).notifier);
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => FieldEditorScreen(
          bandId: key.bandId,
          clientId: field.clientId,
          editorKey: key,
        ),
      ),
    );
    // FieldEditorScreen reads/writes the editor provider directly by clientId,
    // so no callbacks are needed and it survives provider refreshes.
    // notifier retained here only to document the dependency.
    // ignore: unnecessary_statements
    notifier;
  }

  void _openPreview(QuestionnaireEditorState state) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => QuestionnairePreviewScreen(
          title: state.name,
          fields: state.fields,
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.field,
    required this.index,
    required this.onTap,
  });

  final EditorField field;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (field.options.isNotEmpty) '${field.options.length} options',
      if (field.visibilityRule != null) 'conditional',
      if (field.mappingTarget != null) 'mapped',
    ];

    return CupertinoListTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: Icon(CupertinoIcons.line_horizontal_3,
            size: 20, color: context.secondaryText),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              field.label.isEmpty ? '(untitled)' : field.label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (field.required)
            const Text(' *',
                style: TextStyle(color: CupertinoColors.destructiveRed)),
        ],
      ),
      subtitle: Text(
        chips.isEmpty ? field.type : '${field.type} · ${chips.join(' · ')}',
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }
}
```

Remove the leftover `// ignore: unnecessary_statements` block if the analyzer allows deleting the `notifier;` line outright (it should — delete both lines).

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: only "URI doesn't exist" errors for `field_editor_screen.dart` / `questionnaire_preview_screen.dart` (created in Tasks 11–12). Anything else in this file: fix now.

- [ ] **Step 3: Commit after Task 11–12 make the tree compile**

(If executing tasks strictly one-per-session, create empty stub files for `FieldEditorScreen` and `QuestionnairePreviewScreen` now — same shape as Task 9's stub, with the constructors shown in Tasks 11–12 — so `flutter analyze` is clean, then commit:)

```bash
git add -A && git commit -m "feat(questionnaires): builder screen with reorder + dirty-tracked save"
```

### Task 11: Per-field editor screen

**Files:**
- Create (or fill stub): `lib/features/questionnaires/screens/field_editor_screen.dart`

**Interfaces:**
- Consumes: `questionnaireEditorProvider` (reads the field by `clientId`, writes via `updateField`/`duplicateField`/`removeField`), `questionnaireCatalogProvider`, `VisibilityRule`, `FieldOption`.
- Produces: `FieldEditorScreen({required int bandId, required String clientId, required ({int bandId, int questionnaireId}) editorKey})`.

- [ ] **Step 1: Implement**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/questionnaire_catalog.dart';
import '../data/models/questionnaire_field.dart';
import '../providers/questionnaire_editor_provider.dart';

class FieldEditorScreen extends ConsumerStatefulWidget {
  const FieldEditorScreen({
    super.key,
    required this.bandId,
    required this.clientId,
    required this.editorKey,
  });

  final int bandId;
  final String clientId;
  final ({int bandId, int questionnaireId}) editorKey;

  @override
  ConsumerState<FieldEditorScreen> createState() => _FieldEditorScreenState();
}

class _FieldEditorScreenState extends ConsumerState<FieldEditorScreen> {
  TextEditingController? _label;
  TextEditingController? _help;

  @override
  void dispose() {
    _label?.dispose();
    _help?.dispose();
    super.dispose();
  }

  EditorField? get _field {
    final state = ref.watch(questionnaireEditorProvider(widget.editorKey)).value;
    if (state == null) return null;
    for (final f in state.fields) {
      if (f.clientId == widget.clientId) return f;
    }
    return null;
  }

  QuestionnaireEditorNotifier get _notifier =>
      ref.read(questionnaireEditorProvider(widget.editorKey).notifier);

  void _apply(EditorField updated) => _notifier.updateField(updated);

  @override
  Widget build(BuildContext context) {
    final field = _field;
    final catalog =
        ref.watch(questionnaireCatalogProvider(widget.bandId)).value;

    if (field == null) {
      // Field was removed (e.g. via delete below) — nothing to edit.
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Field')),
        child: SafeArea(child: SizedBox.shrink()),
      );
    }

    _label ??= TextEditingController(text: field.label);
    _help ??= TextEditingController(text: field.helpText ?? '');

    final typeDef = catalog?.fieldTypes
        .where((t) => t.type == field.type)
        .firstOrNull;
    final isInput = typeDef?.isInput ?? true;
    final hasOptions =
        typeDef?.requiredSettings.contains('options') ?? false;
    final hasPurpose =
        typeDef?.requiredSettings.contains('purpose') ?? false;
    final compatibleTargets = (catalog?.mappingTargets ?? const <MappingTargetDef>[])
        .where((m) => m.compatibleFieldTypes.contains(field.type))
        .toList();
    final earlierFields = _earlierInputFields(field);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(typeDef?.label ?? field.type),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoTextFormFieldRow(
                  controller: _label,
                  prefix: const Text('Label'),
                  placeholder: 'Field label',
                  onChanged: (v) => _apply(field.copyWith(label: v)),
                ),
                CupertinoTextFormFieldRow(
                  controller: _help,
                  prefix: const Text('Help'),
                  placeholder: 'Optional help text',
                  onChanged: (v) => _apply(v.isEmpty
                      ? field.copyWith(clearHelpText: true)
                      : field.copyWith(helpText: v)),
                ),
                if (isInput)
                  CupertinoListTile(
                    title: const Text('Required'),
                    trailing: CupertinoSwitch(
                      value: field.required,
                      onChanged: (v) => _apply(field.copyWith(required: v)),
                    ),
                  ),
              ],
            ),
            if (hasOptions) _OptionsSection(field: field, onApply: _apply),
            if (hasPurpose)
              CupertinoListSection.insetGrouped(
                header: const Text('Song picker'),
                children: [
                  CupertinoListTile(
                    title: const Text('Purpose'),
                    additionalInfo: Text(_purposeLabel(
                        field.settings?['purpose'] as String? ?? 'general')),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => _pickPurpose(field),
                  ),
                ],
              ),
            if (compatibleTargets.isNotEmpty)
              CupertinoListSection.insetGrouped(
                header: const Text('Event mapping'),
                children: [
                  CupertinoListTile(
                    title: const Text('Maps to'),
                    additionalInfo: Text(
                      compatibleTargets
                              .where((m) => m.key == field.mappingTarget)
                              .firstOrNull
                              ?.label ??
                          'None',
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => _pickMappingTarget(field, compatibleTargets),
                  ),
                ],
              ),
            if (isInput && earlierFields.isNotEmpty)
              _VisibilitySection(
                field: field,
                earlierFields: earlierFields,
                onApply: _apply,
              ),
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile(
                  title: const Text('Duplicate field'),
                  onTap: () {
                    _notifier.duplicateField(field.clientId);
                    Navigator.of(context).pop();
                  },
                ),
                CupertinoListTile(
                  title: const Text(
                    'Delete field',
                    style: TextStyle(color: CupertinoColors.destructiveRed),
                  ),
                  onTap: () {
                    _notifier.removeField(field.clientId);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Input fields positioned before this one — the only legal visibility
  /// dependencies (server enforces forward-only references).
  List<EditorField> _earlierInputFields(EditorField field) {
    final state =
        ref.read(questionnaireEditorProvider(widget.editorKey)).value;
    if (state == null) return const [];
    final index =
        state.fields.indexWhere((f) => f.clientId == field.clientId);
    if (index <= 0) return const [];
    return state.fields
        .sublist(0, index)
        .where((f) => f.type != 'header' && f.type != 'instructions')
        .toList();
  }

  String _purposeLabel(String purpose) {
    switch (purpose) {
      case 'must_play':
        return 'Must play';
      case 'do_not_play':
        return 'Do not play';
      default:
        return 'General';
    }
  }

  Future<void> _pickPurpose(EditorField field) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Purpose'),
        actions: [
          for (final purpose in const ['must_play', 'do_not_play', 'general'])
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _apply(field.copyWith(settings: {
                  ...?field.settings,
                  'purpose': purpose,
                }));
              },
              child: Text(_purposeLabel(purpose)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickMappingTarget(
      EditorField field, List<MappingTargetDef> targets) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Maps to'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _apply(field.copyWith(clearMappingTarget: true));
            },
            child: const Text('None'),
          ),
          for (final t in targets)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _apply(field.copyWith(mappingTarget: t.key));
              },
              child: Text(t.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

// ── Options editor ────────────────────────────────────────────────────────────

class _OptionsSection extends StatelessWidget {
  const _OptionsSection({required this.field, required this.onApply});

  final EditorField field;
  final ValueChanged<EditorField> onApply;

  void _setOptions(List<FieldOption> options) {
    onApply(field.copyWith(settings: {
      ...?field.settings,
      'options': options.map((o) => o.toJson()).toList(),
    }));
  }

  @override
  Widget build(BuildContext context) {
    final options = field.options;
    return CupertinoListSection.insetGrouped(
      header: const Text('Options'),
      children: [
        for (var i = 0; i < options.length; i++)
          CupertinoListTile(
            // Key on index+label so edits rebuild correctly.
            key: ValueKey('option-$i-${options[i].value}'),
            title: Text(options[i].label),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                final next = [...options]..removeAt(i);
                _setOptions(next);
              },
              child: const Icon(CupertinoIcons.minus_circle,
                  color: CupertinoColors.destructiveRed, size: 20),
            ),
            onTap: () => _editOption(context, options, i),
          ),
        CupertinoListTile(
          title: const Text('Add option'),
          leading: const Icon(CupertinoIcons.add_circled, size: 20),
          onTap: () => _editOption(context, options, null),
        ),
      ],
    );
  }

  Future<void> _editOption(
      BuildContext context, List<FieldOption> options, int? index) async {
    final controller =
        TextEditingController(text: index == null ? '' : options[index].label);
    final label = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(index == null ? 'Add option' : 'Edit option'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(controller: controller, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.isEmpty) return;

    final next = [...options];
    if (index == null) {
      // New options use the label as the value (matching simple web usage);
      // existing options keep their stored value when relabeled.
      next.add(FieldOption(label: label, value: label));
    } else {
      next[index] = FieldOption(label: label, value: next[index].value);
    }
    _setOptions(next);
  }
}

// ── Visibility rule builder ───────────────────────────────────────────────────

class _VisibilitySection extends StatelessWidget {
  const _VisibilitySection({
    required this.field,
    required this.earlierFields,
    required this.onApply,
  });

  final EditorField field;
  final List<EditorField> earlierFields;
  final ValueChanged<EditorField> onApply;

  static const _operators = {
    'equals': 'Equals',
    'not_equals': 'Does not equal',
    'contains': 'Contains',
    'empty': 'Is empty',
    'not_empty': 'Is not empty',
  };

  @override
  Widget build(BuildContext context) {
    final rule = field.visibilityRule;
    final target = rule == null
        ? null
        : earlierFields
            .where((f) => f.clientId == rule.dependsOn)
            .firstOrNull;
    final needsValue =
        rule != null && rule.operator != 'empty' && rule.operator != 'not_empty';

    return CupertinoListSection.insetGrouped(
      header: const Text('Show this field only if…'),
      children: [
        CupertinoListTile(
          title: const Text('Conditional'),
          trailing: CupertinoSwitch(
            value: rule != null,
            onChanged: (v) {
              if (v) {
                onApply(field.copyWith(
                  visibilityRule: VisibilityRule(
                    dependsOn: earlierFields.first.clientId,
                    operator: 'equals',
                    value: null,
                  ),
                ));
              } else {
                onApply(field.copyWith(clearVisibilityRule: true));
              }
            },
          ),
        ),
        if (rule != null) ...[
          CupertinoListTile(
            title: const Text('Field'),
            additionalInfo: Text(
              target == null
                  ? '(removed)'
                  : (target.label.isEmpty ? '(untitled)' : target.label),
            ),
            trailing: const CupertinoListTileChevron(),
            onTap: () => _pickTarget(context, rule),
          ),
          CupertinoListTile(
            title: const Text('Condition'),
            additionalInfo: Text(_operators[rule.operator] ?? rule.operator),
            trailing: const CupertinoListTileChevron(),
            onTap: () => _pickOperator(context, rule),
          ),
          if (needsValue)
            CupertinoListTile(
              title: const Text('Value'),
              additionalInfo: Text('${rule.value ?? '(not set)'}'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => _pickValue(context, rule, target),
            ),
        ],
      ],
    );
  }

  void _applyRule(VisibilityRule rule) =>
      onApply(field.copyWith(visibilityRule: rule));

  Future<void> _pickTarget(BuildContext context, VisibilityRule rule) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Depends on'),
        actions: [
          for (final f in earlierFields)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _applyRule(rule.copyWith(dependsOn: f.clientId, value: null));
              },
              child: Text(f.label.isEmpty ? '(untitled)' : f.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickOperator(BuildContext context, VisibilityRule rule) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Condition'),
        actions: [
          for (final entry in _operators.entries)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                final clearsValue =
                    entry.key == 'empty' || entry.key == 'not_empty';
                _applyRule(rule.copyWith(
                  operator: entry.key,
                  value: clearsValue ? null : rule.value,
                ));
              },
              child: Text(entry.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickValue(
      BuildContext context, VisibilityRule rule, EditorField? target) async {
    // Choice targets get an option picker; yes_no gets Yes/No; else free text.
    if (target != null && target.options.isNotEmpty) {
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: const Text('Value'),
          actions: [
            for (final o in target.options)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _applyRule(rule.copyWith(value: o.value));
                },
                child: Text(o.label),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('Cancel'),
          ),
        ),
      );
      return;
    }
    if (target != null && target.type == 'yes_no') {
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: const Text('Value'),
          actions: [
            for (final v in const ['yes', 'no'])
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _applyRule(rule.copyWith(value: v));
                },
                child: Text(v == 'yes' ? 'Yes' : 'No'),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('Cancel'),
          ),
        ),
      );
      return;
    }
    final controller = TextEditingController(text: '${rule.value ?? ''}');
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Value'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(controller: controller, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) _applyRule(rule.copyWith(value: value));
  }
}
```

Note on `VisibilityRule.copyWith(value: null)`: Task 5's `copyWith` intentionally passes `value` through unconditionally (no `?? this.value`) so `value: null` clears it — that asymmetry is required here.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: clean except a missing `questionnaire_preview_screen.dart` if Task 12 hasn't run.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(questionnaires): per-field editor (settings, mapping, visibility rules)"
```

### Task 12: Preview screen + list wiring

**Files:**
- Create (or fill stub): `lib/features/questionnaires/screens/questionnaire_preview_screen.dart`
- Modify: `lib/features/questionnaires/screens/questionnaires_screen.dart` (add Preview action to the row action sheet)

**Interfaces:**
- Consumes: `EditorField`, `editorFieldsFromQuestionnaire` (Task 8), `isFieldVisible`/`VisibilityFieldRef` (Task 6), `questionnaireDetailProvider` (Task 7).
- Produces: `QuestionnairePreviewScreen({required String title, required List<EditorField> fields})` — interactive for text/email/phone/long_text (text input), yes_no (segmented), dropdown (action sheet), multi_select/checkbox_group (toggle rows); static placeholders for date/time/song_picker; header/instructions as typography. Visibility rules evaluate live off the entered values.

- [ ] **Step 1: Implement the preview screen**

```dart
import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../logic/visibility_evaluator.dart';
import '../providers/questionnaire_editor_provider.dart';

class QuestionnairePreviewScreen extends StatefulWidget {
  const QuestionnairePreviewScreen({
    super.key,
    required this.title,
    required this.fields,
  });

  final String title;
  final List<EditorField> fields;

  @override
  State<QuestionnairePreviewScreen> createState() =>
      _QuestionnairePreviewScreenState();
}

class _QuestionnairePreviewScreenState
    extends State<QuestionnairePreviewScreen> {
  final Map<String, dynamic> _responses = {};

  List<VisibilityFieldRef> get _refs => widget.fields
      .map((f) => VisibilityFieldRef(id: f.clientId, rule: f.visibilityRule))
      .toList();

  void _set(String clientId, dynamic value) =>
      setState(() => _responses[clientId] = value);

  @override
  Widget build(BuildContext context) {
    final visible = widget.fields
        .where((f) => isFieldVisible(f.clientId, _refs, _responses))
        .toList();

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Preview')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            for (final field in visible) _buildField(field),
          ],
        ),
      ),
    );
  }

  Widget _buildField(EditorField field) {
    final label = field.label.isEmpty ? '(untitled)' : field.label;

    switch (field.type) {
      case 'header':
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(label,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        );
      case 'instructions':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(label,
              style: TextStyle(color: context.secondaryText)),
        );
      case 'yes_no':
        return _wrap(
          field,
          CupertinoSegmentedControl<String>(
            groupValue: _responses[field.clientId] as String?,
            children: const {
              'yes': Padding(padding: EdgeInsets.all(8), child: Text('Yes')),
              'no': Padding(padding: EdgeInsets.all(8), child: Text('No')),
            },
            onValueChanged: (v) => _set(field.clientId, v),
          ),
        );
      case 'dropdown':
        final selected = _responses[field.clientId] as String?;
        final selectedLabel = field.options
            .where((o) => o.value == selected)
            .firstOrNull
            ?.label;
        return _wrap(
          field,
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => _pickDropdown(field),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(selectedLabel ?? 'Select…'),
                const Icon(CupertinoIcons.chevron_down, size: 16),
              ],
            ),
          ),
        );
      case 'multi_select':
      case 'checkbox_group':
        final selected =
            (_responses[field.clientId] as List<dynamic>? ?? []).cast<String>();
        return _wrap(
          field,
          Column(
            children: [
              for (final o in field.options)
                CupertinoListTile(
                  padding: EdgeInsets.zero,
                  title: Text(o.label),
                  trailing: selected.contains(o.value)
                      ? const Icon(CupertinoIcons.check_mark_circled_solid)
                      : const Icon(CupertinoIcons.circle),
                  onTap: () {
                    final next = [...selected];
                    if (next.contains(o.value)) {
                      next.remove(o.value);
                    } else {
                      next.add(o.value);
                    }
                    _set(field.clientId, next);
                  },
                ),
            ],
          ),
        );
      case 'date':
      case 'time':
      case 'song_picker':
        return _wrap(
          field,
          Text(
            field.type == 'song_picker'
                ? 'Song picker (interactive in the client portal)'
                : '${field.type == 'date' ? 'Date' : 'Time'} picker (interactive in the client portal)',
            style: TextStyle(color: context.secondaryText),
          ),
        );
      default: // short_text, long_text, email, phone
        return _wrap(
          field,
          CupertinoTextField(
            placeholder: field.type == 'long_text' ? 'Longer answer…' : 'Answer…',
            minLines: field.type == 'long_text' ? 3 : 1,
            maxLines: field.type == 'long_text' ? 5 : 1,
            keyboardType: field.type == 'email'
                ? TextInputType.emailAddress
                : field.type == 'phone'
                    ? TextInputType.phone
                    : TextInputType.text,
            onChanged: (v) => _set(field.clientId, v),
          ),
        );
    }
  }

  Widget _wrap(EditorField field, Widget input) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.label.isEmpty ? '(untitled)' : field.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (field.required)
                const Text(' *',
                    style: TextStyle(color: CupertinoColors.destructiveRed)),
            ],
          ),
          if (field.helpText != null && field.helpText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(field.helpText!,
                  style:
                      TextStyle(color: context.secondaryText, fontSize: 13)),
            ),
          const SizedBox(height: 6),
          input,
        ],
      ),
    );
  }

  Future<void> _pickDropdown(EditorField field) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(field.label.isEmpty ? 'Select' : field.label),
        actions: [
          for (final o in field.options)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _set(field.clientId, o.value);
              },
              child: Text(o.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Wire Preview into the list row action sheet**

In `questionnaires_screen.dart`, replace the `// Task 12 adds a Preview action here.` comment with:

```dart
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              final detail = await ref.read(questionnaireDetailProvider(
                  (bandId: bandId, questionnaireId: q.id)).future);
              if (!context.mounted) return;
              Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => QuestionnairePreviewScreen(
                    title: detail.name,
                    fields: editorFieldsFromQuestionnaire(detail),
                  ),
                ),
              );
            },
            child: const Text('Preview'),
          ),
```

Add the imports to `questionnaires_screen.dart`:

```dart
import '../providers/questionnaire_editor_provider.dart';
import 'questionnaire_preview_screen.dart';
```

- [ ] **Step 3: Analyze + full test run**

Run: `flutter analyze && flutter test`
Expected: analyzer clean; all tests pass (models, evaluator, providers, editor).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(questionnaires): interactive preview with live visibility"
```

### Task 13: Version bump, full verification, PRs

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/pubspec.yaml` (`version:` line)

- [ ] **Step 1: Bump the version**

In `pubspec.yaml`, change `version: 1.14.0+23` to `version: 1.15.0+24` (adjust if the current value has moved — bump minor + build).

- [ ] **Step 2: Full mobile verification**

Run: `flutter analyze && flutter test`
Expected: clean + all green.

- [ ] **Step 3: Full backend verification**

Run: `cd /home/eddie/github/TTS && docker-compose exec app php artisan test --filter=Questionnaire && docker-compose exec app php artisan test tests/Feature/Api/Mobile/QuestionnaireMobileTest.php`
Expected: PASS.

- [ ] **Step 4: Commit the bump**

```bash
cd /home/eddie/github/tts_bandmate && git add pubspec.yaml && git commit -m "chore: bump version to 1.15.0+24"
```

- [ ] **Step 5: On-device verification (run-on-device skill)**

With the local backend running: launch the app on the physical Android phone, **log out and log back in** (the new `read:questionnaires`/`write:questionnaires` token abilities require a fresh token), then: Dashboard → hamburger → Questionnaires → create from the Wedding preset → open the builder → edit a field's label, add a dropdown with two options, add a visibility rule on a later field, reorder by drag, Save → reopen and confirm persistence → Preview and toggle the controlling answer to watch the dependent field appear/disappear → archive → restore → create a blank questionnaire and delete it.

- [ ] **Step 6: Open PRs (after user confirmation)**

Backend: `gh pr create --base staging` from `feat/mobile-questionnaires-api`. Mobile: `gh pr create --base main` from `feat/questionnaires-mobile`. Wait for and address Copilot review comments on both before calling the PRs done.

---

## Self-review notes

- Spec coverage (Phase 1 section): list+catalog+create+detail+update+archive/restore+delete endpoints → Tasks 3–4; NavRow + routes → Task 9 (NavRow deliberately NOT owner-gated, per spec: members read); list screen with active/archived + preset create sheet → Task 9; builder with reorder/dirty/bulk-save → Tasks 8+10; per-field editor with type settings/mapping/visibility → Task 11; preview with live visibility via Dart port → Tasks 6+12; token-ability re-login → Tasks 1, 13.
- Type consistency: `EditorField.clientId`/`toPayload`, `VisibilityRule.dependsOn: String`, provider names (`questionnairesProvider`, `questionnaireDetailProvider`, `questionnaireCatalogProvider`, `questionnaireEditorProvider`), and the repository method names are used identically across Tasks 5–12.
- Known judgment call: changing a field's type after creation is NOT in the field editor (web allows it; the add-flow picks the type up front). If wanted later, it's a `copyWith(type: …, clearSettings/clearMappingTarget: …)` plus a confirm dialog — deferred as YAGNI for v1.
