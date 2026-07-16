# Questionnaires Mobile — Phase 2 (Sending, Logs, Booking Integration, Realtime) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship questionnaire sending, sent-instance logs, a responses viewer, booking-screen integration, and realtime invalidation on mobile — extending the Phase 1 surfaces in both repos.

**Architecture:** Backend adds a thin `Api\Mobile\QuestionnaireInstancesController` over the existing `QuestionnaireSnapshotService` + `SendQuestionnaireRequest` (reused verbatim), with response decoding/song-lookup extracted into a shared `QuestionnaireResponsePresenter` used by portal, web, and mobile. Questionnaire models join the thin `BandDataChanged` broadcast. Mobile adds an instances data layer (models → repository → Riverpod family providers), a questionnaire detail screen (summary + send + logs), a responses screen, send sheets for both directions (questionnaire→booking and booking→template), a booking-detail Questionnaires section, and registry entries in the realtime invalidator.

**Tech Stack:** Laravel 10 (Sanctum, queued Notifications, Pusher broadcasts), Flutter/Dart (Riverpod v2, GoRouter, Dio, Cupertino, intl).

**Spec:** `docs/superpowers/specs/2026-07-15-questionnaires-mobile-design.md` (Phase 2 section)

## Global Constraints

- TTS repo: never run `php`/`artisan`/`composer` on the host — always `docker compose exec -T app …` from `/home/eddie/github/TTS`.
- TTS PRs target `staging`; mobile PRs target `main`.
- Backend branch: `feat/mobile-questionnaire-instances` (off `staging`, created in Task 1). Mobile branch: `feat/questionnaires-mobile-phase2` (already exists, off main which includes Phase 1).
- Mobile: Cupertino widgets only; hand-written `fromJson`; `context.secondaryText` (never raw `CupertinoColors.secondaryLabel` in a `color:`); test naming `test_<behavior>`; `addTearDown(container.dispose)`; force initial build before mutations.
- `flutter analyze` baseline: 3 known pre-existing issues (secure_storage deprecation + 2 main.dart experimental) — every task adds zero new.
- Mobile repo working tree may contain unrelated `.claude/agent-memory` and screenshot files — commit with explicit `git add <paths>` only, NEVER `git add -A` (both repos).
- Wire contract (Phase 2, frozen):
  - Instance summary row: `{id, name, status, sent_at, submitted_at, recipient_name, booking: {id, name}, questionnaire_id}` — dates ISO 8601, mobile formats client-side.
  - Instance detail adds: `description, first_opened_at, locked_at, fields: [<instance fields, position-ordered, same keys as template fields>], responses: {<instance_field_id>: <decoded value>}, song_lookup: {<song_id>: {title, artist}}`.
  - Instance statuses: `sent | in_progress | submitted | locked` (`QuestionnaireInstances::STATUS_*`).
  - Eligible bookings: `{bookings: [{id, name, date, already_sent, contacts: [{id, name, is_primary, can_login}]}]}`.
  - Booking section: `{instances: [<summary rows>], available_questionnaires: [{id, name}]}`.
  - Send: `POST` body `{questionnaire_id, recipient_contact_id}` → 201 `{instance: <summary>}`; validation errors 422 (archived template, foreign contact, contact without portal access — from the reused `SendQuestionnaireRequest`).
  - Realtime wire model names (from `Str::snake(class_basename())`): `questionnaires`, `questionnaire_instances`, `questionnaire_responses` on `private-band.{id}` event `band.data-changed`.
- Doc comments: no raw angle brackets (`unintended_html_in_doc_comment`) — use backtick code spans.
- Commit after every green task with the standard Claude trailers.

---

## Backend tasks (repo `/home/eddie/github/TTS`)

### Task 1: Branch + extract QuestionnaireResponsePresenter

**Files:**
- Create: `/home/eddie/github/TTS/app/Services/QuestionnaireResponsePresenter.php`
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Contact/PortalQuestionnaireController.php` (private `decodeValue`/`encodeValue`, lines ~103-125, and their call sites in `show()`/`saveResponse()`/`submit()`)
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/QuestionnairesController.php` (private `buildSongLookupForInstances`, lines ~249-287, call site in `show()`)
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/BookingsController.php` (its duplicated song-lookup helper + call site in `show()`)
- Test: existing suites (`--filter=Questionnaire` + booking show tests) — pure refactor, no new tests

**Interfaces:**
- Consumes: nothing new.
- Produces (Tasks 3–4 and the three web controllers call these):
  - `decode(?string $value): mixed` — null/'' → null; JSON array → array; else raw string
  - `encode(mixed $value, string $type): ?string` — arrays JSON-encoded for `multi_select|checkbox_group|song_picker`, scalars stringified
  - `songLookup(iterable $instances, int $bandId): array` — `{songId: {title, artist}}` incl. `(removed song #N)` placeholders

- [ ] **Step 1: Create the branch and get a green baseline**

```bash
cd /home/eddie/github/TTS && git checkout staging && git pull && git checkout -b feat/mobile-questionnaire-instances
docker compose exec -T app php artisan test --filter=Questionnaire
```
Expected: PASS (record the count — post-Phase-1 it is 112).

- [ ] **Step 2: Create the presenter by MOVING the helpers**

`app/Services/QuestionnaireResponsePresenter.php` skeleton — move the method bodies **verbatim** (`PortalQuestionnaireController::decodeValue` → `decode`, `::encodeValue` → `encode`, `QuestionnairesController::buildSongLookupForInstances` → `songLookup`); only visibility changes to `public`:

```php
<?php

namespace App\Services;

class QuestionnaireResponsePresenter
{
    /** Decode a stored response value: JSON arrays for multi-valued types, raw string otherwise. */
    public function decode(?string $value): mixed
    {
        // moved body of PortalQuestionnaireController::decodeValue()
    }

    /** Encode a submitted response value for storage. */
    public function encode(mixed $value, string $type): ?string
    {
        // moved body of PortalQuestionnaireController::encodeValue()
    }

    /** Song id to title/artist lookup across instances' song_picker responses. */
    public function songLookup(iterable $instances, int $bandId): array
    {
        // moved body of QuestionnairesController::buildSongLookupForInstances()
    }
}
```

- [ ] **Step 3: Refactor the three controllers to delegate**

- `PortalQuestionnaireController`: constructor-inject `QuestionnaireResponsePresenter $presenter` (or add to the existing constructor); replace every `$this->decodeValue(` with `$this->presenter->decode(` and `$this->encodeValue(` with `$this->presenter->encode(`; delete the two private methods.
- `QuestionnairesController` (web): replace `$this->buildSongLookupForInstances($rawInstances, $band->id)` with `$this->presenter->songLookup($rawInstances, $band->id)` (inject the presenter); delete the private method.
- `BookingsController`: same replacement for its duplicated song-lookup helper (find it with `grep -n "buildSongLookup\|removed song" app/Http/Controllers/BookingsController.php`); delete the duplicate.

If `BookingsController`'s copy differs textually from the questionnaire controller's, keep the `QuestionnairesController` version as canonical (they are behavior-identical: same `(removed song #N)` placeholder contract) and note any diff in your report.

- [ ] **Step 4: Run the guarding suites**

```bash
docker compose exec -T app php artisan test --filter=Questionnaire
docker compose exec -T app php artisan test --filter=Booking
```
Expected: PASS with counts identical to before the refactor.

- [ ] **Step 5: Commit**

```bash
git add app/Services/QuestionnaireResponsePresenter.php app/Http/Controllers/Contact/PortalQuestionnaireController.php app/Http/Controllers/QuestionnairesController.php app/Http/Controllers/BookingsController.php
git commit -m "refactor: extract QuestionnaireResponsePresenter (decode/encode/song lookup)"
```

### Task 2: Broadcast questionnaire changes (BandDataChanged)

**Files:**
- Modify: `/home/eddie/github/TTS/app/Models/Questionnaires.php`
- Modify: `/home/eddie/github/TTS/app/Models/QuestionnaireInstances.php`
- Modify: `/home/eddie/github/TTS/app/Models/QuestionnaireResponses.php`
- Test: `/home/eddie/github/TTS/tests/Feature/Questionnaires/QuestionnaireBroadcastTest.php` (create)

**Interfaces:**
- Consumes: `App\Models\Traits\BroadcastsBandChanges` (existing trait: boots created/updated/deleted hooks, wire name `Str::snake(class_basename())`, `broadcastBandId()` override for indirect band).
- Produces: `band.data-changed` broadcasts with model names `questionnaires`, `questionnaire_instances`, `questionnaire_responses` — Task 11 (mobile registry) depends on these exact names.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature\Questionnaires;

use App\Events\BandDataChanged;
use App\Models\Bands;
use App\Models\Bookings;
use App\Models\Contacts;
use App\Models\QuestionnaireInstances;
use App\Models\Questionnaires;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Tests\TestCase;

class QuestionnaireBroadcastTest extends TestCase
{
    use RefreshDatabase;

    private Bands $band;
    private Bookings $booking;
    private Contacts $contact;
    private User $owner;

    protected function setUp(): void
    {
        parent::setUp();
        $this->band = Bands::factory()->create();
        $this->owner = User::factory()->create();
        $this->band->owners()->create(['user_id' => $this->owner->id]);
        $this->booking = Bookings::factory()->create(['band_id' => $this->band->id]);
        $this->contact = Contacts::factory()->create(['band_id' => $this->band->id, 'can_login' => true]);
    }

    private function makeInstance(): QuestionnaireInstances
    {
        $template = Questionnaires::factory()->create(['band_id' => $this->band->id]);

        return QuestionnaireInstances::create([
            'questionnaire_id' => $template->id,
            'booking_id' => $this->booking->id,
            'recipient_contact_id' => $this->contact->id,
            'sent_by_user_id' => $this->owner->id,
            'name' => $template->name,
            'description' => '',
            'status' => QuestionnaireInstances::STATUS_SENT,
            'sent_at' => now(),
        ]);
    }

    public function test_questionnaire_create_broadcasts(): void
    {
        Event::fake([BandDataChanged::class]);

        $q = Questionnaires::factory()->create(['band_id' => $this->band->id]);

        Event::assertDispatched(BandDataChanged::class, fn (BandDataChanged $e) =>
            $e->bandId === $this->band->id
            && $e->model === 'questionnaires'
            && $e->id === $q->id
            && $e->action === 'created');
    }

    public function test_instance_status_change_broadcasts_with_booking_band(): void
    {
        $instance = $this->makeInstance();
        Event::fake([BandDataChanged::class]);

        $instance->update(['status' => QuestionnaireInstances::STATUS_LOCKED, 'locked_at' => now()]);

        Event::assertDispatched(BandDataChanged::class, fn (BandDataChanged $e) =>
            $e->bandId === $this->band->id
            && $e->model === 'questionnaire_instances'
            && $e->id === $instance->id
            && $e->action === 'updated');
    }

    public function test_response_save_broadcasts_with_instance_band(): void
    {
        $instance = $this->makeInstance();
        $field = $instance->fields()->create([
            'type' => 'short_text', 'label' => 'Name', 'position' => 10, 'required' => false,
            'source_field_id' => 0,
        ]);
        Event::fake([BandDataChanged::class]);

        $response = $instance->responses()->create([
            'instance_field_id' => $field->id,
            'value' => 'hello',
        ]);

        Event::assertDispatched(BandDataChanged::class, fn (BandDataChanged $e) =>
            $e->bandId === $this->band->id
            && $e->model === 'questionnaire_responses'
            && $e->id === $response->id
            && $e->action === 'created');
    }
}
```

(If `Questionnaires::factory()` doesn't exist, check `database/factories/` — Phase 1's web tests used `Questionnaires::factory()` in `SendQuestionnaireTest`, so it exists. If `source_field_id => 0` violates a constraint, create a template field first and use its id.)

- [ ] **Step 2: Run to verify it fails**

Run: `docker compose exec -T app php artisan test --filter=QuestionnaireBroadcastTest`
Expected: FAIL — `BandDataChanged` never dispatched.

- [ ] **Step 3: Wire the trait**

`Questionnaires.php` — add to imports and class body (direct `band_id`, no overrides needed):

```php
use App\Models\Traits\BroadcastsBandChanges;
// inside class:
    use BroadcastsBandChanges;
```

`QuestionnaireInstances.php` — trait + indirect band override:

```php
    use BroadcastsBandChanges;

    protected function broadcastBandId(): ?int
    {
        $bandId = $this->booking?->band_id;

        return $bandId ? (int) $bandId : null;
    }
```

`QuestionnaireResponses.php` — trait + band via instance's booking:

```php
    use BroadcastsBandChanges;

    protected function broadcastBandId(): ?int
    {
        $bandId = $this->instance?->booking?->band_id;

        return $bandId ? (int) $bandId : null;
    }
```

- [ ] **Step 4: Run to verify it passes + regression**

```bash
docker compose exec -T app php artisan test --filter=QuestionnaireBroadcastTest
docker compose exec -T app php artisan test --filter=Questionnaire
```
Expected: 3/3 new PASS; full questionnaire suite PASS (the trait's try/catch means broadcasts can never break writes; watch for any test that asserts exact event counts).

- [ ] **Step 5: Commit**

```bash
git add app/Models/Questionnaires.php app/Models/QuestionnaireInstances.php app/Models/QuestionnaireResponses.php tests/Feature/Questionnaires/QuestionnaireBroadcastTest.php
git commit -m "feat: broadcast BandDataChanged for questionnaire models"
```

### Task 3: Mobile read endpoints (instances, eligible bookings, booking section, instance detail)

**Files:**
- Create: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/QuestionnaireInstancesController.php`
- Modify: `/home/eddie/github/TTS/routes/api.php` (after the Phase 1 questionnaires groups, ~line 410)
- Modify: `/home/eddie/github/TTS/app/Services/Mobile/BookingFormatter.php` (`formatContacts`, ~line 108: add `can_login`)
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/QuestionnaireInstanceMobileTest.php` (create)

**Interfaces:**
- Consumes: `QuestionnaireResponsePresenter` (Task 1), `QuestionnaireInstances` model relations, `Bands::questionnaires()`/`bookings()` relations, `mobile.band` middleware.
- Produces (mobile read contract):
  - `GET /api/mobile/bands/{band}/questionnaires/{questionnaire}/instances` → 200 `{"instances": [<summary>]}` ordered by `sent_at` desc
  - `GET .../questionnaires/{questionnaire}/eligible-bookings` → 200 `{"bookings": [{id, name, date, already_sent, contacts: [{id, name, is_primary, can_login}]}]}` (future-dated events only)
  - `GET .../bookings/{booking}/questionnaire-instances` → 200 `{"instances": [<summary>], "available_questionnaires": [{id, name}]}` (non-archived templates)
  - `GET .../questionnaire-instances/{instance}` → 200 `{"instance": <detail>}` (fields position-ordered; responses decoded and keyed by instance_field_id; song_lookup)
  - Cross-band anything → 404. Also `private summary()` / `private detail()` helpers Task 4 reuses.

- [ ] **Step 1: Write the failing tests**

`tests/Feature/Api/Mobile/QuestionnaireInstanceMobileTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\BandMembers;
use App\Models\BandOwners;
use App\Models\Bands;
use App\Models\Bookings;
use App\Models\Contacts;
use App\Models\QuestionnaireInstances;
use App\Models\Questionnaires;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class QuestionnaireInstanceMobileTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;
    private User $member;
    private Bands $band;
    private Bookings $booking;
    private Contacts $contact;
    private Questionnaires $template;
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

        setPermissionsTeamId($this->band->id);
        $this->member->assignRole('band-member');

        $this->booking = Bookings::factory()->create(['band_id' => $this->band->id]);
        $this->booking->events()->create([
            'date' => now()->addMonth()->toDateString(),
            'venue_name' => 'Test Venue',
        ]);
        $this->contact = Contacts::factory()->create(['band_id' => $this->band->id, 'can_login' => true]);
        $this->booking->contacts()->attach($this->contact, ['is_primary' => true]);
        $this->template = Questionnaires::factory()->create(['band_id' => $this->band->id]);

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

    private function makeInstance(array $attrs = []): QuestionnaireInstances
    {
        return QuestionnaireInstances::create(array_merge([
            'questionnaire_id' => $this->template->id,
            'booking_id' => $this->booking->id,
            'recipient_contact_id' => $this->contact->id,
            'sent_by_user_id' => $this->owner->id,
            'name' => $this->template->name,
            'description' => '',
            'status' => QuestionnaireInstances::STATUS_SENT,
            'sent_at' => now(),
        ], $attrs));
    }

    public function test_member_can_list_instances_for_questionnaire(): void
    {
        $this->makeInstance();

        $this->withHeaders($this->asMember())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$this->template->id}/instances")
            ->assertOk()
            ->assertJsonCount(1, 'instances')
            ->assertJsonPath('instances.0.status', 'sent')
            ->assertJsonPath('instances.0.recipient_name', $this->contact->name)
            ->assertJsonPath('instances.0.booking.id', $this->booking->id);
    }

    public function test_eligible_bookings_flags_already_sent_and_portal_access(): void
    {
        $this->makeInstance();
        $noPortal = Contacts::factory()->create(['band_id' => $this->band->id, 'can_login' => false]);
        $this->booking->contacts()->attach($noPortal, ['is_primary' => false]);

        $response = $this->withHeaders($this->asOwner())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$this->template->id}/eligible-bookings")
            ->assertOk()
            ->assertJsonPath('bookings.0.already_sent', true);

        $contacts = collect($response->json('bookings.0.contacts'));
        $this->assertTrue($contacts->firstWhere('id', $this->contact->id)['can_login']);
        $this->assertFalse($contacts->firstWhere('id', $noPortal->id)['can_login']);
    }

    public function test_eligible_bookings_excludes_past_only_bookings(): void
    {
        $past = Bookings::factory()->create(['band_id' => $this->band->id]);
        $past->events()->create([
            'date' => now()->subMonth()->toDateString(),
            'venue_name' => 'Past Venue',
        ]);

        $response = $this->withHeaders($this->asOwner())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaires/{$this->template->id}/eligible-bookings")
            ->assertOk();

        $ids = collect($response->json('bookings'))->pluck('id');
        $this->assertTrue($ids->contains($this->booking->id));
        $this->assertFalse($ids->contains($past->id));
    }

    public function test_booking_section_returns_instances_and_available_templates(): void
    {
        $this->makeInstance();
        Questionnaires::factory()->create(['band_id' => $this->band->id, 'archived_at' => now()]);

        $this->withHeaders($this->asMember())
            ->getJson("/api/mobile/bands/{$this->band->id}/bookings/{$this->booking->id}/questionnaire-instances")
            ->assertOk()
            ->assertJsonCount(1, 'instances')
            ->assertJsonCount(1, 'available_questionnaires')
            ->assertJsonPath('available_questionnaires.0.id', $this->template->id);
    }

    public function test_instance_detail_decodes_responses_and_resolves_songs(): void
    {
        $instance = $this->makeInstance();
        $textField = $instance->fields()->create([
            'type' => 'short_text', 'label' => 'Name', 'position' => 10,
            'required' => false, 'source_field_id' => 0,
        ]);
        $multiField = $instance->fields()->create([
            'type' => 'multi_select', 'label' => 'Extras', 'position' => 20,
            'required' => false, 'source_field_id' => 0,
            'settings' => ['options' => [['label' => 'A', 'value' => 'a'], ['label' => 'B', 'value' => 'b']]],
        ]);
        $songField = $instance->fields()->create([
            'type' => 'song_picker', 'label' => 'Must play', 'position' => 30,
            'required' => false, 'source_field_id' => 0,
            'settings' => ['purpose' => 'must_play'],
        ]);
        $song = \App\Models\Song::factory()->create(['band_id' => $this->band->id]);
        $instance->responses()->create(['instance_field_id' => $textField->id, 'value' => 'Alice']);
        $instance->responses()->create(['instance_field_id' => $multiField->id, 'value' => json_encode(['a', 'b'])]);
        $instance->responses()->create(['instance_field_id' => $songField->id, 'value' => json_encode([$song->id])]);

        $this->withHeaders($this->asMember())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}")
            ->assertOk()
            ->assertJsonPath('instance.fields.0.label', 'Name')
            ->assertJsonPath("instance.responses.{$textField->id}", 'Alice')
            ->assertJsonPath("instance.responses.{$multiField->id}", ['a', 'b'])
            ->assertJsonPath("instance.song_lookup.{$song->id}.title", $song->title);
    }

    public function test_cross_band_instance_is_404(): void
    {
        $otherBand = Bands::factory()->create();
        $otherBooking = Bookings::factory()->create(['band_id' => $otherBand->id]);
        $foreign = $this->makeInstance(['booking_id' => $otherBooking->id]);

        $this->withHeaders($this->asOwner())
            ->getJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$foreign->id}")
            ->assertStatus(404);
    }
}
```

(Adapt factory invocations if `Bookings->events()->create` needs different columns — copy from existing mobile bookings tests; if `Song::factory()` needs extra attrs, copy from song tests.)

- [ ] **Step 2: Run to verify they fail**

Run: `docker compose exec -T app php artisan test --filter=QuestionnaireInstanceMobileTest`
Expected: FAIL — 404s (routes missing).

- [ ] **Step 3: Add routes**

In `routes/api.php`, after the Phase 1 questionnaires write group:

```php
// Questionnaire instances (sending/logs)
Route::middleware('mobile.band:read:questionnaires')->group(function () {
    Route::get('/bands/{band}/questionnaires/{questionnaire}/instances', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'instancesForQuestionnaire'])->name('mobile.questionnaires.instances');
    Route::get('/bands/{band}/questionnaires/{questionnaire}/eligible-bookings', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'eligibleBookings'])->name('mobile.questionnaires.eligible-bookings');
    Route::get('/bands/{band}/bookings/{booking}/questionnaire-instances', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'forBooking'])->name('mobile.bookings.questionnaire-instances');
    Route::get('/bands/{band}/questionnaire-instances/{instance}', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'show'])->name('mobile.questionnaire-instances.show');
});
```

- [ ] **Step 4: Create the controller (read half)**

```php
<?php

namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Models\Bands;
use App\Models\Bookings;
use App\Models\QuestionnaireInstances;
use App\Models\Questionnaires;
use App\Services\QuestionnaireResponsePresenter;
use Illuminate\Http\JsonResponse;

/** Authorization is handled at the route layer via the mobile.band middleware. */
class QuestionnaireInstancesController extends Controller
{
    public function __construct(
        private QuestionnaireResponsePresenter $presenter,
    ) {
    }

    public function instancesForQuestionnaire(Bands $band, Questionnaires $questionnaire): JsonResponse
    {
        abort_if($questionnaire->band_id !== $band->id, 404);

        $instances = $questionnaire->instances()
            ->with(['recipientContact:id,name', 'booking:id,name,band_id'])
            ->orderByDesc('sent_at')
            ->get()
            ->map(fn (QuestionnaireInstances $i) => $this->summary($i));

        return response()->json(['instances' => $instances]);
    }

    public function eligibleBookings(Bands $band, Questionnaires $questionnaire): JsonResponse
    {
        abort_if($questionnaire->band_id !== $band->id, 404);

        $sentBookingIds = $questionnaire->instances()->pluck('booking_id')->all();

        $bookings = $band->bookings()
            ->with(['contacts:id,name,can_login', 'events:id,eventable_id,eventable_type,date,venue_name'])
            ->whereHas('events', fn ($q) => $q->whereDate('date', '>=', today()))
            ->get(['id', 'name', 'band_id'])
            ->map(fn (Bookings $b) => [
                'id' => $b->id,
                'name' => $b->name,
                'date' => $b->event_dates,
                'already_sent' => in_array($b->id, $sentBookingIds, true),
                'contacts' => $b->contacts->map(fn ($c) => [
                    'id' => $c->id,
                    'name' => $c->name,
                    'is_primary' => (bool) ($c->pivot->is_primary ?? false),
                    'can_login' => (bool) $c->can_login,
                ])->values(),
            ]);

        return response()->json(['bookings' => $bookings]);
    }

    public function forBooking(Bands $band, Bookings $booking): JsonResponse
    {
        abort_if($booking->band_id !== $band->id, 404);

        $instances = $booking->questionnaireInstances()
            ->with(['recipientContact:id,name', 'booking:id,name,band_id'])
            ->orderByDesc('sent_at')
            ->get()
            ->map(fn (QuestionnaireInstances $i) => $this->summary($i));

        $available = $band->questionnaires()
            ->whereNull('archived_at')
            ->orderBy('name')
            ->get(['id', 'name'])
            ->map(fn ($q) => ['id' => $q->id, 'name' => $q->name]);

        return response()->json([
            'instances' => $instances,
            'available_questionnaires' => $available,
        ]);
    }

    public function show(Bands $band, QuestionnaireInstances $instance): JsonResponse
    {
        $this->ensureBelongsToBand($band, $instance);
        $instance->load([
            'recipientContact:id,name',
            'booking:id,name,band_id',
            'fields',
            'responses',
        ]);

        return response()->json(['instance' => $this->detail($instance, $band)]);
    }

    private function ensureBelongsToBand(Bands $band, QuestionnaireInstances $instance): void
    {
        abort_if($instance->booking?->band_id !== $band->id, 404);
    }

    private function summary(QuestionnaireInstances $i): array
    {
        return [
            'id' => $i->id,
            'name' => $i->name,
            'status' => $i->status,
            'sent_at' => $i->sent_at?->toIso8601String(),
            'submitted_at' => $i->submitted_at?->toIso8601String(),
            'recipient_name' => $i->recipientContact->name ?? 'Unknown',
            'booking' => [
                'id' => $i->booking->id,
                'name' => $i->booking->name,
            ],
            'questionnaire_id' => $i->questionnaire_id,
        ];
    }

    private function detail(QuestionnaireInstances $i, Bands $band): array
    {
        return $this->summary($i) + [
            'description' => $i->description,
            'first_opened_at' => $i->first_opened_at?->toIso8601String(),
            'locked_at' => $i->locked_at?->toIso8601String(),
            'fields' => $i->fields->map(fn ($f) => [
                'id' => $f->id,
                'type' => $f->type,
                'label' => $f->label,
                'help_text' => $f->help_text,
                'required' => (bool) $f->required,
                'position' => $f->position,
                'settings' => $f->settings,
                'visibility_rule' => $f->visibility_rule,
            ])->values()->all(),
            'responses' => $i->responses->mapWithKeys(fn ($r) => [
                $r->instance_field_id => $this->presenter->decode($r->value),
            ]),
            'song_lookup' => $this->presenter->songLookup([$i], $band->id),
        ];
    }
}
```

(The `fields()` relation is already position-ordered on the model. `ensureBelongsToBand` reads `booking?->band_id` — instances always have a booking, but the null-safe keeps a dangling instance a 404 rather than a 500.)

- [ ] **Step 5: Add `can_login` to the booking formatter**

In `BookingFormatter::formatContacts`, add to the mapped array:

```php
            'can_login'  => (bool) $c->can_login,
```

- [ ] **Step 6: Run to green + regression**

```bash
docker compose exec -T app php artisan test --filter=QuestionnaireInstanceMobileTest
docker compose exec -T app php artisan test --filter=Questionnaire
docker compose exec -T app php artisan test --filter=BookingMobile
```
Expected: 6/6 new PASS; questionnaire suite PASS; mobile booking tests PASS (the formatter gained a key — additive, but confirm no strict-shape assertions break).

- [ ] **Step 7: Commit**

```bash
git add app/Http/Controllers/Api/Mobile/QuestionnaireInstancesController.php routes/api.php app/Services/Mobile/BookingFormatter.php tests/Feature/Api/Mobile/QuestionnaireInstanceMobileTest.php
git commit -m "feat(mobile): questionnaire instance read endpoints + contact can_login"
```

### Task 4: Mobile write endpoints (send, resend, lock, unlock, destroy)

**Files:**
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/QuestionnaireInstancesController.php`
- Modify: `/home/eddie/github/TTS/routes/api.php`
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/QuestionnaireInstanceMobileTest.php`

**Interfaces:**
- Consumes: `QuestionnaireSnapshotService::snapshot(Questionnaires, Bookings, Contacts, User)` (existing), `SendQuestionnaireRequest` (existing web FormRequest, reused verbatim — its `authorize()` reads `route('band')`, its rules read `route('booking')`, and `withValidator` rejects contacts without `can_login`), `QuestionnaireSent` notification (existing).
- Produces (mobile write contract):
  - `POST /bands/{band}/bookings/{booking}/questionnaires` `{questionnaire_id, recipient_contact_id}` → 201 `{"instance": <summary>}`; 422 on archived template / foreign contact / no portal access
  - `POST /bands/{band}/questionnaire-instances/{instance}/resend` → 200 `{"instance": <summary>}` (re-notifies, no new instance)
  - `POST .../lock` → 200 `{"instance": <summary>}` with status `locked`
  - `POST .../unlock` → 200 `{"instance": <summary>}` with status recomputed (submitted → `submitted`; has responses → `in_progress`; else `sent`)
  - `DELETE /bands/{band}/questionnaire-instances/{instance}` → 200 `{"message": "Questionnaire instance deleted"}` (soft delete)

- [ ] **Step 1: Add the failing tests**

Append inside `QuestionnaireInstanceMobileTest`:

```php
    public function test_owner_can_send_questionnaire(): void
    {
        \Illuminate\Support\Facades\Notification::fake();

        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/bookings/{$this->booking->id}/questionnaires", [
                'questionnaire_id' => $this->template->id,
                'recipient_contact_id' => $this->contact->id,
            ])
            ->assertStatus(201)
            ->assertJsonPath('instance.status', 'sent')
            ->assertJsonPath('instance.recipient_name', $this->contact->name);

        $this->assertDatabaseHas('questionnaire_instances', [
            'questionnaire_id' => $this->template->id,
            'booking_id' => $this->booking->id,
            'status' => 'sent',
        ]);

        \Illuminate\Support\Facades\Notification::assertSentTo(
            $this->contact, \App\Notifications\QuestionnaireSent::class);
    }

    public function test_send_rejects_contact_without_portal_access(): void
    {
        $noPortal = Contacts::factory()->create(['band_id' => $this->band->id, 'can_login' => false]);
        $this->booking->contacts()->attach($noPortal, ['is_primary' => false]);

        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/bookings/{$this->booking->id}/questionnaires", [
                'questionnaire_id' => $this->template->id,
                'recipient_contact_id' => $noPortal->id,
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('recipient_contact_id');
    }

    public function test_send_rejects_archived_template(): void
    {
        $this->template->update(['archived_at' => now()]);

        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/bookings/{$this->booking->id}/questionnaires", [
                'questionnaire_id' => $this->template->id,
                'recipient_contact_id' => $this->contact->id,
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('questionnaire_id');
    }

    public function test_member_cannot_send(): void
    {
        $this->withHeaders($this->asMember())
            ->postJson("/api/mobile/bands/{$this->band->id}/bookings/{$this->booking->id}/questionnaires", [
                'questionnaire_id' => $this->template->id,
                'recipient_contact_id' => $this->contact->id,
            ])
            ->assertStatus(403);
    }

    public function test_resend_renotifies_without_new_instance(): void
    {
        $instance = $this->makeInstance();
        \Illuminate\Support\Facades\Notification::fake();

        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}/resend")
            ->assertOk();

        $this->assertSame(1, QuestionnaireInstances::count());
        \Illuminate\Support\Facades\Notification::assertSentTo(
            $this->contact, \App\Notifications\QuestionnaireSent::class);
    }

    public function test_lock_and_unlock_recompute_status(): void
    {
        $instance = $this->makeInstance();

        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}/lock")
            ->assertOk()
            ->assertJsonPath('instance.status', 'locked');
        $this->assertNotNull($instance->fresh()->locked_at);

        // Unlock with no responses reverts to sent.
        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}/unlock")
            ->assertOk()
            ->assertJsonPath('instance.status', 'sent');
        $this->assertNull($instance->fresh()->locked_at);

        // With a response present, unlock resolves to in_progress.
        $field = $instance->fields()->create([
            'type' => 'short_text', 'label' => 'Q', 'position' => 10,
            'required' => false, 'source_field_id' => 0,
        ]);
        $instance->responses()->create(['instance_field_id' => $field->id, 'value' => 'x']);
        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}/lock");
        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}/unlock")
            ->assertOk()
            ->assertJsonPath('instance.status', 'in_progress');
    }

    public function test_destroy_soft_deletes_instance(): void
    {
        $instance = $this->makeInstance();

        $this->withHeaders($this->asOwner())
            ->deleteJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$instance->id}")
            ->assertOk();

        $this->assertSoftDeleted('questionnaire_instances', ['id' => $instance->id]);
    }

    public function test_cross_band_instance_write_is_404(): void
    {
        $otherBand = Bands::factory()->create();
        $otherBooking = Bookings::factory()->create(['band_id' => $otherBand->id]);
        $foreign = $this->makeInstance(['booking_id' => $otherBooking->id]);

        $this->withHeaders($this->asOwner())
            ->postJson("/api/mobile/bands/{$this->band->id}/questionnaire-instances/{$foreign->id}/lock")
            ->assertStatus(404);
    }
```

- [ ] **Step 2: Run to verify the new ones fail**

Run: `docker compose exec -T app php artisan test --filter=QuestionnaireInstanceMobileTest`
Expected: Task 3's 6 PASS; the 9 new FAIL (405/404).

- [ ] **Step 3: Add the write routes**

After Task 3's read group:

```php
Route::middleware('mobile.band:write:questionnaires')->group(function () {
    Route::post('/bands/{band}/bookings/{booking}/questionnaires', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'send'])->name('mobile.bookings.questionnaires.send');
    Route::post('/bands/{band}/questionnaire-instances/{instance}/resend', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'resend'])->name('mobile.questionnaire-instances.resend');
    Route::post('/bands/{band}/questionnaire-instances/{instance}/lock', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'lock'])->name('mobile.questionnaire-instances.lock');
    Route::post('/bands/{band}/questionnaire-instances/{instance}/unlock', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'unlock'])->name('mobile.questionnaire-instances.unlock');
    Route::delete('/bands/{band}/questionnaire-instances/{instance}', [App\Http\Controllers\Api\Mobile\QuestionnaireInstancesController::class, 'destroy'])->name('mobile.questionnaire-instances.destroy');
});
```

- [ ] **Step 4: Add the write methods**

Add imports `use App\Http\Requests\SendQuestionnaireRequest;`, `use App\Models\Contacts;`, `use App\Notifications\QuestionnaireSent;`, `use App\Services\QuestionnaireSnapshotService;`, `use Illuminate\Support\Facades\Auth;` and inject the snapshot service (add `private QuestionnaireSnapshotService $snapshotService,` to the constructor). Then:

```php
    public function send(SendQuestionnaireRequest $request, Bands $band, Bookings $booking): JsonResponse
    {
        abort_if($booking->band_id !== $band->id, 404);

        $template = Questionnaires::findOrFail($request->input('questionnaire_id'));
        $contact = Contacts::findOrFail($request->input('recipient_contact_id'));

        $instance = $this->snapshotService->snapshot($template, $booking, $contact, Auth::user());
        $contact->notify(new QuestionnaireSent($instance));

        $instance->load(['recipientContact:id,name', 'booking:id,name,band_id']);

        return response()->json(['instance' => $this->summary($instance)], 201);
    }

    public function resend(Bands $band, QuestionnaireInstances $instance): JsonResponse
    {
        $this->ensureBelongsToBand($band, $instance);

        $instance->recipientContact->notify(new QuestionnaireSent($instance));
        $instance->load(['recipientContact:id,name', 'booking:id,name,band_id']);

        return response()->json(['instance' => $this->summary($instance)]);
    }

    public function lock(Bands $band, QuestionnaireInstances $instance): JsonResponse
    {
        $this->ensureBelongsToBand($band, $instance);

        $instance->update([
            'status' => QuestionnaireInstances::STATUS_LOCKED,
            'locked_at' => now(),
            'locked_by_user_id' => Auth::id(),
        ]);
        $instance->load(['recipientContact:id,name', 'booking:id,name,band_id']);

        return response()->json(['instance' => $this->summary($instance)]);
    }

    public function unlock(Bands $band, QuestionnaireInstances $instance): JsonResponse
    {
        $this->ensureBelongsToBand($band, $instance);

        $hasResponses = $instance->responses()->exists();
        $instance->update([
            'status' => $instance->submitted_at
                ? QuestionnaireInstances::STATUS_SUBMITTED
                : ($hasResponses ? QuestionnaireInstances::STATUS_IN_PROGRESS : QuestionnaireInstances::STATUS_SENT),
            'locked_at' => null,
            'locked_by_user_id' => null,
        ]);
        $instance->load(['recipientContact:id,name', 'booking:id,name,band_id']);

        return response()->json(['instance' => $this->summary($instance)]);
    }

    public function destroy(Bands $band, QuestionnaireInstances $instance): JsonResponse
    {
        $this->ensureBelongsToBand($band, $instance);
        $instance->delete();

        return response()->json(['message' => 'Questionnaire instance deleted']);
    }
```

(Lock/unlock/resend bodies mirror `BookingQuestionnaireController` exactly; the only differences are JSON responses instead of redirects and band-scoping via the instance's booking instead of a `{booking}` route param.)

- [ ] **Step 5: Run to green + regression**

```bash
docker compose exec -T app php artisan test --filter=QuestionnaireInstanceMobileTest
docker compose exec -T app php artisan test --filter=Questionnaire
```
Expected: 15/15 file PASS; full questionnaire suite PASS.

- [ ] **Step 6: Commit**

```bash
git add app/Http/Controllers/Api/Mobile/QuestionnaireInstancesController.php routes/api.php tests/Feature/Api/Mobile/QuestionnaireInstanceMobileTest.php
git commit -m "feat(mobile): questionnaire send/resend/lock/unlock/delete endpoints"
```

---

## Mobile tasks (repo `/home/eddie/github/tts_bandmate`, branch `feat/questionnaires-mobile-phase2`)

### Task 5: Endpoints, instance models + tests

**Files:**
- Modify: `lib/core/network/api_endpoints.dart` (extend the Questionnaires section)
- Create: `lib/features/questionnaires/data/models/questionnaire_instance.dart`
- Create: `lib/features/questionnaires/data/models/eligible_booking.dart`
- Modify: `lib/features/bookings/data/models/booking_contact.dart` (add `canLogin`)
- Test: `test/features/questionnaires/questionnaire_instance_models_test.dart`

**Interfaces:**
- Produces:
  - Endpoints: `mobileBandQuestionnaireInstances(int bandId, int questionnaireId)`, `mobileBandQuestionnaireEligibleBookings(int bandId, int questionnaireId)`, `mobileBandBookingQuestionnaireInstances(int bandId, int bookingId)`, `mobileBandBookingQuestionnairesSend(int bandId, int bookingId)`, `mobileBandQuestionnaireInstance(int bandId, int instanceId)`, `mobileBandQuestionnaireInstanceResend/Lock/Unlock(int bandId, int instanceId)`
  - `QuestionnaireInstance{int id, String name, String status, DateTime? sentAt, DateTime? submittedAt, String recipientName, int bookingId, String bookingName, int? questionnaireId, String? description, DateTime? firstOpenedAt, DateTime? lockedAt, List<QuestionnaireField> fields, Map<String, dynamic> responses, Map<String, SongRef> songLookup}` + `bool get isLocked/isSubmitted` + `String get statusLabel` ('Sent'/'In progress'/'Submitted'/'Locked')
  - `SongRef{String title, String? artist}` + `String get display` ("Title — Artist" or just title)
  - `EligibleBooking{int id, String name, String? date, bool alreadySent, List<EligibleContact> contacts}`; `EligibleContact{int id, String name, bool isPrimary, bool canLogin}`
  - `AvailableQuestionnaire{int id, String name}` (in eligible_booking.dart)
  - `BookingQuestionnaires{List<QuestionnaireInstance> instances, List<AvailableQuestionnaire> availableQuestionnaires}`
  - `BookingContact.canLogin` (bool, default false)

- [ ] **Step 1: Add the endpoint builders**

Append to the Questionnaires section of `api_endpoints.dart`:

```dart
  static String mobileBandQuestionnaireInstances(int bandId, int questionnaireId) =>
      '/api/mobile/bands/$bandId/questionnaires/$questionnaireId/instances';
  static String mobileBandQuestionnaireEligibleBookings(int bandId, int questionnaireId) =>
      '/api/mobile/bands/$bandId/questionnaires/$questionnaireId/eligible-bookings';
  static String mobileBandBookingQuestionnaireInstances(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/questionnaire-instances';
  static String mobileBandBookingQuestionnairesSend(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/questionnaires';
  static String mobileBandQuestionnaireInstance(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId';
  static String mobileBandQuestionnaireInstanceResend(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/resend';
  static String mobileBandQuestionnaireInstanceLock(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/lock';
  static String mobileBandQuestionnaireInstanceUnlock(int bandId, int instanceId) =>
      '/api/mobile/bands/$bandId/questionnaire-instances/$instanceId/unlock';
```

- [ ] **Step 2: Write the failing model tests**

`test/features/questionnaires/questionnaire_instance_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/eligible_booking.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_instance.dart';

void main() {
  group('QuestionnaireInstance.fromJson', () {
    test('test_parses_summary_row', () {
      final i = QuestionnaireInstance.fromJson({
        'id': 7,
        'name': 'Wedding Intake',
        'status': 'in_progress',
        'sent_at': '2026-07-15T10:00:00+00:00',
        'submitted_at': null,
        'recipient_name': 'Alice',
        'booking': {'id': 3, 'name': 'Smith Wedding'},
        'questionnaire_id': 1,
      });
      expect(i.id, 7);
      expect(i.status, 'in_progress');
      expect(i.statusLabel, 'In progress');
      expect(i.recipientName, 'Alice');
      expect(i.bookingId, 3);
      expect(i.bookingName, 'Smith Wedding');
      expect(i.sentAt, isNotNull);
      expect(i.submittedAt, null);
      expect(i.fields, isEmpty);
      expect(i.isLocked, false);
    });

    test('test_parses_detail_with_responses_and_songs', () {
      final i = QuestionnaireInstance.fromJson({
        'id': 7,
        'name': 'Wedding Intake',
        'status': 'submitted',
        'recipient_name': 'Alice',
        'booking': {'id': 3, 'name': 'Smith Wedding'},
        'fields': [
          {'id': 21, 'type': 'short_text', 'label': 'Name', 'position': 10},
          {'id': 22, 'type': 'song_picker', 'label': 'Must play', 'position': 20},
        ],
        'responses': {
          '21': 'Alice',
          '22': [5, 9],
        },
        'song_lookup': {
          '5': {'title': 'Song A', 'artist': 'Artist A'},
          '9': {'title': '(removed song #9)', 'artist': null},
        },
      });
      expect(i.isSubmitted, true);
      expect(i.fields.length, 2);
      expect(i.responses['21'], 'Alice');
      expect(i.responses['22'], [5, 9]);
      expect(i.songLookup['5']!.display, 'Song A — Artist A');
      expect(i.songLookup['9']!.display, '(removed song #9)');
    });

    test('test_status_labels', () {
      for (final (status, label) in [
        ('sent', 'Sent'),
        ('in_progress', 'In progress'),
        ('submitted', 'Submitted'),
        ('locked', 'Locked'),
        ('weird', 'weird'),
      ]) {
        final i = QuestionnaireInstance.fromJson({
          'id': 1, 'name': 'x', 'status': status,
          'recipient_name': 'r', 'booking': {'id': 1, 'name': 'b'},
        });
        expect(i.statusLabel, label);
      }
    });
  });

  group('EligibleBooking.fromJson', () {
    test('test_parses_contacts_with_portal_flag', () {
      final b = EligibleBooking.fromJson({
        'id': 3,
        'name': 'Smith Wedding',
        'date': 'Oct 10, 2026',
        'already_sent': true,
        'contacts': [
          {'id': 1, 'name': 'Alice', 'is_primary': true, 'can_login': true},
          {'id': 2, 'name': 'Bob', 'is_primary': false, 'can_login': false},
        ],
      });
      expect(b.alreadySent, true);
      expect(b.contacts.first.canLogin, true);
      expect(b.contacts.last.canLogin, false);
    });
  });

  group('BookingQuestionnaires.fromJson', () {
    test('test_parses_instances_and_templates', () {
      final payload = BookingQuestionnaires.fromJson({
        'instances': [
          {'id': 7, 'name': 'Intake', 'status': 'sent',
           'recipient_name': 'Alice', 'booking': {'id': 3, 'name': 'b'}},
        ],
        'available_questionnaires': [
          {'id': 1, 'name': 'Wedding Intake'},
        ],
      });
      expect(payload.instances.single.id, 7);
      expect(payload.availableQuestionnaires.single.name, 'Wedding Intake');
    });
  });
}
```

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/features/questionnaires/questionnaire_instance_models_test.dart`
Expected: FAIL — imports unresolvable.

- [ ] **Step 4: Implement the models**

`lib/features/questionnaires/data/models/questionnaire_instance.dart`:

```dart
import 'questionnaire_field.dart';

class SongRef {
  const SongRef({required this.title, this.artist});

  final String title;
  final String? artist;

  String get display =>
      artist == null || artist!.isEmpty ? title : '$title — $artist';

  factory SongRef.fromJson(Map<String, dynamic> json) => SongRef(
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String?,
      );
}

class QuestionnaireInstance {
  const QuestionnaireInstance({
    required this.id,
    required this.name,
    required this.status,
    this.sentAt,
    this.submittedAt,
    required this.recipientName,
    required this.bookingId,
    required this.bookingName,
    this.questionnaireId,
    this.description,
    this.firstOpenedAt,
    this.lockedAt,
    this.fields = const [],
    this.responses = const {},
    this.songLookup = const {},
  });

  final int id;
  final String name;
  final String status; // sent | in_progress | submitted | locked
  final DateTime? sentAt;
  final DateTime? submittedAt;
  final String recipientName;
  final int bookingId;
  final String bookingName;
  final int? questionnaireId;
  final String? description;
  final DateTime? firstOpenedAt;
  final DateTime? lockedAt;
  final List<QuestionnaireField> fields;

  /// Decoded answers keyed by instance field id (as string).
  final Map<String, dynamic> responses;
  final Map<String, SongRef> songLookup;

  bool get isLocked => status == 'locked';
  bool get isSubmitted => status == 'submitted';

  String get statusLabel {
    switch (status) {
      case 'sent':
        return 'Sent';
      case 'in_progress':
        return 'In progress';
      case 'submitted':
        return 'Submitted';
      case 'locked':
        return 'Locked';
      default:
        return status;
    }
  }

  factory QuestionnaireInstance.fromJson(Map<String, dynamic> json) {
    final booking = json['booking'] as Map<String, dynamic>? ?? {};
    final rawFields = json['fields'] as List<dynamic>? ?? [];
    final rawResponses = json['responses'];
    final rawSongs = json['song_lookup'] as Map<String, dynamic>? ?? {};
    return QuestionnaireInstance(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      status: json['status'] as String? ?? 'sent',
      sentAt: json['sent_at'] == null
          ? null
          : DateTime.tryParse(json['sent_at'] as String),
      submittedAt: json['submitted_at'] == null
          ? null
          : DateTime.tryParse(json['submitted_at'] as String),
      recipientName: json['recipient_name'] as String? ?? 'Unknown',
      bookingId: ((booking['id'] as num?) ?? 0).toInt(),
      bookingName: booking['name'] as String? ?? '',
      questionnaireId: (json['questionnaire_id'] as num?)?.toInt(),
      description: json['description'] as String?,
      firstOpenedAt: json['first_opened_at'] == null
          ? null
          : DateTime.tryParse(json['first_opened_at'] as String),
      lockedAt: json['locked_at'] == null
          ? null
          : DateTime.tryParse(json['locked_at'] as String),
      fields: rawFields
          .map((f) => QuestionnaireField.fromJson(f as Map<String, dynamic>))
          .toList(),
      // Responses arrive keyed by int-ish field ids; normalize keys to String.
      // An empty responses set serializes as [] in PHP, so tolerate lists.
      responses: rawResponses is Map<String, dynamic>
          ? rawResponses.map((k, v) => MapEntry(k, v))
          : const {},
      songLookup: rawSongs.map(
          (k, v) => MapEntry(k, SongRef.fromJson(v as Map<String, dynamic>))),
    );
  }

  QuestionnaireInstance copyWith({String? status, DateTime? lockedAt, bool clearLockedAt = false}) {
    return QuestionnaireInstance(
      id: id,
      name: name,
      status: status ?? this.status,
      sentAt: sentAt,
      submittedAt: submittedAt,
      recipientName: recipientName,
      bookingId: bookingId,
      bookingName: bookingName,
      questionnaireId: questionnaireId,
      description: description,
      firstOpenedAt: firstOpenedAt,
      lockedAt: clearLockedAt ? null : (lockedAt ?? this.lockedAt),
      fields: fields,
      responses: responses,
      songLookup: songLookup,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuestionnaireInstance &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
```

`lib/features/questionnaires/data/models/eligible_booking.dart`:

```dart
import 'questionnaire_instance.dart';

class EligibleContact {
  const EligibleContact({
    required this.id,
    required this.name,
    required this.isPrimary,
    required this.canLogin,
  });

  final int id;
  final String name;
  final bool isPrimary;
  final bool canLogin;

  factory EligibleContact.fromJson(Map<String, dynamic> json) =>
      EligibleContact(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        isPrimary: (json['is_primary'] as bool?) ?? false,
        canLogin: (json['can_login'] as bool?) ?? false,
      );
}

class EligibleBooking {
  const EligibleBooking({
    required this.id,
    required this.name,
    this.date,
    required this.alreadySent,
    this.contacts = const [],
  });

  final int id;
  final String name;
  final String? date;
  final bool alreadySent;
  final List<EligibleContact> contacts;

  factory EligibleBooking.fromJson(Map<String, dynamic> json) =>
      EligibleBooking(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        date: json['date'] as String?,
        alreadySent: (json['already_sent'] as bool?) ?? false,
        contacts: (json['contacts'] as List<dynamic>? ?? [])
            .map((c) => EligibleContact.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class AvailableQuestionnaire {
  const AvailableQuestionnaire({required this.id, required this.name});

  final int id;
  final String name;

  factory AvailableQuestionnaire.fromJson(Map<String, dynamic> json) =>
      AvailableQuestionnaire(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
      );
}

class BookingQuestionnaires {
  const BookingQuestionnaires({
    this.instances = const [],
    this.availableQuestionnaires = const [],
  });

  final List<QuestionnaireInstance> instances;
  final List<AvailableQuestionnaire> availableQuestionnaires;

  factory BookingQuestionnaires.fromJson(Map<String, dynamic> json) =>
      BookingQuestionnaires(
        instances: (json['instances'] as List<dynamic>? ?? [])
            .map((i) =>
                QuestionnaireInstance.fromJson(i as Map<String, dynamic>))
            .toList(),
        availableQuestionnaires:
            (json['available_questionnaires'] as List<dynamic>? ?? [])
                .map((q) =>
                    AvailableQuestionnaire.fromJson(q as Map<String, dynamic>))
                .toList(),
      );
}
```

`booking_contact.dart` — add a `canLogin` field following the model's existing style: `final bool canLogin;` in the constructor (named, default handled in fromJson), parsed as `canLogin: (json['can_login'] as bool?) ?? false,`. Match the file's existing formatting exactly.

- [ ] **Step 5: Run to green**

Run: `flutter test test/features/questionnaires/ && flutter analyze`
Expected: all questionnaire tests PASS (old + new); analyze at 3-issue baseline.

- [ ] **Step 6: Commit**

```bash
git add lib/core/network/api_endpoints.dart lib/features/questionnaires/data/models/questionnaire_instance.dart lib/features/questionnaires/data/models/eligible_booking.dart lib/features/bookings/data/models/booking_contact.dart test/features/questionnaires/questionnaire_instance_models_test.dart
git commit -m "feat(questionnaires): instance wire models + endpoints"
```

### Task 6: Repository methods + instance providers + tests

**Files:**
- Modify: `lib/features/questionnaires/data/questionnaires_repository.dart`
- Create: `lib/features/questionnaires/providers/questionnaire_instances_provider.dart`
- Modify: `test/features/questionnaires/fake_questionnaires_repository.dart` (implement the new methods)
- Test: `test/features/questionnaires/questionnaire_instances_provider_test.dart`

**Interfaces:**
- Consumes: models + endpoints (Task 5), `questionnairesRepositoryProvider`, `questionnairesProvider` (Phase 1).
- Produces:
  - Repository methods:
    - `Future<List<QuestionnaireInstance>> getInstances(int bandId, int questionnaireId)`
    - `Future<List<EligibleBooking>> getEligibleBookings(int bandId, int questionnaireId)`
    - `Future<BookingQuestionnaires> getBookingQuestionnaires(int bandId, int bookingId)`
    - `Future<QuestionnaireInstance> getInstance(int bandId, int instanceId)`
    - `Future<QuestionnaireInstance> sendQuestionnaire(int bandId, int bookingId, {required int questionnaireId, required int recipientContactId})`
    - `Future<QuestionnaireInstance> resendInstance(int bandId, int instanceId)` / `lockInstance(...)` / `unlockInstance(...)`
    - `Future<void> deleteInstance(int bandId, int instanceId)`
  - `questionnaireInstancesProvider` = `AsyncNotifierProvider.family<QuestionnaireInstancesNotifier, List<QuestionnaireInstance>, ({int bandId, int questionnaireId})>` with `refresh()`, `send({required int bookingId, required int recipientContactId})` (prepends, returns created, invalidates `questionnairesProvider(bandId)` + `eligibleBookingsProvider`), `resend(int instanceId)`, `lock(int instanceId)` / `unlock(int instanceId)` (replace row), `deleteInstance(int instanceId)` (removes, invalidates `questionnairesProvider(bandId)`)
  - `instanceDetailProvider` = `FutureProvider.family<QuestionnaireInstance, ({int bandId, int instanceId})>`
  - `eligibleBookingsProvider` = `FutureProvider.family<List<EligibleBooking>, ({int bandId, int questionnaireId})>`
  - `bookingQuestionnairesProvider` = `FutureProvider.family<BookingQuestionnaires, ({int bandId, int bookingId})>`

- [ ] **Step 1: Write the failing tests**

`test/features/questionnaires/questionnaire_instances_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_instance.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaire_instances_provider.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaires_provider.dart';
import 'fake_questionnaires_repository.dart';

const _key = (bandId: 1, questionnaireId: 1);

QuestionnaireInstance instance(int id, {String status = 'sent'}) =>
    QuestionnaireInstance(
      id: id,
      name: 'Intake',
      status: status,
      recipientName: 'Alice',
      bookingId: 3,
      bookingName: 'Smith Wedding',
      questionnaireId: 1,
    );

void main() {
  ProviderContainer makeContainer(FakeQuestionnairesRepository repo) {
    return ProviderContainer(
      overrides: [questionnairesRepositoryProvider.overrideWithValue(repo)],
    );
  }

  test('test_build_loads_instances', () async {
    final repo = FakeQuestionnairesRepository(instances: [instance(7)]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);

    final list = await container.read(questionnaireInstancesProvider(_key).future);
    expect(list.single.id, 7);
  });

  test('test_send_prepends_and_records_args', () async {
    final repo = FakeQuestionnairesRepository(instances: [instance(7)]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireInstancesProvider(_key).future);

    final created = await container
        .read(questionnaireInstancesProvider(_key).notifier)
        .send(bookingId: 3, recipientContactId: 12);

    expect(created.id, isNot(7));
    expect(repo.sentBookingId, 3);
    expect(repo.sentContactId, 12);
    expect(repo.sentQuestionnaireId, 1);
    final list = container.read(questionnaireInstancesProvider(_key)).value!;
    expect(list.first.id, created.id); // prepended
    expect(list.length, 2);
  });

  test('test_lock_replaces_row', () async {
    final repo = FakeQuestionnairesRepository(instances: [instance(7)]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireInstancesProvider(_key).future);

    await container
        .read(questionnaireInstancesProvider(_key).notifier)
        .lock(7);

    final list = container.read(questionnaireInstancesProvider(_key)).value!;
    expect(list.single.status, 'locked');
  });

  test('test_delete_removes_row', () async {
    final repo = FakeQuestionnairesRepository(instances: [instance(7)]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireInstancesProvider(_key).future);

    await container
        .read(questionnaireInstancesProvider(_key).notifier)
        .deleteInstance(7);

    expect(repo.deletedInstanceId, 7);
    expect(container.read(questionnaireInstancesProvider(_key)).value, isEmpty);
  });
}
```

- [ ] **Step 2: Extend the fake repository**

In `fake_questionnaires_repository.dart` add fields and overrides (keep the existing ones untouched):

```dart
  List<QuestionnaireInstance> instances;
  int? sentBookingId;
  int? sentContactId;
  int? sentQuestionnaireId;
  int? deletedInstanceId;
  int _nextInstanceId = 500;
```

(add `this.instances = const []` to the constructor) and:

```dart
  @override
  Future<List<QuestionnaireInstance>> getInstances(int bandId, int questionnaireId) async =>
      instances;

  @override
  Future<List<EligibleBooking>> getEligibleBookings(int bandId, int questionnaireId) async =>
      const [];

  @override
  Future<BookingQuestionnaires> getBookingQuestionnaires(int bandId, int bookingId) async =>
      BookingQuestionnaires(instances: instances);

  @override
  Future<QuestionnaireInstance> getInstance(int bandId, int instanceId) async =>
      instances.firstWhere((i) => i.id == instanceId);

  @override
  Future<QuestionnaireInstance> sendQuestionnaire(
    int bandId,
    int bookingId, {
    required int questionnaireId,
    required int recipientContactId,
  }) async {
    sentBookingId = bookingId;
    sentContactId = recipientContactId;
    sentQuestionnaireId = questionnaireId;
    return QuestionnaireInstance(
      id: _nextInstanceId++,
      name: 'Intake',
      status: 'sent',
      recipientName: 'New Recipient',
      bookingId: bookingId,
      bookingName: 'Booking',
      questionnaireId: questionnaireId,
    );
  }

  @override
  Future<QuestionnaireInstance> resendInstance(int bandId, int instanceId) async =>
      instances.firstWhere((i) => i.id == instanceId);

  @override
  Future<QuestionnaireInstance> lockInstance(int bandId, int instanceId) async =>
      instances.firstWhere((i) => i.id == instanceId).copyWith(status: 'locked');

  @override
  Future<QuestionnaireInstance> unlockInstance(int bandId, int instanceId) async =>
      instances.firstWhere((i) => i.id == instanceId).copyWith(status: 'sent');

  @override
  Future<void> deleteInstance(int bandId, int instanceId) async {
    deletedInstanceId = instanceId;
  }
```

(with the imports for `QuestionnaireInstance`, `EligibleBooking`, `BookingQuestionnaires`).

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/features/questionnaires/questionnaire_instances_provider_test.dart`
Expected: FAIL — provider file missing / fake doesn't implement the interface yet.

- [ ] **Step 4: Implement repository methods**

Append to `questionnaires_repository.dart` (import the two new model files):

```dart
  Future<List<QuestionnaireInstance>> getInstances(
      int bandId, int questionnaireId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstances(bandId, questionnaireId),
    );
    final list = response.data!['instances'] as List<dynamic>;
    return list
        .map((i) => QuestionnaireInstance.fromJson(i as Map<String, dynamic>))
        .toList();
  }

  Future<List<EligibleBooking>> getEligibleBookings(
      int bandId, int questionnaireId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireEligibleBookings(
          bandId, questionnaireId),
    );
    final list = response.data!['bookings'] as List<dynamic>;
    return list
        .map((b) => EligibleBooking.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  Future<BookingQuestionnaires> getBookingQuestionnaires(
      int bandId, int bookingId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandBookingQuestionnaireInstances(bandId, bookingId),
    );
    return BookingQuestionnaires.fromJson(response.data!);
  }

  Future<QuestionnaireInstance> getInstance(int bandId, int instanceId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstance(bandId, instanceId),
    );
    return QuestionnaireInstance.fromJson(
        response.data!['instance'] as Map<String, dynamic>);
  }

  Future<QuestionnaireInstance> sendQuestionnaire(
    int bandId,
    int bookingId, {
    required int questionnaireId,
    required int recipientContactId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandBookingQuestionnairesSend(bandId, bookingId),
      data: {
        'questionnaire_id': questionnaireId,
        'recipient_contact_id': recipientContactId,
      },
    );
    return QuestionnaireInstance.fromJson(
        response.data!['instance'] as Map<String, dynamic>);
  }

  Future<QuestionnaireInstance> resendInstance(int bandId, int instanceId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstanceResend(bandId, instanceId),
    );
    return QuestionnaireInstance.fromJson(
        response.data!['instance'] as Map<String, dynamic>);
  }

  Future<QuestionnaireInstance> lockInstance(int bandId, int instanceId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstanceLock(bandId, instanceId),
    );
    return QuestionnaireInstance.fromJson(
        response.data!['instance'] as Map<String, dynamic>);
  }

  Future<QuestionnaireInstance> unlockInstance(int bandId, int instanceId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandQuestionnaireInstanceUnlock(bandId, instanceId),
    );
    return QuestionnaireInstance.fromJson(
        response.data!['instance'] as Map<String, dynamic>);
  }

  Future<void> deleteInstance(int bandId, int instanceId) async {
    await _dio.delete<void>(
      ApiEndpoints.mobileBandQuestionnaireInstance(bandId, instanceId),
    );
  }
```

- [ ] **Step 5: Implement the providers**

`lib/features/questionnaires/providers/questionnaire_instances_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/eligible_booking.dart';
import '../data/models/questionnaire_instance.dart';
import '../data/questionnaires_repository.dart';
import 'questionnaires_provider.dart';

class QuestionnaireInstancesNotifier
    extends AsyncNotifier<List<QuestionnaireInstance>> {
  QuestionnaireInstancesNotifier(this._key);

  final ({int bandId, int questionnaireId}) _key;

  QuestionnairesRepository get _repo =>
      ref.read(questionnairesRepositoryProvider);

  @override
  Future<List<QuestionnaireInstance>> build() =>
      _repo.getInstances(_key.bandId, _key.questionnaireId);

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => _repo.getInstances(_key.bandId, _key.questionnaireId));
  }

  Future<QuestionnaireInstance> send({
    required int bookingId,
    required int recipientContactId,
  }) async {
    final created = await _repo.sendQuestionnaire(
      _key.bandId,
      bookingId,
      questionnaireId: _key.questionnaireId,
      recipientContactId: recipientContactId,
    );
    final current = state.value ?? [];
    state = AsyncValue.data([created, ...current]);
    // Times-sent count on the template list + already_sent flags change.
    ref.invalidate(questionnairesProvider(_key.bandId));
    ref.invalidate(eligibleBookingsProvider(_key));
    return created;
  }

  Future<void> resend(int instanceId) async {
    await _repo.resendInstance(_key.bandId, instanceId);
  }

  Future<void> lock(int instanceId) async {
    final updated = await _repo.lockInstance(_key.bandId, instanceId);
    _replace(updated);
  }

  Future<void> unlock(int instanceId) async {
    final updated = await _repo.unlockInstance(_key.bandId, instanceId);
    _replace(updated);
  }

  Future<void> deleteInstance(int instanceId) async {
    await _repo.deleteInstance(_key.bandId, instanceId);
    final current = state.value ?? [];
    state = AsyncValue.data(
        current.where((i) => i.id != instanceId).toList());
    ref.invalidate(questionnairesProvider(_key.bandId));
  }

  void _replace(QuestionnaireInstance updated) {
    final current = state.value ?? [];
    state = AsyncValue.data(
        current.map((i) => i.id == updated.id ? updated : i).toList());
  }
}

final questionnaireInstancesProvider = AsyncNotifierProvider.family<
    QuestionnaireInstancesNotifier,
    List<QuestionnaireInstance>,
    ({int bandId, int questionnaireId})>(
  (arg) => QuestionnaireInstancesNotifier(arg),
);

final instanceDetailProvider = FutureProvider.family<QuestionnaireInstance,
    ({int bandId, int instanceId})>(
  (ref, args) async {
    final repo = ref.watch(questionnairesRepositoryProvider);
    return repo.getInstance(args.bandId, args.instanceId);
  },
);

final eligibleBookingsProvider = FutureProvider.family<List<EligibleBooking>,
    ({int bandId, int questionnaireId})>(
  (ref, args) async {
    final repo = ref.watch(questionnairesRepositoryProvider);
    return repo.getEligibleBookings(args.bandId, args.questionnaireId);
  },
);

final bookingQuestionnairesProvider = FutureProvider.family<
    BookingQuestionnaires, ({int bandId, int bookingId})>(
  (ref, args) async {
    final repo = ref.watch(questionnairesRepositoryProvider);
    return repo.getBookingQuestionnaires(args.bandId, args.bookingId);
  },
);
```

- [ ] **Step 6: Run to green**

Run: `flutter test test/features/questionnaires/ && flutter analyze`
Expected: all PASS (new 4 + all prior); analyze baseline.

- [ ] **Step 7: Commit**

```bash
git add lib/features/questionnaires/data/questionnaires_repository.dart lib/features/questionnaires/providers/questionnaire_instances_provider.dart test/features/questionnaires/fake_questionnaires_repository.dart test/features/questionnaires/questionnaire_instances_provider_test.dart
git commit -m "feat(questionnaires): instance repository + providers"
```

### Task 7: Status badge + questionnaire detail screen + routes

**Files:**
- Create: `lib/features/questionnaires/widgets/instance_status_badge.dart`
- Create: `lib/features/questionnaires/screens/questionnaire_detail_screen.dart`
- Modify: `lib/core/config/router.dart` (add `/questionnaires/:id` + `/questionnaires/:id/instances/:instanceId` routes)
- Modify: `lib/features/questionnaires/screens/questionnaires_screen.dart` (row tap → detail screen for everyone)

**Interfaces:**
- Consumes: `questionnaireDetailProvider`, `questionnaireInstancesProvider` (+ notifier mutations), `questionnaireEditorProvider`'s `editorFieldsFromQuestionnaire`, `QuestionnairePreviewScreen`, `SendQuestionnaireSheet` (Task 8 — create as a stub in this task so the tree compiles), `InstanceResponsesScreen` route (Task 9 route target exists after this task's router change; the screen file is stubbed here too).
- Produces: `InstanceStatusBadge({required String status})`; `QuestionnaireDetailScreen({required int questionnaireId})`; routes `/questionnaires/:id` and `/questionnaires/:id/instances/:instanceId`.

- [ ] **Step 1: Create the status badge**

`lib/features/questionnaires/widgets/instance_status_badge.dart` (visual pattern mirrors `lib/shared/widgets/status_chip.dart`):

```dart
import 'package:flutter/cupertino.dart';

/// Colored status pill for a questionnaire instance:
/// sent (blue) / in_progress (orange) / submitted (green) / locked (grey).
class InstanceStatusBadge extends StatelessWidget {
  const InstanceStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'sent' => ('Sent', CupertinoColors.systemBlue.resolveFrom(context)),
      'in_progress' => (
          'In progress',
          CupertinoColors.systemOrange.resolveFrom(context)
        ),
      'submitted' => (
          'Submitted',
          CupertinoColors.systemGreen.resolveFrom(context)
        ),
      'locked' => ('Locked', CupertinoColors.systemGrey.resolveFrom(context)),
      _ => (status, CupertinoColors.systemGrey.resolveFrom(context)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
```

- [ ] **Step 2: Create stub files so the tree compiles**

- `lib/features/questionnaires/widgets/send_questionnaire_sheet.dart` — stub `SendQuestionnaireSheet extends ConsumerStatefulWidget` with constructor `({super.key, required this.bandId, required this.questionnaireId})` and a minimal Container build (Task 8 fills it).
- `lib/features/questionnaires/screens/instance_responses_screen.dart` — stub `InstanceResponsesScreen extends ConsumerWidget` with constructor `({super.key, required this.questionnaireId, required this.instanceId})` and a spinner scaffold (Task 9 fills it).

- [ ] **Step 3: Add routes**

In `router.dart`, next to the existing questionnaire routes (literal `edit` segment already precedes the bare param route only if ordered correctly — put `/questionnaires/:id/edit` FIRST, then these two):

```dart
      GoRoute(
        path: '/questionnaires/:id/instances/:instanceId',
        builder: (_, state) => InstanceResponsesScreen(
          questionnaireId: int.parse(state.pathParameters['id']!),
          instanceId: int.parse(state.pathParameters['instanceId']!),
        ),
      ),
      GoRoute(
        path: '/questionnaires/:id',
        builder: (_, state) => QuestionnaireDetailScreen(
          questionnaireId: int.parse(state.pathParameters['id']!),
        ),
      ),
```

Add the two imports.

- [ ] **Step 4: Create the detail screen**

`lib/features/questionnaires/screens/questionnaire_detail_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../features/auth/data/models/band_summary.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/questionnaire_instance.dart';
import '../providers/questionnaire_editor_provider.dart';
import '../providers/questionnaire_instances_provider.dart';
import '../providers/questionnaires_provider.dart';
import '../widgets/instance_status_badge.dart';
import '../widgets/send_questionnaire_sheet.dart';
import 'questionnaire_preview_screen.dart';

class QuestionnaireDetailScreen extends ConsumerStatefulWidget {
  const QuestionnaireDetailScreen({super.key, required this.questionnaireId});

  final int questionnaireId;

  @override
  ConsumerState<QuestionnaireDetailScreen> createState() =>
      _QuestionnaireDetailScreenState();
}

class _QuestionnaireDetailScreenState
    extends ConsumerState<QuestionnaireDetailScreen> {
  String? _statusFilter; // null = all

  static const _filters = [
    (null, 'All'),
    ('sent', 'Sent'),
    ('in_progress', 'In progress'),
    ('submitted', 'Submitted'),
    ('locked', 'Locked'),
  ];

  @override
  Widget build(BuildContext context) {
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
        navigationBar: CupertinoNavigationBar(middle: Text('Questionnaire')),
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    final detailKey = (bandId: bandId, questionnaireId: widget.questionnaireId);
    final detailAsync = ref.watch(questionnaireDetailProvider(detailKey));
    final instancesAsync =
        ref.watch(questionnaireInstancesProvider(detailKey));

    final title = detailAsync.value?.name ?? 'Questionnaire';

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(title, overflow: TextOverflow.ellipsis),
        trailing: isOwner
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showSendSheet(bandId),
                child: const Text('Send'),
              )
            : null,
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: () async {
                ref.invalidate(questionnaireDetailProvider(detailKey));
                await ref
                    .read(questionnaireInstancesProvider(detailKey).notifier)
                    .refresh();
              },
            ),
            SliverToBoxAdapter(child: _summarySection(detailAsync, isOwner)),
            SliverToBoxAdapter(child: _filterRow()),
            _instancesSliver(instancesAsync, detailKey, isOwner),
          ],
        ),
      ),
    );
  }

  Widget _summarySection(AsyncValue<dynamic> detailAsync, bool isOwner) {
    final q = detailAsync.value;
    if (q == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (q.description != null && (q.description as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(q.description as String,
                  style: TextStyle(color: context.secondaryText)),
            ),
          Row(
            children: [
              Text(
                q.instancesCount == 0
                    ? 'Never sent'
                    : 'Sent ${q.instancesCount} time${q.instancesCount == 1 ? '' : 's'}',
                style: TextStyle(color: context.secondaryText, fontSize: 13),
              ),
              const Spacer(),
              if (isOwner)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      context.push('/questionnaires/${widget.questionnaireId}/edit'),
                  child: const Text('Edit'),
                ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _openPreview(q),
                child: const Text('Preview'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final (value, label) in _filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _statusFilter = value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _statusFilter == value
                        ? CupertinoColors.systemBlue.resolveFrom(context)
                        : CupertinoColors.tertiarySystemBackground
                            .resolveFrom(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _statusFilter == value
                          ? CupertinoColors.white
                          : CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _instancesSliver(
    AsyncValue<List<QuestionnaireInstance>> instancesAsync,
    ({int bandId, int questionnaireId}) detailKey,
    bool isOwner,
  ) {
    if (instancesAsync.isLoading && !instancesAsync.hasValue) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }
    if (instancesAsync.hasError && !instancesAsync.hasValue) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text('Failed to load sent questionnaires.',
                style: TextStyle(color: context.secondaryText)),
          ),
        ),
      );
    }
    final all = instancesAsync.value!;
    final filtered = _statusFilter == null
        ? all
        : all.where((i) => i.status == _statusFilter).toList();

    if (filtered.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              all.isEmpty
                  ? 'Not sent to anyone yet.'
                  : 'No sent questionnaires match this filter.',
              style: TextStyle(color: context.secondaryText),
            ),
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: CupertinoListSection.insetGrouped(
        header: const Text('Sent'),
        children: [
          for (final i in filtered)
            _InstanceRow(
              instance: i,
              detailKey: detailKey,
              isOwner: isOwner,
              questionnaireId: widget.questionnaireId,
            ),
        ],
      ),
    );
  }

  Future<void> _showSendSheet(int bandId) async {
    final container = ProviderScope.containerOf(context);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: SendQuestionnaireSheet(
          bandId: bandId,
          questionnaireId: widget.questionnaireId,
        ),
      ),
    );
  }

  void _openPreview(dynamic q) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => QuestionnairePreviewScreen(
          title: q.name as String,
          fields: editorFieldsFromQuestionnaire(q),
        ),
      ),
    );
  }
}

class _InstanceRow extends ConsumerWidget {
  const _InstanceRow({
    required this.instance,
    required this.detailKey,
    required this.isOwner,
    required this.questionnaireId,
  });

  final QuestionnaireInstance instance;
  final ({int bandId, int questionnaireId}) detailKey;
  final bool isOwner;
  final int questionnaireId;

  String _fmt(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, yyyy').format(d.toLocal());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = instance;
    return GestureDetector(
      onLongPress: isOwner ? () => _showActions(context, ref) : null,
      child: CupertinoListTile(
        title: Row(
          children: [
            Expanded(
              child:
                  Text(i.bookingName, overflow: TextOverflow.ellipsis),
            ),
            InstanceStatusBadge(status: i.status),
          ],
        ),
        subtitle: Text(
          '${i.recipientName} · sent ${_fmt(i.sentAt)}'
          '${i.submittedAt != null ? ' · submitted ${_fmt(i.submittedAt)}' : ''}',
        ),
        trailing: const CupertinoListTileChevron(),
        onTap: () => context
            .push('/questionnaires/$questionnaireId/instances/${i.id}'),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final notifier =
        ref.read(questionnaireInstancesProvider(detailKey).notifier);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text('${instance.name} — ${instance.recipientName}'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              try {
                await notifier.resend(instance.id);
                if (context.mounted) {
                  _info(context, 'Sent', 'The questionnaire email was re-sent.');
                }
              } catch (_) {
                if (context.mounted) {
                  _info(context, 'Resend failed', 'Please try again.');
                }
              }
            },
            child: const Text('Resend email'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              try {
                if (instance.isLocked) {
                  await notifier.unlock(instance.id);
                } else {
                  await notifier.lock(instance.id);
                }
              } catch (_) {
                if (context.mounted) {
                  _info(context, instance.isLocked ? 'Unlock failed' : 'Lock failed',
                      'Please try again.');
                }
              }
            },
            child: Text(instance.isLocked ? 'Unlock' : 'Lock'),
          ),
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
        title: const Text('Delete sent questionnaire?'),
        content: Text(
            'The copy sent to ${instance.recipientName} and any answers will be removed.'),
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
          .read(questionnaireInstancesProvider(detailKey).notifier)
          .deleteInstance(instance.id);
    } catch (_) {
      if (context.mounted) {
        _info(context, 'Delete failed', 'Please try again.');
      }
    }
  }

  void _info(BuildContext context, String title, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
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
```

- [ ] **Step 5: Point list rows at the detail screen**

In `questionnaires_screen.dart`'s `_QuestionnaireRow`, change `onTap` so BOTH owner and non-owner push the detail screen:

```dart
        onTap: () => context.push('/questionnaires/${q.id}'),
```

(keep the long-press action sheet exactly as is — Edit/Preview/Archive/Restore/Delete still work from the list).

- [ ] **Step 6: Analyze + test + commit**

Run: `flutter analyze && flutter test`
Expected: baseline + all green.

```bash
git add lib/features/questionnaires/widgets/instance_status_badge.dart lib/features/questionnaires/widgets/send_questionnaire_sheet.dart lib/features/questionnaires/screens/instance_responses_screen.dart lib/features/questionnaires/screens/questionnaire_detail_screen.dart lib/core/config/router.dart lib/features/questionnaires/screens/questionnaires_screen.dart
git commit -m "feat(questionnaires): detail screen with sent log, filters + instance actions"
```

### Task 8: Send sheets (questionnaire → booking, booking → template)

**Files:**
- Rewrite: `lib/features/questionnaires/widgets/send_questionnaire_sheet.dart` (replace Task 7's stub)
- Create: `lib/features/questionnaires/widgets/send_from_booking_sheet.dart`

**Interfaces:**
- Consumes: `eligibleBookingsProvider`, `questionnaireInstancesProvider().send(...)`, `bookingQuestionnairesProvider`, `questionnairesRepositoryProvider.sendQuestionnaire(...)`, `EligibleBooking`/`EligibleContact`/`AvailableQuestionnaire`.
- Produces:
  - `SendQuestionnaireSheet({required int bandId, required int questionnaireId})` — booking picker (already-sent tagged) → recipient picker (non-portal contacts disabled) → Send via the instances notifier
  - `SendFromBookingSheet({required int bandId, required int bookingId, required List<AvailableQuestionnaire> templates, required List<EligibleContact> contacts})` — template picker + recipient picker → Send via repository, then invalidates `bookingQuestionnairesProvider` + `questionnairesProvider`

- [ ] **Step 1: Implement SendQuestionnaireSheet**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/eligible_booking.dart';
import '../providers/questionnaire_instances_provider.dart';

class SendQuestionnaireSheet extends ConsumerStatefulWidget {
  const SendQuestionnaireSheet({
    super.key,
    required this.bandId,
    required this.questionnaireId,
  });

  final int bandId;
  final int questionnaireId;

  @override
  ConsumerState<SendQuestionnaireSheet> createState() =>
      _SendQuestionnaireSheetState();
}

class _SendQuestionnaireSheetState
    extends ConsumerState<SendQuestionnaireSheet> {
  EligibleBooking? _booking;
  EligibleContact? _contact;
  bool _sending = false;
  String? _error;

  ({int bandId, int questionnaireId}) get _key =>
      (bandId: widget.bandId, questionnaireId: widget.questionnaireId);

  Future<void> _submit() async {
    final booking = _booking;
    final contact = _contact;
    if (booking == null || contact == null) {
      setState(() => _error = 'Choose a booking and a recipient.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(questionnaireInstancesProvider(_key).notifier).send(
            bookingId: booking.id,
            recipientContactId: contact.id,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Failed to send. Please try again.';
        });
      }
    }
  }

  Future<void> _pickBooking(List<EligibleBooking> bookings) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Choose booking'),
        actions: [
          for (final b in bookings)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                setState(() {
                  _booking = b;
                  _contact = null;
                });
              },
              child: Text(
                '${b.name}${b.date != null ? ' · ${b.date}' : ''}'
                '${b.alreadySent ? ' (already sent)' : ''}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickContact(EligibleBooking booking) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Send to'),
        message: booking.contacts.any((c) => !c.canLogin)
            ? const Text('Contacts without portal access can\'t be sent a questionnaire.')
            : null,
        actions: [
          for (final c in booking.contacts.where((c) => c.canLogin))
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                setState(() => _contact = c);
              },
              child: Text('${c.name}${c.isPrimary ? ' (primary)' : ''}'),
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
    final bookingsAsync = ref.watch(eligibleBookingsProvider(_key));
    final bookings = bookingsAsync.value ?? const <EligibleBooking>[];
    final selectedBooking = _booking;
    final portalContacts =
        selectedBooking?.contacts.where((c) => c.canLogin).toList() ??
            const <EligibleContact>[];

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
                        _sending ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Text('Send Questionnaire',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _sending ? null : _submit,
                    child: _sending
                        ? const CupertinoActivityIndicator()
                        : const Text('Send'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (bookingsAsync.isLoading && bookings.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              else if (bookings.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No upcoming bookings to send to.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.secondaryText),
                  ),
                )
              else ...[
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _sending ? null : () => _pickBooking(bookings),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Booking'),
                      Flexible(
                        child: Text(
                          selectedBooking?.name ?? 'Choose…',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.secondaryText),
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _sending || selectedBooking == null
                      ? null
                      : () => _pickContact(selectedBooking),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Recipient'),
                      Flexible(
                        child: Text(
                          _contact?.name ??
                              (selectedBooking == null
                                  ? 'Choose a booking first'
                                  : portalContacts.isEmpty
                                      ? 'No portal-enabled contacts'
                                      : 'Choose…'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.secondaryText),
                        ),
                      ),
                    ],
                  ),
                ),
                if (selectedBooking != null && selectedBooking.alreadySent)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'This booking has already been sent this questionnaire.',
                      style: TextStyle(
                          color: context.secondaryText, fontSize: 13),
                    ),
                  ),
              ],
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

- [ ] **Step 2: Implement SendFromBookingSheet**

`lib/features/questionnaires/widgets/send_from_booking_sheet.dart` — same sheet chrome; state `AvailableQuestionnaire? _template; EligibleContact? _contact;`; template picker action sheet over `widget.templates`; recipient picker over `widget.contacts.where((c) => c.canLogin)`; submit:

```dart
  Future<void> _submit() async {
    final template = _template;
    final contact = _contact;
    if (template == null || contact == null) {
      setState(() => _error = 'Choose a questionnaire and a recipient.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(questionnairesRepositoryProvider).sendQuestionnaire(
            widget.bandId,
            widget.bookingId,
            questionnaireId: template.id,
            recipientContactId: contact.id,
          );
      ref.invalidate(bookingQuestionnairesProvider(
          (bandId: widget.bandId, bookingId: widget.bookingId)));
      ref.invalidate(questionnairesProvider(widget.bandId));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Failed to send. Please try again.';
        });
      }
    }
  }
```

Constructor: `SendFromBookingSheet({super.key, required this.bandId, required this.bookingId, required this.templates, required this.contacts})` with `final List<AvailableQuestionnaire> templates; final List<EligibleContact> contacts;`. Header title 'Send Questionnaire'. Row labels 'Questionnaire' / 'Recipient'. Empty-templates state: 'No active questionnaires. Create one under Operations → Questionnaires.' Imports: cupertino, flutter_riverpod, context_colors, `../data/models/eligible_booking.dart`, `../providers/questionnaire_instances_provider.dart`, `../providers/questionnaires_provider.dart`. Follow SendQuestionnaireSheet's exact layout/dispose/keyboard-inset conventions.

- [ ] **Step 3: Analyze + test + commit**

Run: `flutter analyze && flutter test`
Expected: baseline + green.

```bash
git add lib/features/questionnaires/widgets/send_questionnaire_sheet.dart lib/features/questionnaires/widgets/send_from_booking_sheet.dart
git commit -m "feat(questionnaires): send sheets for questionnaire and booking flows"
```

### Task 9: Instance responses screen

**Files:**
- Rewrite: `lib/features/questionnaires/screens/instance_responses_screen.dart` (replace Task 7's stub)

**Interfaces:**
- Consumes: `instanceDetailProvider((bandId, instanceId))`, `isFieldVisible`/`VisibilityFieldRef` (Phase 1 evaluator — instance field ids stringified), `InstanceStatusBadge`, `questionnaireInstancesProvider` notifier for actions.
- Produces: `InstanceResponsesScreen({required int questionnaireId, required int instanceId})` at route `/questionnaires/:id/instances/:instanceId`.

- [ ] **Step 1: Implement**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../features/auth/data/models/band_summary.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/questionnaire_field.dart';
import '../data/models/questionnaire_instance.dart';
import '../logic/visibility_evaluator.dart';
import '../providers/questionnaire_instances_provider.dart';
import '../widgets/instance_status_badge.dart';

class InstanceResponsesScreen extends ConsumerWidget {
  const InstanceResponsesScreen({
    super.key,
    required this.questionnaireId,
    required this.instanceId,
  });

  final int questionnaireId;
  final int instanceId;

  String _fmt(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, yyyy h:mm a').format(d.toLocal());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider).value;
    final bandId = ref.watch(selectedBandProvider).value;
    final bands = authState is AuthAuthenticated
        ? authState.bands
        : const <BandSummary>[];
    final currentBand =
        bandId == null ? null : bands.where((b) => b.id == bandId).firstOrNull;
    final isOwner = currentBand?.isOwner ?? false;

    const navBarTitle = Text('Responses');

    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    final key = (bandId: bandId, instanceId: instanceId);
    final detailAsync = ref.watch(instanceDetailProvider(key));

    if (detailAsync.isLoading && !detailAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }
    if (detailAsync.hasError && !detailAsync.hasValue) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(
          child: Center(
            child: Text('Failed to load responses.',
                style: TextStyle(color: context.secondaryText)),
          ),
        ),
      );
    }

    final instance = detailAsync.value!;
    final refs = instance.fields
        .map((f) => VisibilityFieldRef(id: '${f.id}', rule: f.visibilityRule))
        .toList();
    final visibleFields = instance.fields
        .where((f) => isFieldVisible('${f.id}', refs, instance.responses))
        .toList();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: navBarTitle,
        trailing: isOwner
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showActions(context, ref, bandId, instance),
                child: const Icon(CupertinoIcons.ellipsis_circle, size: 22),
              )
            : null,
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: () async => ref.invalidate(instanceDetailProvider(key)),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            instance.name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                        ),
                        InstanceStatusBadge(status: instance.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${instance.bookingName} · ${instance.recipientName}',
                      style: TextStyle(color: context.secondaryText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sent ${_fmt(instance.sentAt)}'
                      '${instance.firstOpenedAt != null ? ' · opened ${_fmt(instance.firstOpenedAt)}' : ''}'
                      '${instance.submittedAt != null ? ' · submitted ${_fmt(instance.submittedAt)}' : ''}',
                      style: TextStyle(
                          color: context.secondaryText, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  for (final field in visibleFields)
                    _FieldAnswer(field: field, instance: instance),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref, int bandId,
      QuestionnaireInstance instance) async {
    final qId = instance.questionnaireId ?? questionnaireId;
    final listKey = (bandId: bandId, questionnaireId: qId);
    final detailKey = (bandId: bandId, instanceId: instanceId);
    final notifier =
        ref.read(questionnaireInstancesProvider(listKey).notifier);

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              try {
                await notifier.resend(instance.id);
              } catch (_) {
                if (context.mounted) {
                  _info(context, 'Resend failed', 'Please try again.');
                }
              }
            },
            child: const Text('Resend email'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              try {
                if (instance.isLocked) {
                  await notifier.unlock(instance.id);
                } else {
                  await notifier.lock(instance.id);
                }
                ref.invalidate(instanceDetailProvider(detailKey));
              } catch (_) {
                if (context.mounted) {
                  _info(context,
                      instance.isLocked ? 'Unlock failed' : 'Lock failed',
                      'Please try again.');
                }
              }
            },
            child: Text(instance.isLocked ? 'Unlock' : 'Lock'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              try {
                await notifier.deleteInstance(instance.id);
                if (context.mounted) Navigator.of(context).pop();
              } catch (_) {
                if (context.mounted) {
                  _info(context, 'Delete failed', 'Please try again.');
                }
              }
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

  void _info(BuildContext context, String title, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
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

class _FieldAnswer extends StatelessWidget {
  const _FieldAnswer({required this.field, required this.instance});

  final QuestionnaireField field;
  final QuestionnaireInstance instance;

  @override
  Widget build(BuildContext context) {
    if (field.type == 'header') {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(field.label,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      );
    }
    if (field.type == 'instructions') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(field.label,
            style: TextStyle(color: context.secondaryText, fontSize: 13)),
      );
    }

    final raw = instance.responses['${field.id}'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label,
              style: TextStyle(
                  color: context.secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          _answer(context, raw),
        ],
      ),
    );
  }

  Widget _answer(BuildContext context, dynamic raw) {
    if (raw == null || (raw is String && raw.isEmpty) || (raw is List && raw.isEmpty)) {
      return Text('—', style: TextStyle(color: context.secondaryText));
    }

    if (field.type == 'song_picker' && raw is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final id in raw)
            Text(instance.songLookup['$id']?.display ?? '(removed song #$id)'),
        ],
      );
    }

    if (raw is List) {
      // multi_select / checkbox_group: map option values back to labels.
      final labels = raw.map((v) {
        final match =
            field.options.where((o) => o.value == '$v').firstOrNull;
        return match?.label ?? '$v';
      });
      return Text(labels.join(', '));
    }

    if (field.type == 'yes_no') {
      return Text('$raw' == 'yes' ? 'Yes' : ('$raw' == 'no' ? 'No' : '$raw'));
    }

    if (field.type == 'dropdown') {
      final match =
          field.options.where((o) => o.value == '$raw').firstOrNull;
      return Text(match?.label ?? '$raw');
    }

    return Text('$raw');
  }
}
```

- [ ] **Step 2: Analyze + test + commit**

Run: `flutter analyze && flutter test`
Expected: baseline + green.

```bash
git add lib/features/questionnaires/screens/instance_responses_screen.dart
git commit -m "feat(questionnaires): instance responses screen"
```

### Task 10: Booking detail Questionnaires section

**Files:**
- Modify: `lib/features/bookings/screens/booking_detail_screen.dart`

**Interfaces:**
- Consumes: `bookingQuestionnairesProvider((bandId, bookingId))`, `InstanceStatusBadge`, `SendFromBookingSheet`, `EligibleContact` (built from the booking's own contacts, which now carry `canLogin` via Task 5's `BookingContact` + Task 3's formatter).
- Produces: a Questionnaires section on the booking detail screen between the Contract and Notes sections.

- [ ] **Step 1: Add the section**

In `_BookingDetailView`'s build, after the Contract section block and before Notes, insert:

```dart
                  const SizedBox(height: 16),
                  const _SectionHeader(label: 'Questionnaires'),
                  _QuestionnairesSection(
                    bandId: widget.bandId,
                    bookingId: widget.bookingId,
                    contacts: b.contacts,
                    isOwner: isOwner,
                  ),
```

If the view doesn't already compute `isOwner`, derive it the same way `operations_screen.dart` does (authProvider bands + selectedBandProvider) or reuse an existing owner flag in the file if one exists (check first — prefer the file's own precedent).

Then add the section widget at the bottom of the file:

```dart
class _QuestionnairesSection extends ConsumerWidget {
  const _QuestionnairesSection({
    required this.bandId,
    required this.bookingId,
    required this.contacts,
    required this.isOwner,
  });

  final int bandId;
  final int bookingId;
  final List<BookingContact> contacts;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (bandId: bandId, bookingId: bookingId);
    final async = ref.watch(bookingQuestionnairesProvider(key));
    final data = async.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (async.isLoading && data == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (data != null) ...[
          for (final i in data.instances)
            CupertinoListTile(
              title: Row(
                children: [
                  Expanded(
                    child: Text(i.name, overflow: TextOverflow.ellipsis),
                  ),
                  InstanceStatusBadge(status: i.status),
                ],
              ),
              subtitle: Text(i.recipientName),
              trailing: const CupertinoListTileChevron(),
              onTap: () => context.push(
                  '/questionnaires/${i.questionnaireId ?? 0}/instances/${i.id}'),
            ),
          if (data.instances.isEmpty && !isOwner)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No questionnaires sent for this booking.',
                  style: TextStyle(color: context.secondaryText)),
            ),
          if (isOwner)
            BookingSectionTile(
              icon: CupertinoIcons.doc_text,
              title: 'Send questionnaire',
              subtitle: data.availableQuestionnaires.isEmpty
                  ? 'No active questionnaires'
                  : '${data.availableQuestionnaires.length} available',
              onTap: data.availableQuestionnaires.isEmpty
                  ? null
                  : () => _showSendSheet(context, ref, data),
            ),
        ],
      ],
    );
  }

  Future<void> _showSendSheet(
      BuildContext context, WidgetRef ref, BookingQuestionnaires data) async {
    final eligibleContacts = contacts
        .map((c) => EligibleContact(
              id: c.contactId,
              name: c.name,
              isPrimary: c.isPrimary,
              canLogin: c.canLogin,
            ))
        .toList();
    final container = ProviderScope.containerOf(context);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: SendFromBookingSheet(
          bandId: bandId,
          bookingId: bookingId,
          templates: data.availableQuestionnaires,
          contacts: eligibleContacts,
        ),
      ),
    );
  }
}
```

Add imports to `booking_detail_screen.dart`:

```dart
import '../../questionnaires/data/models/eligible_booking.dart';
import '../../questionnaires/providers/questionnaire_instances_provider.dart';
import '../../questionnaires/widgets/instance_status_badge.dart';
import '../../questionnaires/widgets/send_from_booking_sheet.dart';
```

(Adjust relative paths / add `BookingQuestionnaires` import from `questionnaire_instance.dart`'s sibling if the analyzer asks; `BookingContact` is already imported in this file. If `BookingSectionTile.onTap` is non-nullable, wrap the disabled case by omitting the tile instead.)

- [ ] **Step 2: Analyze + test + commit**

Run: `flutter analyze && flutter test`
Expected: baseline + green.

```bash
git add lib/features/bookings/screens/booking_detail_screen.dart
git commit -m "feat(questionnaires): booking detail questionnaires section"
```

### Task 11: Realtime invalidation registry

**Files:**
- Modify: `lib/shared/providers/band_realtime_provider.dart`

**Interfaces:**
- Consumes: `questionnairesProvider`, `questionnaireDetailProvider` (Phase 1), `questionnaireInstancesProvider`, `instanceDetailProvider`, `eligibleBookingsProvider`, `bookingQuestionnairesProvider` (Task 6); backend wire names from Task 2.
- Produces: live refresh of questionnaire screens on `band.data-changed`.

- [ ] **Step 1: Register the models**

Add imports:

```dart
import '../../features/questionnaires/providers/questionnaire_instances_provider.dart';
import '../../features/questionnaires/providers/questionnaires_provider.dart';
```

Add cases to `invalidationTargetsFor` (before `default`):

```dart
    case 'questionnaires':
      return [questionnairesProvider, questionnaireDetailProvider];
    case 'questionnaire_instances':
      return [
        questionnaireInstancesProvider,
        instanceDetailProvider,
        bookingQuestionnairesProvider,
        eligibleBookingsProvider,
        questionnairesProvider, // times-sent counts on the list
      ];
    case 'questionnaire_responses':
      return [instanceDetailProvider, questionnaireInstancesProvider];
```

Extend `_allRegisteredModels` with `'questionnaires'`, `'questionnaire_instances'`, `'questionnaire_responses'`.

- [ ] **Step 2: Analyze + test + commit**

Run: `flutter analyze && flutter test`
Expected: baseline + green (the realtime provider has existing tests — if a test enumerates registered models, update it to include the three new entries).

```bash
git add lib/shared/providers/band_realtime_provider.dart
# plus the realtime test file if updated
git commit -m "feat(questionnaires): realtime invalidation for questionnaire models"
```

### Task 12: Version bump, full verification, PRs

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/pubspec.yaml`

- [ ] **Step 1: Bump the version**

`version: 1.15.0+24` → `version: 1.16.0+25` (adjust if moved; bump minor + build).

- [ ] **Step 2: Full mobile verification**

Run: `flutter analyze && flutter test`
Expected: 3-issue baseline; all tests green.

- [ ] **Step 3: Full backend verification**

```bash
cd /home/eddie/github/TTS
docker compose exec -T app php artisan test --filter=Questionnaire
docker compose exec -T app php artisan test --filter=BookingMobile
```
Expected: PASS.

- [ ] **Step 4: Commit the bump**

```bash
cd /home/eddie/github/tts_bandmate && git add pubspec.yaml && git commit -m "chore: bump version to 1.16.0+25"
```

- [ ] **Step 5: On-device verification (run-on-device skill)**

Local backend running; log in (token already carries questionnaire abilities from Phase 1 — no re-login needed unless the device session predates Phase 1's deploy). Drive: Operations → Questionnaires → open a questionnaire → Send → pick booking + recipient (verify non-portal contacts are absent and already-sent tagging) → confirm the log row appears with a Sent badge → open the row (responses screen; answer via the web portal locally if feasible, else verify empty-answer rendering) → lock/unlock from the row's long-press → booking detail screen shows the section + send flow → verify realtime: with the app open on the detail screen, submit/edit a response in the web portal and watch the log/status refresh live.

- [ ] **Step 6: Open PRs (after user confirmation)**

Backend: `gh pr create --base staging` (draft if requested) from `feat/mobile-questionnaire-instances`. Mobile: `gh pr create --base main` from `feat/questionnaires-mobile-phase2`. Wait for and address Copilot comments on both.

---

## Self-review notes

- Spec coverage (Phase 2 section): all seven backend endpoints → Tasks 3–4 (instances, eligible-bookings, send, booking section, instance detail, resend/lock/unlock, delete); `BandDataChanged` on questionnaire models → Task 2; detail screen with summary/actions/send/log list + status filters → Task 7; send sheet with eligible bookings + portal-enabled recipients + inline errors → Task 8; responses screen with decoded values, songs as "Title — Artist", headers/instructions as breaks, unanswered muted, hidden-by-visibility omitted → Task 9; booking-detail section with instances + send → Task 10; realtime registry → Task 11.
- Type consistency: `QuestionnaireInstance` responses keyed by `String` field ids everywhere (backend `mapWithKeys` emits int-keyed JSON objects which Dart decodes as `Map<String, dynamic>` string keys); `EligibleContact` reused for both send flows; provider record keys `({int bandId, int questionnaireId})` / `({int bandId, int instanceId})` / `({int bandId, int bookingId})` used identically across Tasks 6–11.
- Deviations noted: spec's "already-sent bookings flagged but re-sendable" — implemented (tag in picker, warning line, Send not blocked). Spec's questionnaire-detail "Archive/Delete actions" live on the list screen's long-press (Phase 1) plus Edit/Preview on the detail header — archive/delete not duplicated on the detail screen (YAGNI; list is one tap away). Instance actions on both the detail-screen rows and the responses screen surface failures via mounted-guarded alert dialogs (matching Phase 1's fix-wave convention — no silent catches).
- Phase 3 (apply-to-event + push) intentionally untouched.
