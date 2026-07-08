# Band-Scoped Realtime Invalidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every band-scoped model create/update/delete on the backend broadcasts a thin `{model, id, action}` signal on `private-band.{bandId}`; the mobile app subscribes per selected band and invalidates the matching Riverpod providers.

**Architecture:** Backend: an opt-in `BroadcastsBandChanges` model trait dispatches one queued `BandDataChanged` event; one new channel-auth entry. Mobile: a shared `PusherConnection` service in `core/` (live-setlist + planner ported onto it), plus a `bandRealtimeProvider` with a model→providers invalidation registry and debounce.

**Tech Stack:** Laravel 12 (PHPUnit, soketi/Pusher protocol, Horizon queue), Flutter/Riverpod v2 (`pusher_channels_flutter` ^2.6.0).

**Spec:** `docs/superpowers/specs/2026-07-06-band-realtime-invalidation-design.md`

## Global Constraints

- Backend repo: `/home/eddie/github/TTS`. ALL php/artisan/composer commands run as `docker compose exec app <cmd>` from that directory — never on the host.
- Backend branch: `feat/band-realtime-broadcasts` off `staging`. Backend PR base is **staging** (auto-deploys on merge).
- Mobile repo: `/home/eddie/github/tts_bandmate`, branch `feat/band-realtime-invalidation` (already exists). Mobile PR base is **main**.
- The broadcast path must NEVER break or slow a write: trait hooks wrap dispatch in try/catch + `report()`; event is queued (`ShouldBroadcast`), not `ShouldBroadcastNow`.
- Model short names are `Str::snake(class_basename($model))` — the wire contract with mobile:
  | Class | wire name |
  |---|---|
  | `Bookings` | `bookings` |
  | `Events` | `events` |
  | `Rehearsal` | `rehearsal` |
  | `Roster` | `roster` |
  | `EventMember` | `event_member` |
- Broadcast event name on the wire: `band.data-changed`. Channel: `private-band.{bandId}` (client string) / `band.{bandId}` (Laravel channel name).
- Mobile: after every task run `flutter analyze` (must be clean) before committing.

---

## Backend tasks (repo `/home/eddie/github/TTS`)

### Task 1: Branch, test-env guard, and `BandDataChanged` event

**Files:**
- Modify: `/home/eddie/github/TTS/phpunit.xml` (add BROADCAST_DRIVER)
- Create: `/home/eddie/github/TTS/app/Events/BandDataChanged.php`
- Test: `/home/eddie/github/TTS/tests/Unit/Events/BandDataChangedTest.php`

**Interfaces:**
- Produces: `App\Events\BandDataChanged::__construct(int $bandId, string $model, int $id, string $action, ?array $parent = null)`; `broadcastOn(): [PrivateChannel('band.{bandId}')]`; `broadcastAs(): 'band.data-changed'`; `broadcastWith(): {model, id, action[, parent]}`. Task 2's trait dispatches this exact signature.

- [ ] **Step 1: Create the branch**

```bash
cd /home/eddie/github/TTS && git checkout staging && git pull && git checkout -b feat/band-realtime-broadcasts
```

- [ ] **Step 2: Force the null broadcast driver in tests**

Adding the trait (Task 2+) makes every factory `create()` in the whole suite dispatch a real broadcast (queue is `sync` in tests and `phpunit.xml` does not set `BROADCAST_DRIVER`, so it would use the `.env` pusher driver and attempt HTTP). Guard first. In `/home/eddie/github/TTS/phpunit.xml`, next to the existing `<server name="QUEUE_CONNECTION" value="sync"/>` line, add:

```xml
<server name="BROADCAST_DRIVER" value="null"/>
```

- [ ] **Step 3: Write the failing unit test**

`/home/eddie/github/TTS/tests/Unit/Events/BandDataChangedTest.php`:

```php
<?php

namespace Tests\Unit\Events;

use App\Events\BandDataChanged;
use Illuminate\Broadcasting\PrivateChannel;
use PHPUnit\Framework\TestCase;

class BandDataChangedTest extends TestCase
{
    public function test_broadcasts_on_the_band_private_channel(): void
    {
        $event = new BandDataChanged(42, 'bookings', 7, 'updated');

        $channels = $event->broadcastOn();
        $this->assertCount(1, $channels);
        $this->assertInstanceOf(PrivateChannel::class, $channels[0]);
        $this->assertSame('private-band.42', $channels[0]->name);
    }

    public function test_broadcast_alias_and_thin_payload(): void
    {
        $event = new BandDataChanged(42, 'bookings', 7, 'created');

        $this->assertSame('band.data-changed', $event->broadcastAs());
        $this->assertSame(
            ['model' => 'bookings', 'id' => 7, 'action' => 'created'],
            $event->broadcastWith(),
        );
    }

    public function test_payload_includes_parent_when_given(): void
    {
        $event = new BandDataChanged(42, 'event_member', 9, 'deleted', ['model' => 'events', 'id' => 3]);

        $this->assertSame(
            [
                'model'  => 'event_member',
                'id'     => 9,
                'action' => 'deleted',
                'parent' => ['model' => 'events', 'id' => 3],
            ],
            $event->broadcastWith(),
        );
    }
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=BandDataChangedTest`
Expected: FAIL — `Class "App\Events\BandDataChanged" not found`

- [ ] **Step 5: Implement the event**

`/home/eddie/github/TTS/app/Events/BandDataChanged.php`:

```php
<?php

namespace App\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Contracts\Events\ShouldDispatchAfterCommit;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Thin band-scoped change signal: tells subscribed band members that a model
 * changed so they can refetch through the API. Carries no model data — the
 * API layer stays the single permission-enforcing serializer.
 *
 * Queued (ShouldBroadcast, via Horizon) so broadcasting can never slow the
 * originating write; dispatched after commit so a client refetch can't read
 * pre-transaction state.
 */
class BandDataChanged implements ShouldBroadcast, ShouldDispatchAfterCommit
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public int $bandId,
        public string $model,
        public int $id,
        public string $action,
        public ?array $parent = null,
    ) {}

    public function broadcastOn(): array
    {
        return [new PrivateChannel('band.' . $this->bandId)];
    }

    public function broadcastAs(): string
    {
        return 'band.data-changed';
    }

    public function broadcastWith(): array
    {
        $payload = [
            'model'  => $this->model,
            'id'     => $this->id,
            'action' => $this->action,
        ];
        if ($this->parent !== null) {
            $payload['parent'] = $this->parent;
        }

        return $payload;
    }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=BandDataChangedTest`
Expected: PASS (3 tests)

- [ ] **Step 7: Commit**

```bash
cd /home/eddie/github/TTS && git add phpunit.xml app/Events/BandDataChanged.php tests/Unit/Events/BandDataChangedTest.php && git commit -m "feat(realtime): BandDataChanged thin broadcast event + null broadcast driver in tests"
```

### Task 2: `BroadcastsBandChanges` trait, applied to `Bookings`

**Files:**
- Create: `/home/eddie/github/TTS/app/Models/Traits/BroadcastsBandChanges.php`
- Modify: `/home/eddie/github/TTS/app/Models/Bookings.php` (add trait `use`)
- Test: `/home/eddie/github/TTS/tests/Feature/Broadcasting/BroadcastsBandChangesTest.php`

**Interfaces:**
- Consumes: `App\Events\BandDataChanged` (Task 1 signature).
- Produces: trait `App\Models\Traits\BroadcastsBandChanges` with overridable `protected function broadcastBandId(): ?int` (default `$this->band_id`) and `protected function broadcastParent(): ?array` (default `null`). Task 3 overrides these on other models.

- [ ] **Step 1: Write the failing feature test**

`/home/eddie/github/TTS/tests/Feature/Broadcasting/BroadcastsBandChangesTest.php`:

```php
<?php

namespace Tests\Feature\Broadcasting;

use App\Events\BandDataChanged;
use App\Models\Bands;
use App\Models\Bookings;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Tests\TestCase;

class BroadcastsBandChangesTest extends TestCase
{
    use RefreshDatabase;

    public function test_booking_create_update_delete_each_broadcast_a_band_signal(): void
    {
        Event::fake([BandDataChanged::class]);
        $band = Bands::factory()->create();

        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        Event::assertDispatched(
            BandDataChanged::class,
            fn (BandDataChanged $e) => $e->bandId === $band->id
                && $e->model === 'bookings'
                && $e->id === $booking->id
                && $e->action === 'created'
                && $e->parent === null,
        );

        $booking->update(['name' => 'Renamed booking']);
        Event::assertDispatched(
            BandDataChanged::class,
            fn (BandDataChanged $e) => $e->id === $booking->id && $e->action === 'updated',
        );

        $booking->delete();
        Event::assertDispatched(
            BandDataChanged::class,
            fn (BandDataChanged $e) => $e->id === $booking->id && $e->action === 'deleted',
        );
    }
}
```

Note: if `Bookings` has no `name` column, check `$fillable` in `/home/eddie/github/TTS/app/Models/Bookings.php:33` and update any fillable string column instead (e.g. `venue_name`) — the assertion only cares that an update fires.

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=BroadcastsBandChangesTest`
Expected: FAIL — `Event [App\Events\BandDataChanged] was not dispatched` (booking factory works, nothing broadcasts yet)

- [ ] **Step 3: Implement the trait**

`/home/eddie/github/TTS/app/Models/Traits/BroadcastsBandChanges.php`:

```php
<?php

namespace App\Models\Traits;

use App\Events\BandDataChanged;
use Illuminate\Support\Str;

/**
 * Opt-in realtime signal: any created/updated/deleted on the model dispatches
 * a thin BandDataChanged broadcast to the model's band channel.
 *
 * Models whose band is reached indirectly override broadcastBandId(); child
 * models whose client-side listing is keyed by a parent (comments, event
 * members) override broadcastParent().
 *
 * Wire model name is Str::snake(class_basename()) — keep the mobile registry
 * in lib/shared/providers/band_realtime_provider.dart in sync when adding
 * models.
 */
trait BroadcastsBandChanges
{
    public static function bootBroadcastsBandChanges(): void
    {
        static::created(fn ($model) => $model->broadcastBandChange('created'));
        static::updated(fn ($model) => $model->broadcastBandChange('updated'));
        static::deleted(fn ($model) => $model->broadcastBandChange('deleted'));
    }

    protected function broadcastBandChange(string $action): void
    {
        try {
            $bandId = $this->broadcastBandId();
            if (! $bandId) {
                return;
            }

            BandDataChanged::dispatch(
                (int) $bandId,
                Str::snake(class_basename($this)),
                (int) $this->getKey(),
                $action,
                $this->broadcastParent(),
            );
        } catch (\Throwable $e) {
            // A realtime signal must never break the write that caused it.
            report($e);
        }
    }

    protected function broadcastBandId(): ?int
    {
        return isset($this->band_id) ? (int) $this->band_id : null;
    }

    /**
     * @return array{model: string, id: int}|null
     */
    protected function broadcastParent(): ?array
    {
        return null;
    }
}
```

- [ ] **Step 4: Apply to Bookings**

In `/home/eddie/github/TTS/app/Models/Bookings.php`, add to the existing trait list (it already uses `HasFactory` and `GoogleCalendarWritable` from the same namespace):

```php
use App\Models\Traits\BroadcastsBandChanges;
```

and inside the class body add `BroadcastsBandChanges` to the `use` statement listing the other traits.

- [ ] **Step 5: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=BroadcastsBandChangesTest`
Expected: PASS

- [ ] **Step 6: Run the booking-adjacent suites to catch fallout**

Run: `docker compose exec app php artisan test --filter=Booking`
Expected: PASS (pre-existing failures, if any, must match `staging` — verify with `git stash && docker compose exec app php artisan test --filter=Booking && git stash pop` before blaming the trait)

- [ ] **Step 7: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Models/Traits/BroadcastsBandChanges.php app/Models/Bookings.php tests/Feature/Broadcasting/BroadcastsBandChangesTest.php && git commit -m "feat(realtime): BroadcastsBandChanges trait, applied to Bookings"
```

### Task 3: Apply trait to Events, Rehearsal, Roster, EventMember

**Files:**
- Modify: `/home/eddie/github/TTS/app/Models/Events.php`
- Modify: `/home/eddie/github/TTS/app/Models/Rehearsal.php`
- Modify: `/home/eddie/github/TTS/app/Models/Roster.php`
- Modify: `/home/eddie/github/TTS/app/Models/EventMember.php`
- Test: `/home/eddie/github/TTS/tests/Feature/Broadcasting/BroadcastsBandChangesTest.php` (extend)

**Interfaces:**
- Consumes: trait methods from Task 2 (`broadcastBandId()`, `broadcastParent()`).
- Produces: wire names `events`, `rehearsal`, `roster`, `event_member` (Task 7's mobile registry keys), `event_member` signals carry `parent: {model: 'events', id: <event_id>}`.

- [ ] **Step 1: Extend the feature test with the four models**

Append to `/home/eddie/github/TTS/tests/Feature/Broadcasting/BroadcastsBandChangesTest.php` (inside the class; add the imports `App\Models\EventMember`, `App\Models\Events`, `App\Models\EventTypes`, `App\Models\Rehearsal`, `App\Models\Roster` at the top):

```php
    public function test_event_resolves_band_through_its_eventable(): void
    {
        Event::fake([BandDataChanged::class]);
        $band = Bands::factory()->create();
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        $eventType = EventTypes::factory()->create();

        $event = Events::factory()->create([
            'eventable_id'   => $booking->id,
            'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id'  => $eventType->id,
        ]);

        Event::assertDispatched(
            BandDataChanged::class,
            fn (BandDataChanged $e) => $e->bandId === $band->id
                && $e->model === 'events'
                && $e->id === $event->id
                && $e->action === 'created',
        );
    }

    public function test_event_with_unresolvable_eventable_skips_silently(): void
    {
        Event::fake([BandDataChanged::class]);
        $band = Bands::factory()->create();
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        $eventType = EventTypes::factory()->create();
        $event = Events::factory()->create([
            'eventable_id'   => $booking->id,
            'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id'  => $eventType->id,
        ]);

        // Orphan the event, then touch it: no band → no signal, and no throw.
        $booking->deleteQuietly();
        $event->refresh();

        Event::fake([BandDataChanged::class]); // reset captured events
        $event->update(['notes' => 'orphaned update']);

        Event::assertNotDispatched(BandDataChanged::class);
    }

    public function test_event_member_signal_carries_its_event_as_parent(): void
    {
        Event::fake([BandDataChanged::class]);
        $band = Bands::factory()->create();
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        $eventType = EventTypes::factory()->create();
        $event = Events::factory()->create([
            'eventable_id'   => $booking->id,
            'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id'  => $eventType->id,
        ]);

        $member = EventMember::factory()->create([
            'band_id'  => $band->id,
            'event_id' => $event->id,
        ]);

        Event::assertDispatched(
            BandDataChanged::class,
            fn (BandDataChanged $e) => $e->model === 'event_member'
                && $e->id === $member->id
                && $e->parent === ['model' => 'events', 'id' => $event->id],
        );
    }

    public function test_rehearsal_and_roster_broadcast_with_their_band_id(): void
    {
        Event::fake([BandDataChanged::class]);
        $band = Bands::factory()->create();

        $rehearsal = Rehearsal::factory()->create(['band_id' => $band->id]);
        $roster = Roster::factory()->create(['band_id' => $band->id]);

        Event::assertDispatched(
            BandDataChanged::class,
            fn (BandDataChanged $e) => $e->model === 'rehearsal' && $e->id === $rehearsal->id && $e->bandId === $band->id,
        );
        Event::assertDispatched(
            BandDataChanged::class,
            fn (BandDataChanged $e) => $e->model === 'roster' && $e->id === $roster->id && $e->bandId === $band->id,
        );
    }
```

Column-name caveats to verify while writing (adjust the test, not the models): `Events` update uses a real fillable column (`notes` assumed — check `/home/eddie/github/TTS/app/Models/Events.php` `$fillable`); `Rehearsal`/`Roster` factories may need required fields — mirror whatever existing tests pass to those factories.

- [ ] **Step 2: Run test to verify the new tests fail**

Run: `docker compose exec app php artisan test --filter=BroadcastsBandChangesTest`
Expected: FAIL — the four new tests (no trait on those models yet); Task 2's test still passes.

- [ ] **Step 3: Apply the trait to the four models**

Each model adds the import `use App\Models\Traits\BroadcastsBandChanges;` and appends `BroadcastsBandChanges` to its class-level trait `use`. Then the two overrides:

`/home/eddie/github/TTS/app/Models/Events.php` — `Events` has NO `band_id`; it reaches the band polymorphically. Add inside the class:

```php
    protected function broadcastBandId(): ?int
    {
        $bandId = $this->eventable?->band_id;

        return $bandId ? (int) $bandId : null;
    }
```

(All three eventable types — `Bookings`, `BandEvents`, `Rehearsal` — carry `band_id`. The trait already exists alongside the model's own `booted()`; Laravel calls both, no conflict.)

`/home/eddie/github/TTS/app/Models/EventMember.php` — add inside the class:

```php
    protected function broadcastParent(): ?array
    {
        return $this->event_id
            ? ['model' => 'events', 'id' => (int) $this->event_id]
            : null;
    }
```

`Rehearsal` and `Roster` need no overrides (both have `band_id`).

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=BroadcastsBandChangesTest`
Expected: PASS (6 tests total)

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Models/Events.php app/Models/Rehearsal.php app/Models/Roster.php app/Models/EventMember.php tests/Feature/Broadcasting/BroadcastsBandChangesTest.php && git commit -m "feat(realtime): broadcast band signals from Events, Rehearsal, Roster, EventMember"
```

### Task 4: Channel authorization for `band.{bandId}`

**Files:**
- Modify: `/home/eddie/github/TTS/routes/channels.php`
- Test: `/home/eddie/github/TTS/tests/Feature/Broadcasting/BandChannelAuthTest.php`

**Interfaces:**
- Produces: private channel `band.{bandId}` authorized via the codebase's established `canRead('events', $bandId)` idiom (owners, members with read, and subs — same audience as the two existing channels).

- [ ] **Step 1: Write the failing feature test**

`/home/eddie/github/TTS/tests/Feature/Broadcasting/BandChannelAuthTest.php`:

```php
<?php

namespace Tests\Feature\Broadcasting;

use App\Models\Bands;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BandChannelAuthTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // The pusher driver signs auth responses locally (no network) — give
        // it deterministic creds regardless of the surrounding .env.
        config([
            'broadcasting.default'                    => 'pusher',
            'broadcasting.connections.pusher.key'     => 'test-key',
            'broadcasting.connections.pusher.secret'  => 'test-secret',
            'broadcasting.connections.pusher.app_id'  => 'test-app',
        ]);
    }

    private function authAgainstChannel(User $user, int $bandId)
    {
        $token = $user->createToken('test-device')->plainTextToken;

        return $this->withToken($token)->postJson('/broadcasting/auth', [
            'socket_id'    => '123.456',
            'channel_name' => 'private-band.' . $bandId,
        ]);
    }

    public function test_band_owner_can_subscribe_to_their_band_channel(): void
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $response = $this->authAgainstChannel($user, $band->id);

        $response->assertOk();
        $this->assertIsString($response->json('auth'));
    }

    public function test_non_member_is_rejected(): void
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create(); // user has no relation to it

        $this->authAgainstChannel($user, $band->id)->assertForbidden();
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=BandChannelAuthTest`
Expected: FAIL — owner test gets 403 (channel `band.{bandId}` not registered; Laravel rejects unknown channels)

- [ ] **Step 3: Register the channel**

In `/home/eddie/github/TTS/routes/channels.php`, after the `rehearsal-planner.{sessionId}` block, add:

```php
// Generic band data channel: thin BandDataChanged invalidation signals.
// Same audience idiom as the setlist/planner channels — any user who can
// read the band's events (owners, members, subs). Signals carry no data;
// the API enforces per-resource permissions on the refetch.
Broadcast::channel('band.{bandId}', function ($user, $bandId) {
    return $user->canRead('events', (int) $bandId);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=BandChannelAuthTest`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS && git add routes/channels.php tests/Feature/Broadcasting/BandChannelAuthTest.php && git commit -m "feat(realtime): authorize private-band.{bandId} channel for band members"
```

### Task 5: Backend full suite + PR

**Files:** none new.

- [ ] **Step 1: Run the full backend suite**

Run: `docker compose exec app php artisan test`
Expected: PASS. Known flake caveat: `band_roles` / `CalendarFeedTest` unique-constraint flakes are parallel-run artifacts — re-run those files sequentially before treating them as regressions.

- [ ] **Step 2: Push and open the PR against staging**

```bash
cd /home/eddie/github/TTS && git push -u origin feat/band-realtime-broadcasts && gh pr create --base staging --title "Realtime: thin band-scoped change broadcasts" --body "$(cat <<'EOF'
## Summary
- `BandDataChanged` queued broadcast event: thin `{model, id, action[, parent]}` signal on `private-band.{bandId}`
- Opt-in `BroadcastsBandChanges` model trait (Bookings, Events, Rehearsal, Roster, EventMember); Events resolves band via its eventable, EventMember signals carry their event as `parent`
- `band.{bandId}` channel auth (same `canRead('events', …)` idiom as existing channels)
- `phpunit.xml` forces `BROADCAST_DRIVER=null` so factory-heavy suites never attempt real broadcasts

Consumed by tts_bandmate `feat/band-realtime-invalidation` (provider-invalidation registry). Spec lives in the mobile repo: `docs/superpowers/specs/2026-07-06-band-realtime-invalidation-design.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01YNyzbE8jweH5FLjTMJt1kY
EOF
)"
```

- [ ] **Step 3: Wait for Copilot review and address its comments** (repo convention — the PR is not done until Copilot's auto-review comments are handled).

---

## Mobile tasks (repo `/home/eddie/github/tts_bandmate`, branch `feat/band-realtime-invalidation`)

### Task 6: Shared `PusherConnection` service; port live-setlist and planner onto it

**Files:**
- Create: `/home/eddie/github/tts_bandmate/lib/core/network/pusher_connection.dart`
- Modify: `/home/eddie/github/tts_bandmate/lib/features/setlist/providers/live_session_provider.dart:207-230,345-358`
- Modify: `/home/eddie/github/tts_bandmate/lib/features/rehearsal_planner/providers/rehearsal_planner_provider.dart:46-86`
- Test: `/home/eddie/github/tts_bandmate/test/core/network/pusher_connection_test.dart`

**Interfaces:**
- Produces:
  ```dart
  typedef PusherJsonHandler = void Function(String eventName, Map<String, dynamic> data);
  class PusherConnection {
    Future<Future<void> Function()?> subscribe(String channelName, PusherJsonHandler onEvent);
  }
  Map<String, dynamic>? decodePusherData(dynamic raw);          // pure, exported for tests
  final pusherConnectionProvider = Provider<PusherConnection>(…);
  ```
  Task 7 consumes `pusherConnectionProvider` + `PusherJsonHandler`.

- [ ] **Step 1: Write the failing test for the pure decode helper**

`/home/eddie/github/tts_bandmate/test/core/network/pusher_connection_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/pusher_connection.dart';

void main() {
  group('decodePusherData', () {
    test('decodes a JSON object string', () {
      expect(
        decodePusherData('{"model":"bookings","id":1,"action":"updated"}'),
        {'model': 'bookings', 'id': 1, 'action': 'updated'},
      );
    });

    test('passes through an already-decoded map', () {
      expect(decodePusherData({'a': 1}), {'a': 1});
    });

    test('returns null for null, empty, non-JSON, and non-object payloads', () {
      expect(decodePusherData(null), isNull);
      expect(decodePusherData(''), isNull);
      expect(decodePusherData('not json'), isNull);
      expect(decodePusherData('[1,2]'), isNull);
      expect(decodePusherData(42), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/network/pusher_connection_test.dart`
Expected: FAIL — `pusher_connection.dart` does not exist.

- [ ] **Step 3: Implement the service**

`/home/eddie/github/tts_bandmate/lib/core/network/pusher_connection.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

import '../config/app_config.dart';
import '../storage/secure_storage.dart';
import 'pusher_authorizer.dart';

typedef PusherJsonHandler = void Function(
    String eventName, Map<String, dynamic> data);

/// Decodes a raw Pusher event payload into a JSON object, or null when the
/// payload is absent/malformed/not an object. Pure — unit-tested directly.
Map<String, dynamic>? decodePusherData(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is! String || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Single owner of the app-wide `PusherChannelsFlutter.getInstance()`
/// singleton. Every feature subscribes through here so no feature ever
/// resets or disconnects the socket underneath another (the pre-existing
/// live-setlist provider used to call `disconnect()` on dispose, which
/// would have killed all other subscriptions).
class PusherConnection {
  PusherConnection(this._readToken);

  final Future<String?> Function() _readToken;

  /// Subscribes to [channelName], delivering decoded JSON events to
  /// [onEvent]. Returns an unsubscribe callback, or null when Pusher is
  /// unconfigured or there is no auth token (callers treat that as
  /// "realtime unavailable", exactly like today).
  Future<Future<void> Function()?> subscribe(
      String channelName, PusherJsonHandler onEvent) async {
    final token = await _readToken();
    if (token == null || AppConfig.pusherKey.isEmpty) return null;

    final pusher = PusherChannelsFlutter.getInstance();
    // init/connect are idempotent enough for repeated calls — this mirrors
    // the previous per-feature behavior (both call sites did exactly this).
    await pusher.init(
      apiKey: AppConfig.pusherKey,
      cluster: AppConfig.pusherCluster,
      onAuthorizer: pusherAuthorizer(token),
    );
    await pusher.connect();

    await pusher.subscribe(
      channelName: channelName,
      // The parameter must be typed `dynamic` (not `PusherEvent`): the
      // plugin's `PusherChannel.onEvent` is `Function(dynamic)?` and in AOT
      // builds a `(PusherEvent) => …` literal throws a contravariance
      // TypeError. Cast inside instead.
      onEvent: (dynamic event) {
        final e = event as PusherEvent;
        final data = decodePusherData(e.data);
        if (data == null) return;
        onEvent(e.eventName, data);
      },
    );

    return () => pusher.unsubscribe(channelName: channelName);
  }
}

final pusherConnectionProvider = Provider<PusherConnection>((ref) {
  return PusherConnection(() => ref.read(secureStorageProvider).readToken());
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/network/pusher_connection_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Port the live-setlist provider**

In `/home/eddie/github/tts_bandmate/lib/features/setlist/providers/live_session_provider.dart`:

Remove the imports of `pusher_channels_flutter` and `pusher_authorizer`, and the `_pusher`/`_token` fields; add `import '../../../core/network/pusher_connection.dart';`. Replace `_connectPusher` (lines 209-230), `_onPusherEvent` (232-256), `_disconnectChannel` (345-350) and `_disconnect` (352-358) with:

```dart
  Future<void> Function()? _unsubscribe;

  Future<void> _connectPusher(int sessionId) async {
    _unsubscribe = await ref
        .read(pusherConnectionProvider)
        .subscribe('private-setlist.$sessionId', _onPusherEvent);
  }

  void _onPusherEvent(String eventName, Map<String, dynamic> data) {
    switch (eventName) {
      case 'SetlistQueueAdvanced':
        _handleQueueAdvanced(data);
      case 'SetlistQueueUpdated':
        _handleQueueUpdated(data);
      case 'SetlistSessionStateChanged':
        _handleStateChanged(data);
      case 'SetlistCaptainChanged':
        _handleCaptainChanged(data);
      case 'SetlistQueueingNext':
        // Informational — captain is picking the next song.
        break;
    }
  }

  Future<void> _disconnect() async {
    try {
      await _unsubscribe?.call();
    } catch (_) {}
    _unsubscribe = null;
  }
```

(All four `_handleXxx` methods keep their existing bodies — they already take `Map<String, dynamic>`. The `jsonDecode` block disappears; `decodePusherData` inside the service replaces it. Note the deliberate behavior change: dispose now unsubscribes the channel instead of `disconnect()`-ing the shared socket.)

- [ ] **Step 6: Port the planner binder**

In `/home/eddie/github/tts_bandmate/lib/features/rehearsal_planner/providers/rehearsal_planner_provider.dart` replace the body of `plannerStreamBinderProvider` (lines 46-86) with:

```dart
final plannerStreamBinderProvider = Provider<PlannerStreamBinder>((ref) {
  return (channel, onEvent) async {
    final unsubscribe = await ref
        .read(pusherConnectionProvider)
        .subscribe(channel, (eventName, data) {
      if (eventName != 'planner.stream') return;
      onEvent(data['type'] as String? ?? '', data);
    });
    if (unsubscribe != null) {
      ref.onDispose(() async {
        await unsubscribe();
      });
    }
  };
});
```

Drop the now-unused imports (`dart:convert`, `pusher_channels_flutter`, `app_config.dart`, `pusher_authorizer.dart`, `secure_storage.dart` — keep any still used elsewhere in the file) and add `import '../../../core/network/pusher_connection.dart';`. The long AOT-contravariance doc comment moves into `PusherConnection` (Task 6 Step 3 already carries it); replace it here with a one-line pointer: `// Event plumbing lives in core/network/pusher_connection.dart.`

- [ ] **Step 7: Analyze and run the full mobile suite**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests pass (planner tests override the binder, so they are unaffected; nothing else exercised the removed code paths).

- [ ] **Step 8: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/core/network/pusher_connection.dart lib/features/setlist/providers/live_session_provider.dart lib/features/rehearsal_planner/providers/rehearsal_planner_provider.dart test/core/network/pusher_connection_test.dart && git commit -m "refactor(core): shared PusherConnection service; stop disconnecting the shared socket on setlist dispose"
```

### Task 7: `bandRealtimeProvider` — registry, debounce, subscription lifecycle

**Files:**
- Create: `/home/eddie/github/tts_bandmate/lib/shared/providers/band_realtime_provider.dart`
- Test: `/home/eddie/github/tts_bandmate/test/shared/providers/band_realtime_provider_test.dart`

**Interfaces:**
- Consumes: `pusherConnectionProvider`, `PusherJsonHandler` (Task 6); `selectedBandProvider` (`AsyncNotifierProvider<SelectedBandNotifier, int?>` in `lib/shared/providers/selected_band_provider.dart`).
- Produces:
  ```dart
  typedef BandChannelBinder = Future<Future<void> Function()?> Function(String channelName, PusherJsonHandler onEvent);
  final bandChannelBinderProvider = Provider<BandChannelBinder>(…);       // test seam
  final bandRealtimeDebounceProvider = Provider<Duration>(…);             // test seam (300ms prod)
  final providerInvalidatorProvider = Provider<void Function(ProviderOrFamily)>(…); // test seam
  List<ProviderOrFamily> invalidationTargetsFor(String model);            // pure registry
  final bandRealtimeProvider = NotifierProvider<BandRealtimeNotifier, int?>(…); // state = subscribed band id
  ```
  Task 8 watches `bandRealtimeProvider` from `AppScaffold`.

- [ ] **Step 1: Write the failing tests**

`/home/eddie/github/tts_bandmate/test/shared/providers/band_realtime_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/pusher_connection.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/shared/providers/band_realtime_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class FakeSelectedBand extends SelectedBandNotifier {
  FakeSelectedBand(this.initial);
  final int? initial;

  @override
  Future<int?> build() async => initial;

  void set(int? id) => state = AsyncValue.data(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> subscribedChannels;
  late List<String> unsubscribedChannels;
  late PusherJsonHandler? capturedHandler;
  late List<ProviderOrFamily> invalidated;
  late FakeSelectedBand fakeBand;

  ProviderContainer makeContainer({int? bandId = 7}) {
    subscribedChannels = [];
    unsubscribedChannels = [];
    capturedHandler = null;
    invalidated = [];
    fakeBand = FakeSelectedBand(bandId);
    final container = ProviderContainer(overrides: [
      selectedBandProvider.overrideWith(() => fakeBand),
      bandRealtimeDebounceProvider.overrideWithValue(Duration.zero),
      providerInvalidatorProvider.overrideWithValue((p) => invalidated.add(p)),
      bandChannelBinderProvider.overrideWithValue((channel, onEvent) async {
        subscribedChannels.add(channel);
        capturedHandler = onEvent;
        return () async => unsubscribedChannels.add(channel);
      }),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// Activates the provider and lets the async subscribe settle.
  Future<void> activate(ProviderContainer c) async {
    c.read(bandRealtimeProvider);
    await c.read(selectedBandProvider.future);
    await Future<void>.delayed(Duration.zero);
  }

  test('subscribes to the selected band channel', () async {
    final c = makeContainer();
    await activate(c);

    expect(subscribedChannels, ['private-band.7']);
    expect(c.read(bandRealtimeProvider), 7);
  });

  test('does not subscribe when no band is selected', () async {
    final c = makeContainer(bandId: null);
    await activate(c);

    expect(subscribedChannels, isEmpty);
    expect(c.read(bandRealtimeProvider), isNull);
  });

  test('resubscribes when the band changes', () async {
    final c = makeContainer();
    await activate(c);

    fakeBand.set(9);
    await Future<void>.delayed(Duration.zero);

    expect(unsubscribedChannels, ['private-band.7']);
    expect(subscribedChannels, ['private-band.7', 'private-band.9']);
    expect(c.read(bandRealtimeProvider), 9);
  });

  test('a burst of signals for one model invalidates its targets once', () async {
    final c = makeContainer();
    await activate(c);

    for (var i = 0; i < 3; i++) {
      capturedHandler!('band.data-changed',
          {'model': 'bookings', 'id': i, 'action': 'updated'});
    }
    await Future<void>.delayed(Duration.zero);

    expect(invalidated, containsAll(<ProviderOrFamily>[
      bandBookingsProvider,
      bookingDetailProvider,
      dashboardProvider,
    ]));
    expect(invalidated.length, invalidated.toSet().length,
        reason: 'burst must be debounced into one invalidation per target');
  });

  test('unknown models and foreign event names are ignored', () async {
    final c = makeContainer();
    await activate(c);

    capturedHandler!('band.data-changed', {'model': 'mystery', 'id': 1, 'action': 'created'});
    capturedHandler!('some.other.event', {'model': 'bookings', 'id': 1, 'action': 'created'});
    await Future<void>.delayed(Duration.zero);

    expect(invalidated, isEmpty);
  });

  test('registry maps events, rehearsal, and event_member', () {
    expect(invalidationTargetsFor('events'), contains(bandEventsProvider));
    expect(invalidationTargetsFor('event_member'), contains(eventDetailProvider));
    expect(invalidationTargetsFor('rehearsal'), isNotEmpty);
    expect(invalidationTargetsFor('unknown'), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/providers/band_realtime_provider_test.dart`
Expected: FAIL — `band_realtime_provider.dart` does not exist.

- [ ] **Step 3: Implement the provider**

`/home/eddie/github/tts_bandmate/lib/shared/providers/band_realtime_provider.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/pusher_connection.dart';
import '../../features/bookings/providers/bookings_provider.dart';
import '../../features/dashboard/providers/dashboard_provider.dart';
import '../../features/events/providers/events_provider.dart';
import '../../features/rehearsals/providers/rehearsals_provider.dart';
import 'selected_band_provider.dart';

/// Wire event name — must match BandDataChanged::broadcastAs() on the backend.
const String bandDataChangedEvent = 'band.data-changed';

typedef BandChannelBinder = Future<Future<void> Function()?> Function(
    String channelName, PusherJsonHandler onEvent);

/// Production binder: subscribe through the shared PusherConnection.
/// Overridden in tests to capture the handler.
final bandChannelBinderProvider = Provider<BandChannelBinder>((ref) {
  return (channel, onEvent) =>
      ref.read(pusherConnectionProvider).subscribe(channel, onEvent);
});

/// Debounce window for coalescing signal bursts (e.g. a roster sync touching
/// twenty events) into one refetch per provider. Overridden to zero in tests.
final bandRealtimeDebounceProvider =
    Provider<Duration>((_) => const Duration(milliseconds: 300));

/// Indirection over ref.invalidate so tests can observe which providers a
/// signal invalidates without faking HTTP for every feature repository.
final providerInvalidatorProvider =
    Provider<void Function(ProviderOrFamily)>((ref) => ref.invalidate);

/// Wire model name (backend: Str::snake(class_basename)) → providers to
/// invalidate. Invalidating a family invalidates every member — precise
/// parent-keyed invalidation is deliberately deferred (spec: v1).
List<ProviderOrFamily> invalidationTargetsFor(String model) {
  switch (model) {
    case 'bookings':
      return [
        bandBookingsProvider,
        bookingDetailProvider,
        bookingsWindowProvider,
        bookingDateStatusesProvider,
        bookingDateInfoProvider,
        bookingHistoryProvider,
        dashboardProvider,
      ];
    case 'events':
    case 'event_member':
    case 'roster':
      return [
        bandEventsProvider,
        eventDetailProvider,
        eventSubsProvider,
        dashboardProvider,
      ];
    case 'rehearsal':
      return [
        schedulesProvider,
        rehearsalDetailProvider,
        rehearsalDetailByKeyProvider,
        dashboardProvider,
      ];
    default:
      return const [];
  }
}

/// All models the registry knows — used for the blanket invalidation after an
/// app-resume reconnect, when signals may have been missed.
const List<String> _allRegisteredModels = [
  'bookings',
  'events',
  'rehearsal',
];

/// Subscribes to the selected band's realtime channel and turns thin
/// `band.data-changed` signals into Riverpod invalidations. State is the
/// currently subscribed band id (null = not subscribed).
///
/// Must be watch()ed by an always-mounted widget (AppScaffold) to stay alive.
class BandRealtimeNotifier extends Notifier<int?> {
  Future<void> Function()? _unsubscribe;
  Timer? _flushTimer;
  final Set<String> _pendingModels = {};
  AppLifecycleListener? _lifecycle;

  @override
  int? build() {
    ref.onDispose(_teardown);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.listen(selectedBandProvider, (previous, next) {
      _resubscribe(next.value);
    }, fireImmediately: true);
    return null;
  }

  Future<void> _resubscribe(int? bandId) async {
    await _unsubscribe?.call();
    _unsubscribe = null;
    state = null;
    if (bandId == null) return;

    final binder = ref.read(bandChannelBinderProvider);
    _unsubscribe = await binder('private-band.$bandId', _onSignal);
    if (_unsubscribe != null) state = bandId;
  }

  void _onSignal(String eventName, Map<String, dynamic> data) {
    if (eventName != bandDataChangedEvent) return;
    final model = data['model'];
    if (model is! String || invalidationTargetsFor(model).isEmpty) return;

    _pendingModels.add(model);
    _flushTimer ??= Timer(ref.read(bandRealtimeDebounceProvider), _flush);
  }

  void _flush() {
    _flushTimer = null;
    final invalidate = ref.read(providerInvalidatorProvider);
    final targets = <ProviderOrFamily>{
      for (final model in _pendingModels) ...invalidationTargetsFor(model),
    };
    _pendingModels.clear();
    targets.forEach(invalidate);
  }

  /// The socket dies while backgrounded; signals are pure invalidation, so
  /// instead of replaying we refetch everything band-scoped once and
  /// resubscribe (spec: Resilience).
  void _onResume() {
    final bandId = state;
    if (bandId == null) return;
    _pendingModels.addAll(_allRegisteredModels);
    _flushTimer ??= Timer(ref.read(bandRealtimeDebounceProvider), _flush);
    _resubscribe(bandId);
  }

  void _teardown() {
    _lifecycle?.dispose();
    _flushTimer?.cancel();
    _unsubscribe?.call();
  }
}

final bandRealtimeProvider = NotifierProvider<BandRealtimeNotifier, int?>(
  BandRealtimeNotifier.new,
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/providers/band_realtime_provider_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/shared/providers/band_realtime_provider.dart test/shared/providers/band_realtime_provider_test.dart && git commit -m "feat(realtime): bandRealtimeProvider — band channel signals invalidate feature providers"
```

### Task 8: Wire into AppScaffold, full verification, PR

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/shared/widgets/app_scaffold.dart:89-92`

**Interfaces:**
- Consumes: `bandRealtimeProvider` (Task 7).

- [ ] **Step 1: Keep the provider alive from AppScaffold**

In `/home/eddie/github/tts_bandmate/lib/shared/widgets/app_scaffold.dart`, add the import:

```dart
import '../providers/band_realtime_provider.dart';
```

and in the `build` method of the scaffold state (line ~89), immediately after `final connectivityAsync = ref.watch(connectivityProvider);`, add:

```dart
    // Keeps the band realtime subscription alive for the whole shell.
    ref.watch(bandRealtimeProvider);
```

- [ ] **Step 2: Analyze + full test suite**

Run: `flutter analyze && flutter test`
Expected: analyze clean, all tests pass.

- [ ] **Step 3: Commit and push**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/shared/widgets/app_scaffold.dart && git commit -m "feat(realtime): activate band realtime subscription from the app shell" && git push -u origin feat/band-realtime-invalidation
```

- [ ] **Step 4: On-device verification (after the backend branch is running locally)**

With the backend branch checked out and `docker compose up` running in `/home/eddie/github/TTS`: use the run-on-device skill to launch the app against the local backend, then edit a booking via the web UI (or a second device) and confirm the bookings list refreshes without a manual pull. This is the end-to-end proof the thin-signal loop closes.

- [ ] **Step 5: Open the PR against main**

```bash
cd /home/eddie/github/tts_bandmate && gh pr create --base main --title "Realtime: band-scoped provider invalidation" --body "$(cat <<'EOF'
## Summary
- Shared `PusherConnection` service in core/ — single owner of the plugin singleton; live-setlist and planner ported onto it (setlist dispose no longer disconnects the shared socket)
- `bandRealtimeProvider`: subscribes to `private-band.{bandId}`, debounces thin `band.data-changed` signals, invalidates the mapped feature providers (bookings/events/rehearsals/dashboard)
- Registry + debounce + lifecycle covered by unit tests; app-resume blanket refetch per spec

Pairs with TTS PR `feat/band-realtime-broadcasts` (must be deployed for prod signals; harmless without it). Spec: `docs/superpowers/specs/2026-07-06-band-realtime-invalidation-design.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01YNyzbE8jweH5FLjTMJt1kY
EOF
)"
```

- [ ] **Step 6: Wait for Copilot review and address its comments** (repo convention).
