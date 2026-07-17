# Questionnaires Mobile — Phase 3 (Apply-to-Event + Submission Push) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the last questionnaires slice: applying submitted answers to events from mobile (per-field apply, apply-all, append-to-notes with applied / needs-re-apply states) and a `questionnaire_submitted` push to **all** band owners that deep-links to the responses screen.

**Architecture:** Backend extends `Api/Mobile/QuestionnaireInstancesController` with three apply endpoints over the existing `QuestionnaireMappingService`, enriches the instance-detail payload with additive `response_meta` + per-field mapping labels, and rewrites the portal's owner notification to fan out to all owners with a data-only `SendUserPush`. Mobile adds `ResponseMeta` parsing, three repository calls, apply UI on the responses screen, and the new push type in the payload/route mappers (both already have test files to extend).

**Tech Stack:** Laravel 10 (queued jobs/notifications, FCM via FcmSender), Flutter/Dart (Riverpod v2, Cupertino, flutter_local_notifications background isolate).

**Spec:** `docs/superpowers/specs/2026-07-15-questionnaires-mobile-design.md` (Phase 3 section)

## Global Constraints

- TTS repo: never run `php`/`artisan`/`composer` on the host — always `docker compose exec -T app …` from `/home/eddie/github/TTS`.
- TTS PRs target `staging` (draft); mobile PRs target `main`.
- Backend branch: `feat/mobile-questionnaire-apply` (off `staging`, created in Task 1). Mobile branch: `feat/questionnaires-mobile-phase3` (already exists, off main with Phases 1+2).
- Mobile conventions: Cupertino only; hand-written `fromJson`; `context.secondaryText`; mounted guards per `booking_contacts_screen.dart`; test naming `test_<behavior>`; `flutter analyze` baseline is 3 known pre-existing issues — every task adds zero new.
- Commit with explicit `git add <paths>` only — NEVER `git add -A` (both repos; mobile tree has unrelated files).
- Wire contract (Phase 3, frozen; all additive to Phase 2):
  - Instance detail gains `"response_meta": {<instance_field_id>: {response_id, applied_to_event_at(ISO|null), updated_at(ISO)}}` serialized as `{}` when empty (`(object)` cast), and detail fields gain `mapping_target` + `mapping_label` (label null when unmapped or target no longer exists).
  - `POST /bands/{band}/questionnaire-instances/{instance}/responses/{response}/apply` → 200 `{"response": {response_id, applied_to_event_at, updated_at}}`; service `RuntimeException` (no mapping target / booking has no event / target gone) → 422 `{"message"}`.
  - `POST …/apply-all` → 200 `{"applied_count": N}` (mapped + not-yet-applied responses only, mirroring web).
  - `POST …/append-to-notes` → 200 `{"message": "Answers appended to event notes."}`.
  - Apply routes live under `mobile.band:write:events` middleware + in-controller `canRead('questionnaires', $band->id)` check — the exact web predicate (`canRead` questionnaires AND `canWrite` events).
  - Push payload (data-only, `alert: false`, all string values): `type=questionnaire_submitted`, `title` ("«Client» submitted/updated the «Name»"), `body` ("Booking: «Booking name»"), `instanceId`, and `questionnaireId` (omitted when the template was deleted). Deep link `/questionnaires/{questionnaireId}/instances/{instanceId}`; no route when `questionnaireId` is absent.
  - "Needs re-apply" = `updated_at > applied_to_event_at` (portal re-save bumps `updated_at`, never clears the applied stamp).
- Commit after every green task with the standard Claude trailers.

---

## Backend tasks (repo `/home/eddie/github/TTS`)

### Task 1: Branch + instance-detail response_meta and mapping labels

**Files:**
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/QuestionnaireInstancesController.php` (constructor + `detail()`)
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/QuestionnaireInstanceMobileTest.php`

**Interfaces:**
- Consumes: `QuestionnaireMappingRegistry::targetExists(string): bool` / `label(string): string` (existing).
- Produces: detail payload additions per the wire contract — Task 4's mobile parse depends on the exact keys `response_meta.{fieldId}.{response_id,applied_to_event_at,updated_at}` and `fields[].mapping_target` / `fields[].mapping_label`.

- [ ] **Step 1: Create the branch + baseline**

```bash
cd /home/eddie/github/TTS && git checkout staging && git pull && git checkout -b feat/mobile-questionnaire-apply
docker compose exec -T app php artisan test --filter=Questionnaire
```
Expected: PASS (131).

- [ ] **Step 2: Add the failing test**

Append inside `QuestionnaireInstanceMobileTest` (uses the existing `makeInstance()` helper and detail-test conventions):

```php
    public function test_instance_detail_includes_response_meta_and_mapping_labels(): void
    {
        $instance = $this->makeInstance();
        $mapped = $instance->fields()->create([
            'type' => 'yes_no', 'label' => 'Onsite?', 'position' => 10,
            'required' => false, 'source_field_id' => 0,
            'mapping_target' => 'wedding.onsite',
        ]);
        $plain = $instance->fields()->create([
            'type' => 'short_text', 'label' => 'Notes', 'position' => 20,
            'required' => false, 'source_field_id' => 0,
        ]);
        $response = $instance->responses()->create([
            'instance_field_id' => $mapped->id,
            'value' => 'yes',
        ]);

        $json = $this->withHeaders($this->asMember())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}")
            ->assertOk()
            ->assertJsonPath('instance.fields.0.mapping_target', 'wedding.onsite')
            ->assertJsonPath('instance.fields.0.mapping_label', 'Wedding · Onsite Ceremony')
            ->assertJsonPath('instance.fields.1.mapping_label', null)
            ->assertJsonPath("instance.response_meta.{$mapped->id}.response_id", $response->id)
            ->assertJsonPath("instance.response_meta.{$mapped->id}.applied_to_event_at", null);

        $this->assertNotNull($json->json("instance.response_meta.{$mapped->id}.updated_at"));
    }

    public function test_instance_detail_empty_response_meta_serializes_as_object(): void
    {
        $instance = $this->makeInstance();

        $response = $this->withHeaders($this->asMember())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}")
            ->assertOk();

        $this->assertStringContainsString('"response_meta":{}', $response->getContent());
    }
```

- [ ] **Step 3: Run to verify failure**

Run: `docker compose exec -T app php artisan test --filter=QuestionnaireInstanceMobileTest`
Expected: prior 16 PASS; 2 new FAIL (keys missing).

- [ ] **Step 4: Implement**

In `QuestionnaireInstancesController`: add `use App\Services\QuestionnaireMappingRegistry;` and constructor param `private QuestionnaireMappingRegistry $mappingRegistry,`. In `detail()`, extend the fields map with:

```php
                'mapping_target' => $f->mapping_target,
                'mapping_label' => $f->mapping_target && $this->mappingRegistry->targetExists($f->mapping_target)
                    ? $this->mappingRegistry->label($f->mapping_target)
                    : null,
```

and add after `'song_lookup' => …`:

```php
            'response_meta' => (object) $i->responses->mapWithKeys(fn ($r) => [
                $r->instance_field_id => [
                    'response_id' => $r->id,
                    'applied_to_event_at' => $r->applied_to_event_at?->toIso8601String(),
                    'updated_at' => $r->updated_at?->toIso8601String(),
                ],
            ])->all(),
```

- [ ] **Step 5: Green + regression + commit**

```bash
docker compose exec -T app php artisan test --filter=QuestionnaireInstanceMobileTest
docker compose exec -T app php artisan test --filter=Questionnaire
git add app/Http/Controllers/Api/Mobile/QuestionnaireInstancesController.php tests/Feature/Api/Mobile/QuestionnaireInstanceMobileTest.php
git commit -m "feat(mobile): response metadata + mapping labels in instance detail"
```
Expected: 18/18 file; 133 suite.

### Task 2: Mobile apply endpoints

**Files:**
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/QuestionnaireInstancesController.php`
- Modify: `/home/eddie/github/TTS/routes/api.php` (after the Phase 2 questionnaire-instance write group)
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/QuestionnaireInstanceMobileTest.php`

**Interfaces:**
- Consumes: `QuestionnaireMappingService::applyResponse(QuestionnaireResponses, User): Events` (stamps `applied_to_event_at`/`applied_by_user_id`; throws `RuntimeException` on no-mapping-target / gone-target / no-event) and `appendAllToNotes(QuestionnaireInstances, User): Events` (existing); `mobile.band:write:events` middleware (`write:events` is already in TokenService RESOURCES).
- Produces: the three apply endpoints per the wire contract.

- [ ] **Step 1: Add the failing tests**

Append inside `QuestionnaireInstanceMobileTest` (imports to add at top: `use App\Models\Events;`):

```php
    private function makeMappedResponse(QuestionnaireInstances $instance, string $target = 'wedding.onsite', string $value = 'yes'): \App\Models\QuestionnaireResponses
    {
        $field = $instance->fields()->create([
            'type' => $target === 'wedding.onsite' ? 'yes_no' : 'short_text',
            'label' => 'Mapped', 'position' => 10,
            'required' => false, 'source_field_id' => 0,
            'mapping_target' => $target,
        ]);

        return $instance->responses()->create([
            'instance_field_id' => $field->id,
            'value' => $value,
        ]);
    }

    private function ownerWithEventsToken(): array
    {
        $token = $this->owner->createToken(
            'apply-device', ['mobile', 'read:questionnaires', 'write:questionnaires', 'write:events']
        )->plainTextToken;

        return [
            'Authorization' => "Bearer {$token}",
            'X-Band-ID' => $this->band->id,
            'Accept' => 'application/json',
        ];
    }

    public function test_apply_response_writes_event_data_and_stamps(): void
    {
        $instance = $this->makeInstance();
        $response = $this->makeMappedResponse($instance);

        $this->withHeaders($this->ownerWithEventsToken())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}/responses/{$response->id}/apply")
            ->assertOk()
            ->assertJsonPath('response.response_id', $response->id);

        $response->refresh();
        $this->assertNotNull($response->applied_to_event_at);
        $this->assertSame($this->owner->id, $response->applied_by_user_id);

        $event = $this->booking->events()->orderBy('id')->first();
        $this->assertSame(true, data_get(json_decode(json_encode($event->fresh()->additional_data), true), 'wedding.onsite'));
    }

    public function test_apply_response_without_mapping_target_is_422(): void
    {
        $instance = $this->makeInstance();
        $field = $instance->fields()->create([
            'type' => 'short_text', 'label' => 'Plain', 'position' => 10,
            'required' => false, 'source_field_id' => 0,
        ]);
        $response = $instance->responses()->create([
            'instance_field_id' => $field->id, 'value' => 'x',
        ]);

        $this->withHeaders($this->ownerWithEventsToken())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}/responses/{$response->id}/apply")
            ->assertStatus(422);
    }

    public function test_apply_all_applies_only_pending_mapped(): void
    {
        $instance = $this->makeInstance();
        $pending = $this->makeMappedResponse($instance);
        $already = $this->makeMappedResponse($instance, 'wedding.dance.first', 'Song X');
        $already->update(['applied_to_event_at' => now()->subDay(), 'applied_by_user_id' => $this->owner->id]);

        $this->withHeaders($this->ownerWithEventsToken())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}/apply-all")
            ->assertOk()
            ->assertJsonPath('applied_count', 1);

        $this->assertNotNull($pending->fresh()->applied_to_event_at);
    }

    public function test_append_to_notes_appends_block(): void
    {
        $instance = $this->makeInstance();
        $this->makeMappedResponse($instance);

        $this->withHeaders($this->ownerWithEventsToken())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}/append-to-notes")
            ->assertOk();

        $event = $this->booking->events()->orderBy('id')->first()->fresh();
        $this->assertStringContainsString('Customer submitted', (string) $event->notes);
    }

    public function test_apply_requires_write_events_ability(): void
    {
        $instance = $this->makeInstance();
        $response = $this->makeMappedResponse($instance);

        // Owner token WITHOUT write:events ability → middleware 403.
        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}/responses/{$response->id}/apply")
            ->assertStatus(403);
    }

    public function test_apply_cross_band_instance_is_404(): void
    {
        $otherBand = Bands::factory()->create();
        $otherBooking = Bookings::factory()->create(['band_id' => $otherBand->id]);
        $foreign = $this->makeInstance(['booking_id' => $otherBooking->id]);
        $response = $this->makeMappedResponse($foreign);

        $this->withHeaders($this->ownerWithEventsToken())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$foreign->id}/responses/{$response->id}/apply")
            ->assertStatus(404);
    }
```

(If `additional_data` casts differently, mirror the assertion style from `tests/Feature/Questionnaires/EventMappingTest.php`. Note the setUp booking already has one future event from Phase 2's `Events::factory` adaptation — `resolveEvent` finds it.)

- [ ] **Step 2: Run to verify the 6 new fail**

Run: `docker compose exec -T app php artisan test --filter=QuestionnaireInstanceMobileTest`
Expected: 18 pass, 6 fail (404/405).

- [ ] **Step 3: Routes**

In `routes/api.php`, after the Phase 2 `mobile.band:write:questionnaires` instance group:

```php
// Applying answers to events additionally requires event write (mirrors web:
// canRead questionnaires + canWrite events; the questionnaires read check is
// in-controller).
Route::middleware('mobile.band:write:events')->group(function () {
    Route::post('/bands/{band}/questionnaire-instances/{instance}/responses/{response}/apply', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'applyResponse'])->name('mobile.questionnaire-instances.apply-response');
    Route::post('/bands/{band}/questionnaire-instances/{instance}/apply-all', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'applyAll'])->name('mobile.questionnaire-instances.apply-all');
    Route::post('/bands/{band}/questionnaire-instances/{instance}/append-to-notes', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'appendToNotes'])->name('mobile.questionnaire-instances.append-to-notes');
});
```

- [ ] **Step 4: Controller methods**

Add imports `use App\Models\QuestionnaireResponses;`, `use App\Services\QuestionnaireMappingService;`, `use RuntimeException;` and constructor param `private QuestionnaireMappingService $mappingService,`. Then:

```php
    public function applyResponse(Bands $band, QuestionnaireInstances $instance, QuestionnaireResponses $response): JsonResponse
    {
        $this->ensureBelongsToBand($band, $instance);
        abort_unless(Auth::user()->canRead('questionnaires', $band->id), 403);
        abort_if($response->instance_id !== $instance->id, 404);

        try {
            $this->mappingService->applyResponse($response, Auth::user());
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        $response->refresh();

        return response()->json([
            'response' => [
                'response_id' => $response->id,
                'applied_to_event_at' => $response->applied_to_event_at?->toIso8601String(),
                'updated_at' => $response->updated_at?->toIso8601String(),
            ],
        ]);
    }

    public function applyAll(Bands $band, QuestionnaireInstances $instance): JsonResponse
    {
        $this->ensureBelongsToBand($band, $instance);
        abort_unless(Auth::user()->canRead('questionnaires', $band->id), 403);

        $pending = $instance->responses()
            ->whereHas('instanceField', fn ($q) => $q->whereNotNull('mapping_target'))
            ->whereNull('applied_to_event_at')
            ->get();

        $applied = 0;
        try {
            foreach ($pending as $pendingResponse) {
                $this->mappingService->applyResponse($pendingResponse, Auth::user());
                $applied++;
            }
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage(), 'applied_count' => $applied], 422);
        }

        return response()->json(['applied_count' => $applied]);
    }

    public function appendToNotes(Bands $band, QuestionnaireInstances $instance): JsonResponse
    {
        $this->ensureBelongsToBand($band, $instance);
        abort_unless(Auth::user()->canRead('questionnaires', $band->id), 403);

        try {
            $this->mappingService->appendAllToNotes($instance, Auth::user());
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['message' => 'Answers appended to event notes.']);
    }
```

(`Auth` is already imported from Phase 2's write methods.)

- [ ] **Step 5: Green + regression + commit**

```bash
docker compose exec -T app php artisan test --filter=QuestionnaireInstanceMobileTest
docker compose exec -T app php artisan test --filter=Questionnaire
git add app/Http/Controllers/Api/Mobile/QuestionnaireInstancesController.php routes/api.php tests/Feature/Api/Mobile/QuestionnaireInstanceMobileTest.php
git commit -m "feat(mobile): apply questionnaire answers to events"
```
Expected: 24/24 file; 139 suite.

### Task 3: Submission fan-out to all owners + data-only push

**Files:**
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Contact/PortalQuestionnaireController.php` (`notifyBandOwner` → `notifyBandOwners`, call site in `submit()`)
- Test: `/home/eddie/github/TTS/tests/Feature/Questionnaires/QuestionnaireSubmittedPushTest.php` (create)

**Interfaces:**
- Consumes: `SendUserPush::dispatch(int $userId, array $data, string $dedupeKey, bool $alert)` (existing job; `alert: false` = data-only via `FcmSender::sendData`), `Bands::owners` (hasMany `BandOwners`, each with `->user`), `User::deviceTokens()`, `QuestionnaireSubmitted` notification (unchanged).
- Produces: on portal submit, EVERY owner user gets the `QuestionnaireSubmitted` mail+database notification, and owners with registered devices get the data-only push per the wire contract. Mobile Task 5's deep link depends on the exact payload keys.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature\Questionnaires;

use App\Jobs\SendUserPush;
use App\Models\Bands;
use App\Models\Bookings;
use App\Models\Contacts;
use App\Models\DeviceToken;
use App\Models\QuestionnaireInstances;
use App\Models\Questionnaires;
use App\Models\User;
use App\Notifications\QuestionnaireSubmitted;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

class QuestionnaireSubmittedPushTest extends TestCase
{
    use RefreshDatabase;

    private Bands $band;
    private User $owner1;
    private User $owner2;
    private Contacts $contact;
    private QuestionnaireInstances $instance;

    protected function setUp(): void
    {
        parent::setUp();
        $this->band = Bands::factory()->create();
        $this->owner1 = User::factory()->create();
        $this->owner2 = User::factory()->create();
        $this->band->owners()->create(['user_id' => $this->owner1->id]);
        $this->band->owners()->create(['user_id' => $this->owner2->id]);

        $booking = Bookings::factory()->create(['band_id' => $this->band->id]);
        $this->contact = Contacts::factory()->create(['band_id' => $this->band->id, 'can_login' => true]);
        $booking->contacts()->attach($this->contact, ['is_primary' => true]);

        $template = Questionnaires::factory()->create(['band_id' => $this->band->id]);
        $this->instance = QuestionnaireInstances::create([
            'questionnaire_id' => $template->id,
            'booking_id' => $booking->id,
            'recipient_contact_id' => $this->contact->id,
            'sent_by_user_id' => $this->owner1->id,
            'name' => $template->name,
            'description' => '',
            'status' => QuestionnaireInstances::STATUS_SENT,
            'sent_at' => now(),
        ]);

        DeviceToken::create(['user_id' => $this->owner1->id, 'token' => 'tok-1', 'platform' => 'android']);
        // owner2 has no devices.
    }

    private function submitAsContact(): void
    {
        $this->actingAs($this->contact, 'contact')->post(
            route('portal.booking.questionnaire.submit', [
                'booking' => $this->instance->booking_id,
                'instance' => $this->instance->id,
            ])
        )->assertStatus(302);
    }

    public function test_submit_notifies_all_owners_and_pushes_to_device_holders(): void
    {
        Notification::fake();
        Bus::fake([SendUserPush::class]);

        $this->submitAsContact();

        Notification::assertSentTo($this->owner1, QuestionnaireSubmitted::class);
        Notification::assertSentTo($this->owner2, QuestionnaireSubmitted::class);

        Bus::assertDispatched(SendUserPush::class, function (SendUserPush $job) {
            return $job->userId === $this->owner1->id
                && $job->alert === false
                && $job->data['type'] === 'questionnaire_submitted'
                && $job->data['instanceId'] === (string) $this->instance->id
                && $job->data['questionnaireId'] === (string) $this->instance->questionnaire_id
                && str_contains($job->data['title'], 'submitted');
        });
        Bus::assertNotDispatched(SendUserPush::class, fn (SendUserPush $job) => $job->userId === $this->owner2->id);
    }

    public function test_resubmit_pushes_with_updated_wording(): void
    {
        $this->instance->update(['status' => QuestionnaireInstances::STATUS_SUBMITTED, 'submitted_at' => now()->subHour()]);
        Notification::fake();
        Bus::fake([SendUserPush::class]);

        $this->submitAsContact();

        Bus::assertDispatched(SendUserPush::class, fn (SendUserPush $job) =>
            $job->userId === $this->owner1->id && str_contains($job->data['title'], 'updated'));
    }
}
```

(Adapt the portal submit call to the actual route signature/guard if it differs — read `PortalQuestionnaireController::submit` and existing `PortalQuestionnaireTest` for the exact acting-as pattern and any required request body; required visible fields must be satisfied — with zero fields the instance submits clean. If the submit route requires POST data, mirror the existing test's minimal payload.)

- [ ] **Step 2: Run to verify failure**

Run: `docker compose exec -T app php artisan test --filter=QuestionnaireSubmittedPushTest`
Expected: FAIL — owner2 not notified / no SendUserPush dispatched.

- [ ] **Step 3: Implement the fan-out**

In `PortalQuestionnaireController`, add imports `use App\Jobs\SendUserPush;` and replace `notifyBandOwner` (rename the `submit()` call site accordingly):

```php
    private function notifyBandOwners(QuestionnaireInstances $instance, bool $isUpdate): void
    {
        $band = $instance->booking->band;
        $clientName = $instance->recipientContact->name ?? 'A client';
        $verb = $isUpdate ? 'updated' : 'submitted';

        $push = [
            'type' => 'questionnaire_submitted',
            'title' => "{$clientName} {$verb} the {$instance->name}",
            'body' => "Booking: {$instance->booking->name}",
            'instanceId' => (string) $instance->id,
        ];
        if ($instance->questionnaire_id) {
            $push['questionnaireId'] = (string) $instance->questionnaire_id;
        }
        // One logical send per submission: submitted_at was just stamped by
        // submit(), so re-submits produce a fresh dedupe key while queued
        // retries of the same submission share it.
        $dedupeKey = "questionnaire_submitted:{$instance->id}:{$instance->submitted_at->getTimestamp()}";

        $notifiedUserIds = [];
        foreach ($band->owners as $ownerRow) {
            $user = $ownerRow->user;
            if (!$user || in_array($user->id, $notifiedUserIds, true)) {
                continue;
            }
            $notifiedUserIds[] = $user->id;

            $user->notify(new QuestionnaireSubmitted($instance, $isUpdate));

            if ($user->deviceTokens()->exists()) {
                SendUserPush::dispatch($user->id, $push, $dedupeKey, false);
            }
        }
    }
```

- [ ] **Step 4: Green + regressions + commit**

```bash
docker compose exec -T app php artisan test --filter=QuestionnaireSubmittedPushTest
docker compose exec -T app php artisan test --filter=Questionnaire
```
Expected: 2/2 new; full suite green — if any existing portal test asserted the OLD first-owner-only behavior, update that assertion to the all-owners behavior (this change is the spec's explicit intent, note it in your report).

```bash
git add app/Http/Controllers/Contact/PortalQuestionnaireController.php tests/Feature/Questionnaires/QuestionnaireSubmittedPushTest.php
git commit -m "feat: notify all band owners on questionnaire submission with data-only push"
```

---

## Mobile tasks (repo `/home/eddie/github/tts_bandmate`, branch `feat/questionnaires-mobile-phase3`)

### Task 4: ResponseMeta model, mapping labels, apply repository calls + tests

**Files:**
- Modify: `lib/features/questionnaires/data/models/questionnaire_instance.dart` (ResponseMeta + `responseMeta` field)
- Modify: `lib/features/questionnaires/data/models/questionnaire_field.dart` (`mappingLabel`)
- Modify: `lib/core/network/api_endpoints.dart` (3 builders)
- Modify: `lib/features/questionnaires/data/questionnaires_repository.dart` (3 methods)
- Modify: `test/features/questionnaires/fake_questionnaires_repository.dart` (overrides + recorders)
- Test: `test/features/questionnaires/questionnaire_instance_models_test.dart` (extend)

**Interfaces:**
- Produces:
  - `ResponseMeta{int responseId, DateTime? appliedToEventAt, DateTime? updatedAt}` with `bool get isApplied` (`appliedToEventAt != null`) and `bool get needsReapply` (`isApplied && updatedAt != null && updatedAt.isAfter(appliedToEventAt)`)
  - `QuestionnaireInstance.responseMeta: Map<String, ResponseMeta>` (tolerant of PHP `[]`, keyed by field id string; copyWith passthrough)
  - `QuestionnaireField.mappingLabel: String?` (parsed from `mapping_label`)
  - Endpoints: `mobileBandQuestionnaireResponseApply(int bandId, int instanceId, int responseId)`, `mobileBandQuestionnaireInstanceApplyAll(int bandId, int instanceId)`, `mobileBandQuestionnaireInstanceAppendToNotes(int bandId, int instanceId)`
  - Repository: `Future<void> applyResponse(int bandId, int instanceId, int responseId)`; `Future<int> applyAllResponses(int bandId, int instanceId)` (returns `applied_count`); `Future<void> appendToNotes(int bandId, int instanceId)` — errors propagate (screen surfaces the 422 message)

- [ ] **Step 1: Failing tests**

Add to `questionnaire_instance_models_test.dart`:

```dart
    test('test_parses_response_meta_with_apply_states', () {
      final i = QuestionnaireInstance.fromJson({
        'id': 7,
        'name': 'x',
        'status': 'submitted',
        'recipient_name': 'r',
        'booking': {'id': 1, 'name': 'b'},
        'response_meta': {
          '21': {
            'response_id': 91,
            'applied_to_event_at': null,
            'updated_at': '2026-07-17T10:00:00+00:00',
          },
          '22': {
            'response_id': 92,
            'applied_to_event_at': '2026-07-17T09:00:00+00:00',
            'updated_at': '2026-07-17T10:00:00+00:00',
          },
          '23': {
            'response_id': 93,
            'applied_to_event_at': '2026-07-17T11:00:00+00:00',
            'updated_at': '2026-07-17T10:00:00+00:00',
          },
        },
      });
      expect(i.responseMeta['21']!.isApplied, false);
      expect(i.responseMeta['22']!.isApplied, true);
      expect(i.responseMeta['22']!.needsReapply, true); // updated after apply
      expect(i.responseMeta['23']!.needsReapply, false); // applied after update
    });

    test('test_tolerates_empty_list_response_meta', () {
      final i = QuestionnaireInstance.fromJson({
        'id': 1, 'name': 'x', 'status': 'sent',
        'recipient_name': 'r', 'booking': {'id': 1, 'name': 'b'},
        'response_meta': <dynamic>[],
      });
      expect(i.responseMeta, isEmpty);
    });
```

And a `mappingLabel` case in the existing `QuestionnaireField` group in `questionnaire_models_test.dart` (assert `mapping_label` parses and defaults null).

- [ ] **Step 2: Run to verify failure, then implement**

Models: add the `ResponseMeta` class (see Interfaces; follow `SongRef`'s style in the same file), the `responseMeta` field parsed with the same tolerance pattern as `responses` (`rawMeta is Map<String, dynamic> ? rawMeta.map((k, v) => MapEntry(k, ResponseMeta.fromJson(v as Map<String, dynamic>))) : const {}`), constructor default `const {}`, copyWith passthrough. `QuestionnaireField`: add `final String? mappingLabel;` parsed as `json['mapping_label'] as String?`.

Endpoints:

```dart
  static String mobileBandQuestionnaireResponseApply(
          int bandId, int instanceId, int responseId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/responses/$responseId/apply';
  static String mobileBandQuestionnaireInstanceApplyAll(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/apply-all';
  static String mobileBandQuestionnaireInstanceAppendToNotes(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/append-to-notes';
```

Repository:

```dart
  Future<void> applyResponse(int bandId, int instanceId, int responseId) async {
    await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireResponseApply(
          bandId, instanceId, responseId),
    );
  }

  Future<int> applyAllResponses(int bandId, int instanceId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstanceApplyAll(bandId, instanceId),
    );
    return ((response.data!['applied_count'] as num?) ?? 0).toInt();
  }

  Future<void> appendToNotes(int bandId, int instanceId) async {
    await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstanceAppendToNotes(
          bandId, instanceId),
    );
  }
```

Fake repository: add recorders `int? appliedResponseId; bool appliedAll = false; bool appendedToNotes = false; int applyAllResult = 0;` and the three overrides recording args (applyAllResponses returns `applyAllResult`).

- [ ] **Step 3: Green + commit**

```bash
flutter test test/features/questionnaires/ && flutter analyze
git add lib/features/questionnaires/data/models/questionnaire_instance.dart lib/features/questionnaires/data/models/questionnaire_field.dart lib/core/network/api_endpoints.dart lib/features/questionnaires/data/questionnaires_repository.dart test/features/questionnaires/fake_questionnaires_repository.dart test/features/questionnaires/questionnaire_instance_models_test.dart test/features/questionnaires/questionnaire_models_test.dart
git commit -m "feat(questionnaires): response metadata, mapping labels + apply repository calls"
```

### Task 5: questionnaire_submitted push type + deep link

**Files:**
- Modify: `lib/features/notifications/data/push_payload.dart`
- Modify: `lib/features/notifications/data/push_route.dart`
- Test: `test/notifications/push_payload_test.dart`, `test/notifications/push_route_test.dart` (extend)

**Interfaces:**
- Consumes: backend payload `{type: questionnaire_submitted, title, body, instanceId, questionnaireId?}` (Task 3).
- Produces: `PushType.questionnaireSubmitted`; `routeForPushData` → `/questionnaires/{questionnaireId}/instances/{instanceId}` (null when either id is missing/unparseable); `buildBackgroundNotification` renders it (data-only pushes must be shown by the background isolate, like chat).

- [ ] **Step 1: Failing tests**

`push_route_test.dart`:

```dart
  test('questionnaire_submitted routes to the instance responses screen', () {
    expect(
      routeForPushData({
        'type': 'questionnaire_submitted',
        'questionnaireId': '3',
        'instanceId': '9',
      }),
      '/questionnaires/3/instances/9',
    );
  });

  test('questionnaire_submitted without questionnaireId has no route', () {
    expect(
      routeForPushData({'type': 'questionnaire_submitted', 'instanceId': '9'}),
      isNull,
    );
  });
```

`push_payload_test.dart`:

```dart
    test('questionnaire_submitted parses type and renders in background', () {
      final spec = buildBackgroundNotification({
        'type': 'questionnaire_submitted',
        'title': 'Alice submitted the Wedding Intake',
        'body': 'Booking: Smith Wedding',
        'questionnaireId': '3',
        'instanceId': '9',
      });
      expect(spec, isNotNull);
      expect(spec!.title, 'Alice submitted the Wedding Intake');
      expect(spec.route, '/questionnaires/3/instances/9');
    });

    test('two questionnaire instances get distinct notification ids', () {
      PushPayload payload(String instanceId) => PushPayload.fromData({
            'type': 'questionnaire_submitted',
            'instanceId': instanceId,
          });
      expect(payload('1').notificationId,
          isNot(payload('2').notificationId));
    });
```

- [ ] **Step 2: Implement**

`push_payload.dart`:
- Enum: add `questionnaireSubmitted` before `unknown`.
- `_typeFromString`: `case 'questionnaire_submitted': return PushType.questionnaireSubmitted;`
- `PushPayload`: add `final String? questionnaireId;` and `final String? instanceId;` (constructor + `fromData` via the existing `str()` helper).
- `notificationId`: extend the entity fallback chain to `conversationId ?? rehearsalId ?? instanceId ?? ''`.
- `buildBackgroundNotification`: change the gate to render both data-only types:

```dart
  final payload = PushPayload.fromData(data);
  final rendersInBackground = payload.type == PushType.chatMessage ||
      payload.type == PushType.questionnaireSubmitted;
  if (!rendersInBackground) return null;
```

(update the function's doc comment: scope is now the data-only types — chat messages and questionnaire submissions).

`push_route.dart` — add before the rehearsal branch:

```dart
  if (type == 'questionnaire_submitted') {
    final questionnaireId =
        int.tryParse(data['questionnaireId']?.toString() ?? '');
    final instanceId = int.tryParse(data['instanceId']?.toString() ?? '');
    if (questionnaireId == null || instanceId == null) return null;
    return '/questionnaires/$questionnaireId/instances/$instanceId';
  }
```

- [ ] **Step 3: Green + commit**

```bash
flutter test test/notifications/ && flutter analyze && flutter test
git add lib/features/notifications/data/push_payload.dart lib/features/notifications/data/push_route.dart test/notifications/push_payload_test.dart test/notifications/push_route_test.dart
git commit -m "feat(questionnaires): questionnaire_submitted push type with deep link"
```

### Task 6: Apply UI on the responses screen

**Files:**
- Modify: `lib/features/questionnaires/screens/instance_responses_screen.dart`

**Interfaces:**
- Consumes: `ResponseMeta`/`responseMeta` + `QuestionnaireField.mappingLabel` (Task 4), repository apply methods via `questionnairesRepositoryProvider`, `instanceDetailProvider` invalidation.
- Produces: per-field apply row + Apply-all/Append-to-notes actions, owner-gated.

- [ ] **Step 1: Implement**

In `instance_responses_screen.dart`:

1. Pass apply context into `_FieldAnswer`: the parent already has `isOwner`, `bandId`, and `instance`. Change the field-list construction to:

```dart
                  for (final field in visibleFields)
                    _FieldAnswer(
                      field: field,
                      instance: instance,
                      canApply: isOwner,
                      onApply: (responseId) =>
                          _applyResponse(context, ref, bandId, responseId),
                    ),
```

2. Add to `InstanceResponsesScreen`:

```dart
  Future<void> _applyResponse(
      BuildContext context, WidgetRef ref, int bandId, int responseId) async {
    final key = (bandId: bandId, instanceId: instanceId);
    try {
      await ref
          .read(questionnairesRepositoryProvider)
          .applyResponse(bandId, instanceId, responseId);
      ref.invalidate(instanceDetailProvider(key));
    } on DioException catch (e) {
      if (!context.mounted) return;
      _info(context, 'Apply failed',
          (e.response?.data is Map && e.response!.data['message'] is String)
              ? e.response!.data['message'] as String
              : 'Please try again.');
    } catch (_) {
      if (context.mounted) _info(context, 'Apply failed', 'Please try again.');
    }
  }
```

(add `import 'package:dio/dio.dart';` and `import '../providers/questionnaires_provider.dart';`.)

3. Extend `_showActions` with two actions inserted before the destructive Delete (using the already-in-scope `detailKey` and `instance`):

```dart
          if (instance.fields.any((f) =>
              f.mappingTarget != null &&
              instance.responseMeta.containsKey('${f.id}') &&
              !instance.responseMeta['${f.id}']!.isApplied))
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                try {
                  final count = await ref
                      .read(questionnairesRepositoryProvider)
                      .applyAllResponses(bandId, instance.id);
                  ref.invalidate(instanceDetailProvider(detailKey));
                  if (context.mounted) {
                    _info(context, 'Applied',
                        'Applied $count answer${count == 1 ? '' : 's'} to the event.');
                  }
                } catch (_) {
                  if (context.mounted) {
                    _info(context, 'Apply all failed', 'Please try again.');
                  }
                }
              },
              child: const Text('Apply all pending to event'),
            ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              final confirmed = await showCupertinoDialog<bool>(
                context: context,
                builder: (dialogContext) => CupertinoAlertDialog(
                  title: const Text('Append to event notes?'),
                  content: const Text(
                      'All answers will be appended to the event\'s notes.'),
                  actions: [
                    CupertinoDialogAction(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    CupertinoDialogAction(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Append'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              try {
                await ref
                    .read(questionnairesRepositoryProvider)
                    .appendToNotes(bandId, instance.id);
                if (context.mounted) {
                  _info(context, 'Done', 'Answers appended to event notes.');
                }
              } catch (_) {
                if (context.mounted) {
                  _info(context, 'Append failed', 'Please try again.');
                }
              }
            },
            child: const Text('Append answers to event notes'),
          ),
```

(`_showActions` needs `bandId` — it already receives it as a parameter.)

4. Extend `_FieldAnswer`:

```dart
class _FieldAnswer extends StatelessWidget {
  const _FieldAnswer({
    required this.field,
    required this.instance,
    required this.canApply,
    required this.onApply,
  });

  final QuestionnaireField field;
  final QuestionnaireInstance instance;
  final bool canApply;
  final void Function(int responseId) onApply;
```

and in `build`, after `_answer(context, raw)` inside the Column, add the mapping row:

```dart
          if (field.mappingTarget != null) _mappingRow(context),
```

with:

```dart
  Widget _mappingRow(BuildContext context) {
    final meta = instance.responseMeta['${field.id}'];
    final label = field.mappingLabel ?? field.mappingTarget!;

    // No answer yet: nothing to apply, just show where it would map.
    if (meta == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text('Maps to $label',
            style: TextStyle(color: context.secondaryText, fontSize: 12)),
      );
    }

    final (stateText, showButton) = meta.needsReapply
        ? ('Applied — answer changed since', true)
        : meta.isApplied
            ? ('Applied ✓', false)
            : ('Not applied', true);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label · $stateText',
              style: TextStyle(
                color: meta.isApplied && !meta.needsReapply
                    ? CupertinoColors.systemGreen.resolveFrom(context)
                    : context.secondaryText,
                fontSize: 12,
              ),
            ),
          ),
          if (canApply && showButton)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: () => onApply(meta.responseId),
              child: Text(meta.needsReapply ? 'Re-apply' : 'Apply',
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
```

(If `CupertinoButton.minSize: 0` trips the analyzer on this Flutter version, use `minSize: 24` or omit — keep the button compact.)

- [ ] **Step 2: Analyze + test + commit**

```bash
flutter analyze && flutter test
git add lib/features/questionnaires/screens/instance_responses_screen.dart
git commit -m "feat(questionnaires): apply-to-event actions on responses screen"
```

### Task 7: Version bump, full verification, PRs

- [ ] **Step 1:** Bump `pubspec.yaml` `version: 1.16.0+25` → `version: 1.17.0+26`; `flutter analyze && flutter test` (baseline + all green); commit `chore: bump version to 1.17.0+26`.
- [ ] **Step 2:** Backend: `docker compose exec -T app php artisan test --filter=Questionnaire` and `--filter=Push` — all green.
- [ ] **Step 3:** On-device (run-on-device skill): open a submitted instance → per-field Apply / Re-apply states → Apply all → Append to notes (verify event notes on web) → submit from the web portal and verify the push arrives on the locked phone and deep-links to the responses screen on tap. Note: debug device runs have realtime off, but push goes through FCM (works on the physical device against local backend only if FCM keys are configured — otherwise verify push on staging after merge and note it).
- [ ] **Step 4:** PRs after user confirmation: TTS draft → staging; mobile → main. Copilot wave on both.

---

## Self-review notes

- Spec coverage (Phase 3): apply endpoints with `write:events` requirement → Tasks 1–2; per-field Apply with not-applied / applied ✓ / needs-re-apply (`updated_at > applied_to_event_at`) → Tasks 1+4+6; Apply-all-pending + Append-to-notes with confirm → Tasks 2+6; push to ALL owner users (fixing first-owner-only email too) with data-only payload + deep link → Tasks 3+5. Owner-only UI, backend enforces real permissions.
- Type consistency: `ResponseMeta.responseId` ↔ backend `response_id`; apply route param order (bandId, instanceId, responseId) consistent across endpoints/repository/screen; push keys `questionnaireId`/`instanceId` consistent between Task 3's payload and Task 5's parsers.
- Judgment calls: apply-all returns a count instead of web's redirect flash (mobile shows it in a dialog); `mapping_label` computed server-side per instance field so the client needs no catalog lookup on the responses screen; unanswered mapped fields show a passive "Maps to …" hint instead of a disabled button.
