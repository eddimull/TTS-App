# Comments & Chat — Laravel Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unified conversation system (event/rehearsal/booking comment threads, per-band group channel, global 1:1 DMs) with realtime signals, image attachments, and push notifications, exposed via the `/api/mobile` API.

**Architecture:** Three-table core (`conversations` / `conversation_participants` / `messages`, plus `message_attachments`) with a single `unique_key` column enforcing one-conversation-per-target at the DB level. Access is derived per-request by `ConversationPolicy` (never stored). Realtime rides the existing `BandDataChanged` thin-signal trait for band-attached threads, a new per-user thin signal for DMs, and a new `private-conversation.{id}` channel for open threads. Spec: `docs/superpowers/specs/2026-07-12-comments-chat-design.md` (mobile repo).

**Tech Stack:** Laravel 10, Sanctum token auth, Spatie permissions (team-scoped), Pusher broadcasting (queued via Horizon), FCM via `SendUserPush`.

## Global Constraints

- Repo: `/home/eddie/github/TTS`. Branch off `staging`; PRs target `staging` (never master).
- NEVER run `php`/`artisan`/`composer` on the host — always `docker compose exec app php artisan …` (run from `/home/eddie/github/TTS`).
- Run new test files directly (`php artisan test tests/Feature/...`), not the whole suite — `band_roles`/`CalendarFeedTest` have known parallel-run flakes.
- Wire model name for realtime signals is `Str::snake(class_basename())` → `message`. The Flutter registry (`lib/shared/providers/band_realtime_provider.dart`) must be kept in sync (separate mobile plan).
- Every commit message ends with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- All new mobile endpoints live in `routes/api.php` inside the existing `Route::prefix('mobile')` → `Route::middleware('auth:sanctum')` group, controllers in `App\Http\Controllers\Api\Mobile`.
- Access rules (from spec): DM = participants only, creatable when the two users share ≥1 band in any role; band channel = owners + members (never subs); topic(event/rehearsal) = owners + members with read permission, plus subs entitled to that specific event; topic(booking) = owners + members with `read:bookings` only. Moderation (`delete` others' messages) = owner or `moderate:chat`, band/topic only. Edit = author only, always.
- Canonicalization: a topic conversation for an `Events` row whose `eventable` is a `Rehearsal` attaches to the `Rehearsal` instead. Bookings are NOT canonicalized.

---

### Task 1: Branch, migrations, models, factories

**Files:**
- Create: `database/migrations/2026_07_12_000001_create_chat_tables.php`
- Create: `database/migrations/2026_07_12_000002_add_moderate_chat_permission.php`
- Create: `app/Models/Conversation.php`, `app/Models/ConversationParticipant.php`, `app/Models/Message.php`, `app/Models/MessageAttachment.php`
- Create: `database/factories/ConversationFactory.php`, `database/factories/MessageFactory.php`
- Test: `tests/Feature/Api/Mobile/Chat/ChatModelsTest.php`, helper trait `tests/Feature/Api/Mobile/Chat/ChatTestHelpers.php`

**Interfaces:**
- Produces: `Conversation` (constants `TYPE_DM|TYPE_BAND|TYPE_TOPIC`; statics `dmKeyFor(int,int): string`, `bandKeyFor(int): string`, `topicKeyFor(Model): string`; relations `conversable()`, `band()`, `participants()`, `messages()`), `ConversationParticipant` (`conversation_id`, `user_id`, `last_read_at` datetime cast), `Message` (SoftDeletes; relations `conversation()`, `user()`, `attachments()`), `MessageAttachment` (`message()`). All later tasks consume these.

- [ ] **Step 1: Create the feature branch off staging**

```bash
cd /home/eddie/github/TTS && git checkout staging && git pull && git checkout -b feat/comments-chat
```

- [ ] **Step 2: Write the failing test**

`tests/Feature/Api/Mobile/Chat/ChatTestHelpers.php` (shared by every chat test file):

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Models\Bands;
use App\Models\BandSubs;
use App\Models\Bookings;
use App\Models\EventMember;
use App\Models\Events;
use App\Models\EventTypes;
use App\Models\Rehearsal;
use App\Models\User;

trait ChatTestHelpers
{
    /** @return array{0: User, 1: Bands} */
    protected function makeOwnerWithBand(): array
    {
        $owner = User::factory()->create();
        $band  = Bands::factory()->create();
        $band->owners()->create(['user_id' => $owner->id]);

        return [$owner, $band];
    }

    protected function makeMember(Bands $band, array $permissions = ['read:events']): User
    {
        $member = User::factory()->create();
        $band->members()->create(['user_id' => $member->id]);

        setPermissionsTeamId($band->id);
        foreach ($permissions as $permission) {
            $member->givePermissionTo($permission);
        }
        setPermissionsTeamId(0);

        return $member;
    }

    protected function makeBookingEvent(Bands $band): Events
    {
        $booking = Bookings::factory()->create(['band_id' => $band->id]);

        return Events::factory()->create([
            'eventable_id'   => $booking->id,
            'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id'  => EventTypes::factory()->create()->id,
            'date'           => now()->addDays(7)->format('Y-m-d'),
            'title'          => 'Test Gig',
        ]);
    }

    /** @return array{0: Rehearsal, 1: Events} */
    protected function makeRehearsalEvent(Bands $band): array
    {
        $rehearsal = Rehearsal::factory()->create(['band_id' => $band->id]);
        $event     = Events::factory()->create([
            'eventable_id'   => $rehearsal->id,
            'eventable_type' => 'App\\Models\\Rehearsal',
            'event_type_id'  => EventTypes::factory()->create()->id,
            'date'           => now()->addDays(7)->format('Y-m-d'),
            'title'          => 'Rehearsal',
        ]);

        return [$rehearsal, $event];
    }

    /** A sub-only user assigned to $event (event_members path, like MobileSubEventsParityTest). */
    protected function makeSubAssignedTo(Bands $band, Events $event): User
    {
        $sub = User::factory()->create();
        BandSubs::firstOrCreate(['user_id' => $sub->id, 'band_id' => $band->id]);
        EventMember::create([
            'event_id'         => $event->id,
            'band_id'          => $band->id,
            'user_id'          => $sub->id,
            'roster_member_id' => null,
            'name'             => $sub->name,
        ]);

        return $sub;
    }

    /** A sub of the band NOT assigned to any event. */
    protected function makeUnassignedSub(Bands $band): User
    {
        $sub = User::factory()->create();
        BandSubs::firstOrCreate(['user_id' => $sub->id, 'band_id' => $band->id]);

        return $sub;
    }
}
```

`tests/Feature/Api/Mobile/Chat/ChatModelsTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Models\Conversation;
use App\Models\Message;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ChatModelsTest extends TestCase
{
    use RefreshDatabase, ChatTestHelpers;

    public function test_key_builders_are_deterministic(): void
    {
        $this->assertSame('dm:3:9', Conversation::dmKeyFor(9, 3));
        $this->assertSame('dm:3:9', Conversation::dmKeyFor(3, 9));
        $this->assertSame('band:5', Conversation::bandKeyFor(5));

        [, $band] = $this->makeOwnerWithBand();
        $event = $this->makeBookingEvent($band);
        $this->assertSame('topic:App\\Models\\Events:' . $event->id, Conversation::topicKeyFor($event));
    }

    public function test_unique_key_is_enforced_at_the_database(): void
    {
        [, $band] = $this->makeOwnerWithBand();
        Conversation::create([
            'type' => Conversation::TYPE_BAND, 'band_id' => $band->id,
            'unique_key' => Conversation::bandKeyFor($band->id),
        ]);

        $this->expectException(QueryException::class);
        Conversation::create([
            'type' => Conversation::TYPE_BAND, 'band_id' => $band->id,
            'unique_key' => Conversation::bandKeyFor($band->id),
        ]);
    }

    public function test_message_soft_deletes_and_relations_work(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $conversation = Conversation::create([
            'type' => Conversation::TYPE_BAND, 'band_id' => $band->id,
            'unique_key' => Conversation::bandKeyFor($band->id),
        ]);
        $conversation->participants()->create(['user_id' => $owner->id, 'last_read_at' => now()]);
        $message = $conversation->messages()->create(['user_id' => $owner->id, 'body' => 'hello']);

        $this->assertSame($conversation->id, $message->conversation->id);
        $this->assertSame($owner->id, $message->user->id);
        $this->assertCount(1, $conversation->participants);

        $message->delete();
        $this->assertSoftDeleted('messages', ['id' => $message->id]);
        $this->assertCount(1, $conversation->messages()->withTrashed()->get());
    }

    public function test_moderate_chat_permission_exists(): void
    {
        $this->assertDatabaseHas('permissions', ['name' => 'moderate:chat', 'guard_name' => 'web']);
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ChatModelsTest.php
```

Expected: FAIL — `Class "App\Models\Conversation" not found`.

- [ ] **Step 4: Write the migrations**

`database/migrations/2026_07_12_000001_create_chat_tables.php`:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('conversations', function (Blueprint $table) {
            $table->id();
            $table->string('type', 16); // dm | band | topic
            $table->foreignId('band_id')->nullable()->constrained('bands')->cascadeOnDelete();
            $table->string('conversable_type')->nullable();
            $table->unsignedBigInteger('conversable_id')->nullable();
            // Deterministic identity: "dm:{lo}:{hi}" | "band:{bandId}" |
            // "topic:{morphClass}:{id}" — DB-level one-conversation-per-target
            // for all three types with a single unique column.
            $table->string('unique_key')->unique();
            $table->timestamps();
            $table->index(['conversable_type', 'conversable_id']);
            $table->index('band_id');
        });

        Schema::create('conversation_participants', function (Blueprint $table) {
            $table->id();
            $table->foreignId('conversation_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->timestamp('last_read_at')->nullable();
            $table->timestamps();
            $table->unique(['conversation_id', 'user_id']);
            $table->index('user_id');
        });

        Schema::create('messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('conversation_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained();
            $table->text('body')->nullable(); // nullable: image-only messages
            $table->timestamp('edited_at')->nullable();
            $table->softDeletes();
            $table->timestamps();
            $table->index(['conversation_id', 'id']);
        });

        Schema::create('message_attachments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('message_id')->constrained()->cascadeOnDelete();
            $table->string('path');
            $table->string('disk', 32);
            $table->string('mime', 64);
            $table->unsignedInteger('width')->nullable();
            $table->unsignedInteger('height')->nullable();
            $table->unsignedBigInteger('size_bytes');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('message_attachments');
        Schema::dropIfExists('messages');
        Schema::dropIfExists('conversation_participants');
        Schema::dropIfExists('conversations');
    }
};
```

`database/migrations/2026_07_12_000002_add_moderate_chat_permission.php` (mirrors `2026_04_28_111143_add_questionnaires_permission.php`):

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\PermissionRegistrar;

return new class extends Migration
{
    public function up(): void
    {
        app()[PermissionRegistrar::class]->forgetCachedPermissions();
        Permission::firstOrCreate(['name' => 'moderate:chat', 'guard_name' => 'web']);
    }

    public function down(): void
    {
        Permission::where('name', 'moderate:chat')->where('guard_name', 'web')->delete();
        app()[PermissionRegistrar::class]->forgetCachedPermissions();
    }
};
```

- [ ] **Step 5: Write the models and factories**

`app/Models/Conversation.php`:

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\MorphTo;

class Conversation extends Model
{
    use HasFactory;

    public const TYPE_DM    = 'dm';
    public const TYPE_BAND  = 'band';
    public const TYPE_TOPIC = 'topic';

    protected $fillable = ['type', 'band_id', 'conversable_type', 'conversable_id', 'unique_key'];

    public static function dmKeyFor(int $userA, int $userB): string
    {
        return 'dm:' . min($userA, $userB) . ':' . max($userA, $userB);
    }

    public static function bandKeyFor(int $bandId): string
    {
        return 'band:' . $bandId;
    }

    public static function topicKeyFor(Model $conversable): string
    {
        return 'topic:' . get_class($conversable) . ':' . $conversable->getKey();
    }

    public function conversable(): MorphTo
    {
        return $this->morphTo();
    }

    public function band()
    {
        return $this->belongsTo(Bands::class, 'band_id');
    }

    public function participants()
    {
        return $this->hasMany(ConversationParticipant::class);
    }

    public function messages()
    {
        return $this->hasMany(Message::class);
    }
}
```

`app/Models/ConversationParticipant.php`:

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ConversationParticipant extends Model
{
    protected $fillable = ['conversation_id', 'user_id', 'last_read_at'];

    protected $casts = ['last_read_at' => 'datetime'];

    public function conversation()
    {
        return $this->belongsTo(Conversation::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
```

`app/Models/Message.php` (the `BroadcastsBandChanges` trait is added in Task 8, not here):

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Message extends Model
{
    use HasFactory, SoftDeletes;

    protected $fillable = ['conversation_id', 'user_id', 'body', 'edited_at'];

    protected $casts = ['edited_at' => 'datetime'];

    public function conversation()
    {
        return $this->belongsTo(Conversation::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function attachments()
    {
        return $this->hasMany(MessageAttachment::class);
    }
}
```

`app/Models/MessageAttachment.php`:

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MessageAttachment extends Model
{
    protected $fillable = ['message_id', 'path', 'disk', 'mime', 'width', 'height', 'size_bytes'];

    public function message()
    {
        return $this->belongsTo(Message::class);
    }
}
```

`database/factories/ConversationFactory.php`:

```php
<?php

namespace Database\Factories;

use App\Models\Conversation;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

class ConversationFactory extends Factory
{
    protected $model = Conversation::class;

    public function definition(): array
    {
        return [
            'type'       => Conversation::TYPE_BAND,
            'band_id'    => null,
            'unique_key' => 'test:' . Str::uuid(),
        ];
    }
}
```

`database/factories/MessageFactory.php`:

```php
<?php

namespace Database\Factories;

use App\Models\Conversation;
use App\Models\Message;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

class MessageFactory extends Factory
{
    protected $model = Message::class;

    public function definition(): array
    {
        return [
            'conversation_id' => Conversation::factory(),
            'user_id'         => User::factory(),
            'body'            => $this->faker->sentence(),
        ];
    }
}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ChatModelsTest.php
```

Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
cd /home/eddie/github/TTS && git add database/migrations/2026_07_12_000001_create_chat_tables.php database/migrations/2026_07_12_000002_add_moderate_chat_permission.php app/Models/Conversation.php app/Models/ConversationParticipant.php app/Models/Message.php app/Models/MessageAttachment.php database/factories/ConversationFactory.php database/factories/MessageFactory.php tests/Feature/Api/Mobile/Chat/
git commit -m "feat(chat): conversations, participants, messages, attachments schema + models

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: ConversationService (canonicalization + find-or-create)

**Files:**
- Create: `app/Services/Chat/ConversationService.php`
- Test: `tests/Feature/Api/Mobile/Chat/ConversationServiceTest.php`

**Interfaces:**
- Consumes: `Conversation` key builders and relations (Task 1).
- Produces: `ConversationService` with `canonicalTarget(Model): Model`, `topicFor(Model): Conversation`, `bandChannelFor(Bands): Conversation`, `dmBetween(User, User): Conversation`, `canDm(User, User): bool`, `touchParticipant(Conversation, User): ConversationParticipant`. Controllers (Tasks 4–6) call these.

- [ ] **Step 1: Write the failing test**

`tests/Feature/Api/Mobile/Chat/ConversationServiceTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Models\Conversation;
use App\Services\Chat\ConversationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ConversationServiceTest extends TestCase
{
    use RefreshDatabase, ChatTestHelpers;

    private ConversationService $service;

    protected function setUp(): void
    {
        parent::setUp();
        $this->service = app(ConversationService::class);
    }

    public function test_event_wrapping_a_rehearsal_canonicalizes_to_the_rehearsal(): void
    {
        [, $band] = $this->makeOwnerWithBand();
        [$rehearsal, $event] = $this->makeRehearsalEvent($band);

        $viaEvent     = $this->service->topicFor($event);
        $viaRehearsal = $this->service->topicFor($rehearsal);

        $this->assertSame($viaEvent->id, $viaRehearsal->id, 'both entry points must reach ONE thread');
        $this->assertSame('App\\Models\\Rehearsal', $viaEvent->conversable_type);
        $this->assertSame($rehearsal->id, (int) $viaEvent->conversable_id);
        $this->assertSame($band->id, (int) $viaEvent->band_id);
    }

    public function test_booking_event_topic_attaches_to_the_event_not_the_booking(): void
    {
        [, $band] = $this->makeOwnerWithBand();
        $event = $this->makeBookingEvent($band);

        $topic = $this->service->topicFor($event);

        $this->assertSame('App\\Models\\Events', $topic->conversable_type);
        $this->assertSame($event->id, (int) $topic->conversable_id);
        $this->assertSame($band->id, (int) $topic->band_id);
    }

    public function test_booking_topic_is_separate_from_its_events_topic(): void
    {
        [, $band] = $this->makeOwnerWithBand();
        $event   = $this->makeBookingEvent($band);
        $booking = $event->eventable;

        $this->assertNotSame(
            $this->service->topicFor($booking)->id,
            $this->service->topicFor($event)->id,
        );
    }

    public function test_topic_for_is_idempotent(): void
    {
        [, $band] = $this->makeOwnerWithBand();
        $event = $this->makeBookingEvent($band);

        $this->assertSame($this->service->topicFor($event)->id, $this->service->topicFor($event)->id);
        $this->assertSame(1, Conversation::count());
    }

    public function test_band_channel_is_one_per_band(): void
    {
        [, $band] = $this->makeOwnerWithBand();

        $a = $this->service->bandChannelFor($band);
        $b = $this->service->bandChannelFor($band);

        $this->assertSame($a->id, $b->id);
        $this->assertSame(Conversation::TYPE_BAND, $a->type);
        $this->assertSame($band->id, (int) $a->band_id);
    }

    public function test_dm_is_one_global_thread_per_user_pair_with_both_participants(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);

        $a = $this->service->dmBetween($owner, $member);
        $b = $this->service->dmBetween($member, $owner); // reversed order

        $this->assertSame($a->id, $b->id);
        $this->assertNull($a->band_id);
        $this->assertSame(Conversation::TYPE_DM, $a->type);
        $this->assertEqualsCanonicalizing(
            [$owner->id, $member->id],
            $a->participants()->pluck('user_id')->all(),
        );
    }

    public function test_can_dm_requires_a_shared_band(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member   = $this->makeMember($band);
        $event    = $this->makeBookingEvent($band);
        $sub      = $this->makeSubAssignedTo($band, $event);
        $stranger = \App\Models\User::factory()->create();

        $this->assertTrue($this->service->canDm($owner, $member));
        $this->assertTrue($this->service->canDm($member, $sub), 'member can DM a sub of their band');
        $this->assertTrue($this->service->canDm($sub, $member), 'sub can DM a member of a band they sub for');
        $this->assertFalse($this->service->canDm($owner, $stranger));
        $this->assertFalse($this->service->canDm($owner, $owner), 'no self-DM');
    }

    public function test_touch_participant_upserts_and_bumps_last_read(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = $this->service->bandChannelFor($band);

        $first = $this->service->touchParticipant($channel, $owner);
        $this->assertNotNull($first->last_read_at);

        $again = $this->service->touchParticipant($channel, $owner);
        $this->assertSame($first->id, $again->id, 'no duplicate participant row');
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ConversationServiceTest.php
```

Expected: FAIL — `Class "App\Services\Chat\ConversationService" not found`.

- [ ] **Step 3: Write the service**

`app/Services/Chat/ConversationService.php`:

```php
<?php

namespace App\Services\Chat;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\Conversation;
use App\Models\ConversationParticipant;
use App\Models\Events;
use App\Models\Rehearsal;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\UniqueConstraintViolationException;

class ConversationService
{
    /**
     * Canonicalization rule (spec): an Events row wrapping a Rehearsal shares
     * the rehearsal's thread, so the event screen and rehearsal screen reach
     * ONE conversation. Bookings are NOT collapsed — a booking's thread is a
     * different discussion context than its performance events'.
     */
    public function canonicalTarget(Model $target): Model
    {
        if ($target instanceof Events && $target->eventable instanceof Rehearsal) {
            return $target->eventable;
        }

        return $target;
    }

    public function topicFor(Model $target): Conversation
    {
        $target = $this->canonicalTarget($target);

        $bandId = match (true) {
            $target instanceof Events => $target->eventable?->band_id,
            $target instanceof Rehearsal, $target instanceof Bookings => $target->band_id,
            default => null,
        };

        abort_if($bandId === null, 404, 'Band not found for this topic.');

        return $this->firstOrCreateByKey([
            'type'             => Conversation::TYPE_TOPIC,
            'band_id'          => (int) $bandId,
            'conversable_type' => get_class($target),
            'conversable_id'   => $target->getKey(),
            'unique_key'       => Conversation::topicKeyFor($target),
        ]);
    }

    public function bandChannelFor(Bands $band): Conversation
    {
        return $this->firstOrCreateByKey([
            'type'       => Conversation::TYPE_BAND,
            'band_id'    => $band->id,
            'unique_key' => Conversation::bandKeyFor($band->id),
        ]);
    }

    public function dmBetween(User $a, User $b): Conversation
    {
        $conversation = $this->firstOrCreateByKey([
            'type'       => Conversation::TYPE_DM,
            'unique_key' => Conversation::dmKeyFor($a->id, $b->id),
        ]);

        // DM participant rows are explicit (they ARE the access list).
        foreach ([$a->id, $b->id] as $userId) {
            ConversationParticipant::firstOrCreate([
                'conversation_id' => $conversation->id,
                'user_id'         => $userId,
            ]);
        }

        return $conversation;
    }

    /**
     * Two users may DM when they share at least one band in any role
     * (owner/member/sub). Self-DM is not allowed.
     */
    public function canDm(User $a, User $b): bool
    {
        if ($a->id === $b->id) {
            return false;
        }

        $aBandIds = $a->allBands()->pluck('id');
        $bBandIds = $b->allBands()->pluck('id');

        return $aBandIds->intersect($bBandIds)->isNotEmpty();
    }

    /**
     * Lazily record that $user is in the thread and mark it read now.
     * Access itself is derived by ConversationPolicy — this row only powers
     * unread counts and read receipts.
     */
    public function touchParticipant(Conversation $conversation, User $user): ConversationParticipant
    {
        $participant = ConversationParticipant::firstOrCreate([
            'conversation_id' => $conversation->id,
            'user_id'         => $user->id,
        ]);

        $participant->forceFill(['last_read_at' => now()])->save();

        return $participant;
    }

    /** firstOrCreate with the unique_key race resolved by re-fetch. */
    private function firstOrCreateByKey(array $attributes): Conversation
    {
        $existing = Conversation::where('unique_key', $attributes['unique_key'])->first();
        if ($existing) {
            return $existing;
        }

        try {
            return Conversation::create($attributes);
        } catch (UniqueConstraintViolationException) {
            return Conversation::where('unique_key', $attributes['unique_key'])->firstOrFail();
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ConversationServiceTest.php
```

Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Services/Chat/ConversationService.php tests/Feature/Api/Mobile/Chat/ConversationServiceTest.php
git commit -m "feat(chat): ConversationService — canonicalized find-or-create for dm/band/topic threads

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: ConversationPolicy + User entitlement helpers

**Files:**
- Modify: `app/Models/User.php` (add two methods after `canWrite()`, around line 226)
- Create: `app/Policies/ConversationPolicy.php`
- Test: `tests/Feature/Api/Mobile/Chat/ConversationPolicyTest.php`

**Interfaces:**
- Consumes: `ConversationService` (Task 2), `Conversation` (Task 1).
- Produces: `User::isEntitledToEvent(int $eventId): bool`, `User::canModerateChat(int $bandId): bool`, `ConversationPolicy` with `view(User, Conversation): bool`, `post(User, Conversation): bool`, `moderate(User, Conversation): bool`. Auto-discovered by Laravel (App\Models\Conversation → App\Policies\ConversationPolicy). Controllers use `$this->authorize('view'|'post'|'moderate', $conversation)`; the `conversation.{id}` broadcast channel (Task 8) uses `$user->can('view', $conversation)`.

- [ ] **Step 1: Write the failing test**

`tests/Feature/Api/Mobile/Chat/ConversationPolicyTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Models\User;
use App\Services\Chat\ConversationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ConversationPolicyTest extends TestCase
{
    use RefreshDatabase, ChatTestHelpers;

    private ConversationService $service;

    protected function setUp(): void
    {
        parent::setUp();
        $this->service = app(ConversationService::class);
    }

    // ── DM ───────────────────────────────────────────────────────────

    public function test_dm_is_visible_only_to_its_participants(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member   = $this->makeMember($band);
        $outsider = User::factory()->create();

        $dm = $this->service->dmBetween($owner, $member);

        $this->assertTrue($owner->can('view', $dm));
        $this->assertTrue($member->can('post', $dm));
        $this->assertFalse($outsider->can('view', $dm));
        $this->assertFalse($owner->can('moderate', $dm), 'DMs are never moderatable');
    }

    // ── Band channel ─────────────────────────────────────────────────

    public function test_band_channel_admits_owner_and_member_but_never_subs(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $event  = $this->makeBookingEvent($band);
        $sub    = $this->makeSubAssignedTo($band, $event);

        $channel = $this->service->bandChannelFor($band);

        $this->assertTrue($owner->can('view', $channel));
        $this->assertTrue($member->can('view', $channel));
        $this->assertTrue($member->can('post', $channel));
        $this->assertFalse($sub->can('view', $channel), 'subs never see the band channel');
    }

    // ── Topic: event ─────────────────────────────────────────────────

    public function test_event_topic_admits_members_with_read_events_and_entitled_subs_only(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $memberWithRead    = $this->makeMember($band, ['read:events']);
        $memberWithoutRead = $this->makeMember($band, []);
        $event         = $this->makeBookingEvent($band);
        $otherEvent    = $this->makeBookingEvent($band);
        $entitledSub   = $this->makeSubAssignedTo($band, $event);
        $unentitledSub = $this->makeSubAssignedTo($band, $otherEvent);

        $topic = $this->service->topicFor($event);

        $this->assertTrue($owner->can('view', $topic));
        $this->assertTrue($memberWithRead->can('post', $topic));
        $this->assertFalse($memberWithoutRead->can('view', $topic));
        $this->assertTrue($entitledSub->can('view', $topic), 'sub invited to THIS event may comment');
        $this->assertTrue($entitledSub->can('post', $topic));
        $this->assertFalse($unentitledSub->can('view', $topic), 'sub on a DIFFERENT event may not');
    }

    // ── Topic: rehearsal (canonicalized) ─────────────────────────────

    public function test_rehearsal_topic_uses_rehearsal_read_for_members_and_event_entitlement_for_subs(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band, ['read:rehearsals']);
        $memberEventsOnly = $this->makeMember($band, ['read:events']);
        [, $rehearsalEvent] = $this->makeRehearsalEvent($band);
        $entitledSub = $this->makeSubAssignedTo($band, $rehearsalEvent);

        $topic = $this->service->topicFor($rehearsalEvent); // canonicalizes to Rehearsal

        $this->assertTrue($owner->can('view', $topic));
        $this->assertTrue($member->can('view', $topic));
        $this->assertFalse($memberEventsOnly->can('view', $topic), 'rehearsal topics need read:rehearsals');
        $this->assertTrue($entitledSub->can('view', $topic), 'sub on the wrapping event reaches the rehearsal thread');
    }

    // ── Topic: booking ───────────────────────────────────────────────

    public function test_booking_topic_requires_read_bookings_and_always_excludes_subs(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $memberWithBookings = $this->makeMember($band, ['read:bookings']);
        $memberEventsOnly   = $this->makeMember($band, ['read:events']);
        $event = $this->makeBookingEvent($band);
        $sub   = $this->makeSubAssignedTo($band, $event);

        $topic = $this->service->topicFor($event->eventable);

        $this->assertTrue($owner->can('view', $topic));
        $this->assertTrue($memberWithBookings->can('view', $topic));
        $this->assertFalse($memberEventsOnly->can('view', $topic));
        $this->assertFalse($sub->can('view', $topic), 'subs can never read booking threads');
    }

    // ── Moderation ───────────────────────────────────────────────────

    public function test_moderate_requires_ownership_or_the_moderate_chat_permission(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $plainMember = $this->makeMember($band);
        $moderator   = $this->makeMember($band, ['read:events', 'moderate:chat']);

        $channel = $this->service->bandChannelFor($band);

        $this->assertTrue($owner->can('moderate', $channel));
        $this->assertTrue($moderator->can('moderate', $channel));
        $this->assertFalse($plainMember->can('moderate', $channel));
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ConversationPolicyTest.php
```

Expected: FAIL — every `can(...)` returns false (no policy exists yet), first failure in `test_dm_is_visible_only_to_its_participants`.

- [ ] **Step 3: Add the User helpers**

In `app/Models/User.php`, directly after the closing brace of `canWrite()` (~line 226), insert:

```php
    /**
     * Is this user assigned to the given event as a sub — via an accepted
     * event_subs invitation or an event_members row filling a sub slot?
     * Mirrors the entitlement join in UserEventsService/assignedChartIdsForBand.
     */
    public function isEntitledToEvent(int $eventId): bool
    {
        return \DB::table('event_subs')
                ->where('user_id', $this->id)
                ->where('pending', false)
                ->where('event_id', $eventId)
                ->exists()
            || \DB::table('event_members')
                ->where('user_id', $this->id)
                ->whereNull('roster_member_id')
                ->whereNull('deleted_at')
                ->where('event_id', $eventId)
                ->exists();
    }

    /**
     * May this user delete OTHER people's messages in band/topic threads?
     * Owners always; members via the team-scoped `moderate:chat` permission.
     */
    public function canModerateChat($bandId): bool
    {
        if ($this->ownsBand($bandId)) {
            return true;
        }

        setPermissionsTeamId($bandId);
        $result = $this->hasPermissionTo('moderate:chat');
        setPermissionsTeamId(0);

        return $result;
    }
```

- [ ] **Step 4: Write the policy**

`app/Policies/ConversationPolicy.php`:

```php
<?php

namespace App\Policies;

use App\Models\Bookings;
use App\Models\Conversation;
use App\Models\Events;
use App\Models\Rehearsal;
use App\Models\User;

class ConversationPolicy
{
    public function view(User $user, Conversation $conversation): bool
    {
        return match ($conversation->type) {
            Conversation::TYPE_DM => $conversation->participants()
                ->where('user_id', $user->id)->exists(),

            // Owners + members only. Deliberately NOT canRead('events'):
            // that returns true for subs, who are excluded from the channel.
            Conversation::TYPE_BAND => $user->ownsBand($conversation->band_id)
                || $user->isPartOfBand($conversation->band_id),

            Conversation::TYPE_TOPIC => $this->viewTopic($user, $conversation),

            default => false,
        };
    }

    /** Everyone who can see a thread can post in it. */
    public function post(User $user, Conversation $conversation): bool
    {
        return $this->view($user, $conversation);
    }

    /** Delete others' messages: band/topic only, owner or moderate:chat. */
    public function moderate(User $user, Conversation $conversation): bool
    {
        if ($conversation->type === Conversation::TYPE_DM) {
            return false;
        }

        return $user->canModerateChat($conversation->band_id);
    }

    private function viewTopic(User $user, Conversation $conversation): bool
    {
        $bandId = (int) $conversation->band_id;
        $target = $conversation->conversable;

        if (!$target) {
            return false;
        }

        $isOwnerOrMember = $user->ownsBand($bandId) || $user->isPartOfBand($bandId);

        if ($target instanceof Bookings) {
            // canRead('bookings') has no sub shortcut, so subs are excluded here.
            return $isOwnerOrMember && $user->canRead('bookings', $bandId);
        }

        if ($target instanceof Rehearsal) {
            if ($isOwnerOrMember) {
                return $user->canRead('rehearsals', $bandId);
            }

            // Sub path: entitled to ANY Events row wrapping this rehearsal.
            return $target->events()->pluck('id')
                ->contains(fn ($eventId) => $user->isEntitledToEvent((int) $eventId));
        }

        if ($target instanceof Events) {
            if ($isOwnerOrMember) {
                return $user->canRead('events', $bandId);
            }

            return $user->isEntitledToEvent($target->id);
        }

        return false;
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ConversationPolicyTest.php
```

Expected: PASS (6 tests). If `can()` still returns false everywhere, policy auto-discovery failed — register `Conversation::class => ConversationPolicy::class` in `app/Providers/AuthServiceProvider.php` `$policies` array and re-run.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Policies/ConversationPolicy.php app/Models/User.php tests/Feature/Api/Mobile/Chat/ConversationPolicyTest.php
git commit -m "feat(chat): ConversationPolicy — derived access for dm/band/topic incl. sub entitlement

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Conversations list, DM creation, contacts

**Files:**
- Create: `app/Http/Controllers/Api/Mobile/ConversationsController.php`
- Create: `app/Services/Chat/MessageFormatter.php`
- Modify: `routes/api.php` (inside the `auth:sanctum` mobile group, after the Devices routes ~line 118)
- Test: `tests/Feature/Api/Mobile/Chat/ConversationsIndexTest.php`

**Interfaces:**
- Consumes: `ConversationService`, `ConversationPolicy` (Tasks 2–3).
- Produces (wire contract, canonical — matches the Flutter plan):
  - **Conversation JSON** (list rows, dm create, thread pages): `{id, type, band_id, title, last_message_preview, last_message_at, unread_count, can_moderate}`.
  - **Message JSON** (`MessageFormatter::format`), FLAT: `{id, conversation_id, user_id, user_name, user_avatar_url, body, attachments: [{id, width, height}], edited_at, is_deleted, created_at}`. Attachment binaries are fetched via the client-constructed URL `GET /api/mobile/messages/{message_id}/attachments/{id}` (route lands in Task 6).
  - `GET /api/mobile/conversations` → `{conversations: [Conversation...]}`; `POST /api/mobile/conversations/dm {user_id}` → `{conversation: Conversation}`; `GET /api/mobile/chat/contacts` → `{contacts: [{id, name, avatar_url, context, is_sub}]}` — `context` is a short human string: the shared band name(s), prefixed `"Sub — "` when the contact is only a sub.

- [ ] **Step 1: Write the failing test**

`tests/Feature/Api/Mobile/Chat/ConversationsIndexTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Models\User;
use App\Services\Chat\ConversationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ConversationsIndexTest extends TestCase
{
    use RefreshDatabase, ChatTestHelpers;

    public function test_index_lists_band_channels_and_dms_with_unread_counts(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member  = $this->makeMember($band);
        $service = app(ConversationService::class);

        $dm = $service->dmBetween($owner, $member);
        $dm->messages()->create(['user_id' => $member->id, 'body' => 'hey there']);

        $response = $this->actingAs($owner)->getJson('/api/mobile/conversations')->assertOk();

        $conversations = collect($response->json('conversations'));
        $this->assertCount(2, $conversations); // band channel (lazily created) + dm

        $bandRow = $conversations->firstWhere('type', 'band');
        $this->assertSame($band->name, $bandRow['title']);

        $dmRow = $conversations->firstWhere('type', 'dm');
        $this->assertSame($member->name, $dmRow['title']);
        $this->assertSame('hey there', $dmRow['last_message_preview']);
        $this->assertNotNull($dmRow['last_message_at']);
        $this->assertSame(1, $dmRow['unread_count']);
        $this->assertTrue($bandRow['can_moderate'], 'owner moderates the band channel');
        $this->assertFalse($dmRow['can_moderate'], 'DMs are never moderatable');
    }

    public function test_own_messages_do_not_count_as_unread(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $dm->messages()->create(['user_id' => $owner->id, 'body' => 'my own']);

        $response = $this->actingAs($owner)->getJson('/api/mobile/conversations')->assertOk();

        $dmRow = collect($response->json('conversations'))->firstWhere('type', 'dm');
        $this->assertSame(0, $dmRow['unread_count']);
    }

    public function test_sub_only_user_sees_no_band_channel(): void
    {
        [, $band] = $this->makeOwnerWithBand();
        $event = $this->makeBookingEvent($band);
        $sub   = $this->makeSubAssignedTo($band, $event);

        $response = $this->actingAs($sub)->getJson('/api/mobile/conversations')->assertOk();

        $this->assertSame([], $response->json('conversations'));
    }

    public function test_store_dm_creates_thread_with_a_bandmate(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);

        $response = $this->actingAs($owner)
            ->postJson('/api/mobile/conversations/dm', ['user_id' => $member->id])
            ->assertOk();

        $this->assertSame('dm', $response->json('conversation.type'));
        $this->assertSame($member->name, $response->json('conversation.title'));

        // Idempotent: same pair → same conversation id.
        $again = $this->actingAs($member)
            ->postJson('/api/mobile/conversations/dm', ['user_id' => $owner->id])
            ->assertOk();
        $this->assertSame($response->json('conversation.id'), $again->json('conversation.id'));
    }

    public function test_store_dm_rejects_users_with_no_shared_band(): void
    {
        [$owner] = $this->makeOwnerWithBand();
        $stranger = User::factory()->create();

        $this->actingAs($owner)
            ->postJson('/api/mobile/conversations/dm', ['user_id' => $stranger->id])
            ->assertStatus(403);
    }

    public function test_contacts_lists_bandmates_and_subs_with_context_but_not_strangers(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $event  = $this->makeBookingEvent($band);
        $sub    = $this->makeSubAssignedTo($band, $event);
        User::factory()->create(); // stranger

        $response = $this->actingAs($owner)->getJson('/api/mobile/chat/contacts')->assertOk();

        $contacts = collect($response->json('contacts'))->keyBy('id');
        $this->assertEqualsCanonicalizing([$member->id, $sub->id], $contacts->keys()->all());

        $this->assertSame($band->name, $contacts[$member->id]['context']);
        $this->assertFalse($contacts[$member->id]['is_sub']);
        $this->assertNull($contacts[$member->id]['avatar_url']);

        $this->assertSame('Sub — ' . $band->name, $contacts[$sub->id]['context']);
        $this->assertTrue($contacts[$sub->id]['is_sub']);
    }

    public function test_contacts_for_a_sub_lists_the_bands_owner_and_members(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $event  = $this->makeBookingEvent($band);
        $sub    = $this->makeSubAssignedTo($band, $event);

        $response = $this->actingAs($sub)->getJson('/api/mobile/chat/contacts')->assertOk();

        $contacts = collect($response->json('contacts'))->keyBy('id');
        $this->assertEqualsCanonicalizing([$owner->id, $member->id], $contacts->keys()->all());
        $this->assertSame($band->name, $contacts[$owner->id]['context']);
        $this->assertFalse($contacts[$owner->id]['is_sub']);
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ConversationsIndexTest.php
```

Expected: FAIL — 404s (routes not defined).

- [ ] **Step 3: Write the formatter, controller, and routes**

`app/Services/Chat/MessageFormatter.php`:

```php
<?php

namespace App\Services\Chat;

use App\Models\Message;

class MessageFormatter
{
    /**
     * Single FLAT wire shape for a message everywhere (thread page, stream).
     * Attachment binaries are fetched by the client-constructed URL
     * GET /api/mobile/messages/{message_id}/attachments/{id} — the payload
     * deliberately carries only what layout needs (id + dimensions).
     */
    public function format(Message $message): array
    {
        $deleted = $message->trashed();

        return [
            'id'              => $message->id,
            'conversation_id' => $message->conversation_id,
            'user_id'         => $message->user_id,
            'user_name'       => $message->user->name,
            'user_avatar_url' => null,
            'body'            => $deleted ? null : $message->body,
            'attachments'     => $deleted ? [] : $message->attachments->map(fn ($a) => [
                'id'     => $a->id,
                'width'  => $a->width,
                'height' => $a->height,
            ])->values()->all(),
            'edited_at'  => $message->edited_at?->toIso8601String(),
            'is_deleted' => $deleted,
            'created_at' => $message->created_at->toIso8601String(),
        ];
    }
}
```

`app/Http/Controllers/Api/Mobile/ConversationsController.php` (this task adds `index`, `storeDm`, `contacts`; later tasks extend it):

```php
<?php

namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Models\Conversation;
use App\Models\ConversationParticipant;
use App\Models\Message;
use App\Models\User;
use App\Services\Chat\ConversationService;
use App\Services\Chat\MessageFormatter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ConversationsController extends Controller
{
    public function __construct(
        private readonly ConversationService $conversations,
        private readonly MessageFormatter $formatter,
    ) {}

    /**
     * GET /api/mobile/conversations — the Messages screen: the user's DMs
     * plus a band channel per owned/member band (lazily created so it is
     * always present). Topic threads are NOT listed; they surface on their
     * event/rehearsal/booking screens.
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $channels = $user->bands()->unique('id')->values()
            ->map(fn ($band) => $this->conversations->bandChannelFor($band));

        $dms = Conversation::where('type', Conversation::TYPE_DM)
            ->whereHas('participants', fn ($q) => $q->where('user_id', $user->id))
            ->get();

        $all = $channels->concat($dms);

        $lastReads = ConversationParticipant::where('user_id', $user->id)
            ->whereIn('conversation_id', $all->pluck('id'))
            ->pluck('last_read_at', 'conversation_id');

        $rows = $all->map(fn (Conversation $c) => $this->summarize($c, $user, $lastReads->get($c->id)))
            ->sortByDesc(fn ($row) => $row['last_message_at'] ?? '')
            ->values();

        return response()->json(['conversations' => $rows]);
    }

    /** POST /api/mobile/conversations/dm {user_id} — find-or-create the global pair thread. */
    public function storeDm(Request $request): JsonResponse
    {
        $validated = $request->validate(['user_id' => 'required|integer|exists:users,id']);

        $me    = $request->user();
        $other = User::findOrFail($validated['user_id']);

        abort_unless($this->conversations->canDm($me, $other), 403, 'You do not share a band with this user.');

        $conversation = $this->conversations->dmBetween($me, $other);

        return response()->json(['conversation' => $this->summarize($conversation, $me, null)]);
    }

    /** GET /api/mobile/chat/contacts — who the current user may start a DM with. */
    public function contacts(Request $request): JsonResponse
    {
        $user = $request->user();

        /** @var array<int, array{bands: list<string>, is_sub: bool}> $entries */
        $entries = [];

        $add = function ($userId, string $bandName, bool $isSub) use (&$entries, $user) {
            $userId = (int) $userId;
            if ($userId === $user->id) {
                return;
            }
            $entries[$userId] ??= ['bands' => [], 'is_sub' => $isSub];
            if (!in_array($bandName, $entries[$userId]['bands'], true)) {
                $entries[$userId]['bands'][] = $bandName;
            }
            // Any non-sub relationship wins over sub.
            $entries[$userId]['is_sub'] = $entries[$userId]['is_sub'] && $isSub;
        };

        // Bands I own or play in: owners + members, plus that band's subs.
        foreach ($user->bands()->unique('id') as $band) {
            foreach ($band->owners()->pluck('user_id')->merge($band->members()->pluck('user_id')) as $id) {
                $add($id, $band->name, false);
            }
            foreach (DB::table('band_subs')->where('band_id', $band->id)->pluck('user_id') as $id) {
                $add($id, $band->name, true);
            }
        }

        // Bands I sub for: their owners and members (not fellow subs).
        foreach ($user->bandSub as $band) {
            foreach ($band->owners()->pluck('user_id')->merge($band->members()->pluck('user_id')) as $id) {
                $add($id, $band->name, false);
            }
        }

        $names = User::whereIn('id', array_keys($entries))->pluck('name', 'id');

        $contacts = collect($entries)
            ->map(function ($entry, $userId) use ($names) {
                $bandList = implode(', ', $entry['bands']);

                return [
                    'id'         => (int) $userId,
                    'name'       => (string) ($names[$userId] ?? ''),
                    'avatar_url' => null,
                    'context'    => $entry['is_sub'] ? 'Sub — ' . $bandList : $bandList,
                    'is_sub'     => $entry['is_sub'],
                ];
            })
            ->sortBy('name')->values();

        return response()->json(['contacts' => $contacts]);
    }

    /** Conversation JSON — the one wire shape for a conversation everywhere. */
    private function summarize(Conversation $conversation, User $user, $lastReadAt): array
    {
        $last = $conversation->messages()->withTrashed()->latest('id')->with('attachments')->first();

        $preview = null;
        $lastAt  = null;
        if ($last) {
            $lastAt  = $last->created_at->toIso8601String();
            $preview = $last->trashed()
                ? null
                : (($last->body !== null && $last->body !== '') ? $last->body : '📷 Photo');
        }

        $unread = Message::where('conversation_id', $conversation->id)
            ->where('user_id', '!=', $user->id)
            ->when($lastReadAt, fn ($q) => $q->where('created_at', '>', $lastReadAt))
            ->count();

        $title = match ($conversation->type) {
            Conversation::TYPE_BAND => $conversation->band?->name ?? 'Band',
            Conversation::TYPE_DM   => $conversation->participants()
                ->where('user_id', '!=', $user->id)->with('user')->first()?->user?->name ?? 'Direct message',
            default => 'Conversation',
        };

        return [
            'id'                   => $conversation->id,
            'type'                 => $conversation->type,
            'band_id'              => $conversation->band_id ? (int) $conversation->band_id : null,
            'title'                => $title,
            'last_message_preview' => $preview,
            'last_message_at'      => $lastAt,
            'unread_count'         => $unread,
            'can_moderate'         => $user->can('moderate', $conversation),
        ];
    }
}
```

In `routes/api.php`, after the Devices routes (`Route::delete('/devices', ...)` ~line 117), add:

```php
        // ── Chat / comments (band-agnostic; ConversationPolicy is the gate) ──
        Route::get('/conversations', [App\Http\Controllers\Api\Mobile\ConversationsController::class, 'index'])->name('mobile.conversations.index');
        Route::post('/conversations/dm', [App\Http\Controllers\Api\Mobile\ConversationsController::class, 'storeDm'])->name('mobile.conversations.dm');
        Route::get('/chat/contacts', [App\Http\Controllers\Api\Mobile\ConversationsController::class, 'contacts'])->name('mobile.chat.contacts');
```

Note: the formatter carries no attachment URLs — clients construct `GET /api/mobile/messages/{message_id}/attachments/{id}` themselves (the serving route lands in Task 6).

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ConversationsIndexTest.php
```

Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Http/Controllers/Api/Mobile/ConversationsController.php app/Services/Chat/MessageFormatter.php routes/api.php tests/Feature/Api/Mobile/Chat/ConversationsIndexTest.php
git commit -m "feat(chat): conversations list, DM find-or-create, contacts endpoints

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Topic resolve endpoints (event / rehearsal / booking)

**Files:**
- Modify: `app/Http/Controllers/Api/Mobile/ConversationsController.php` (add `forEvent`, `forRehearsal`, `forBooking`)
- Modify: `routes/api.php`
- Test: `tests/Feature/Api/Mobile/Chat/TopicConversationTest.php`

**Interfaces:**
- Consumes: `ConversationService::topicFor`, `ConversationPolicy::view` (Tasks 2–3), `summarize()` (Task 4).
- Produces: `GET /api/mobile/events/{event}/conversation`, `GET /api/mobile/rehearsals/{rehearsal}/conversation`, `GET /api/mobile/bands/{band}/bookings/{booking}/conversation` — each returns the shared **ThreadPage** shape (also returned by the messages index in Task 6): `{conversation: Conversation, messages: [Message...] (oldest→newest, newest 50), participants: [{user_id, name, avatar_url, last_read_at}], channel: "private-conversation.{id}", has_more: bool}`. `can_moderate` lives inside the Conversation JSON.

- [ ] **Step 1: Write the failing test**

`tests/Feature/Api/Mobile/Chat/TopicConversationTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Services\Chat\ConversationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TopicConversationTest extends TestCase
{
    use RefreshDatabase, ChatTestHelpers;

    public function test_event_conversation_resolves_and_returns_messages(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $event = $this->makeBookingEvent($band);

        $response = $this->actingAs($owner)
            ->getJson("/api/mobile/events/{$event->id}/conversation")
            ->assertOk();

        $this->assertSame('topic', $response->json('conversation.type'));
        $this->assertSame([], $response->json('messages'));
        $this->assertFalse($response->json('has_more'));
        $this->assertTrue($response->json('conversation.can_moderate'));
        $this->assertSame(
            'private-conversation.' . $response->json('conversation.id'),
            $response->json('channel'),
        );
        // Opening the thread registered the viewer as a participant.
        $this->assertContains($owner->id, collect($response->json('participants'))->pluck('user_id')->all());

        // Same event → same conversation.
        $again = $this->actingAs($owner)->getJson("/api/mobile/events/{$event->id}/conversation");
        $this->assertSame($response->json('conversation.id'), $again->json('conversation.id'));
    }

    public function test_event_and_rehearsal_endpoints_reach_the_same_canonical_thread(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        [$rehearsal, $event] = $this->makeRehearsalEvent($band);

        $viaEvent = $this->actingAs($owner)
            ->getJson("/api/mobile/events/{$event->id}/conversation")->assertOk();
        $viaRehearsal = $this->actingAs($owner)
            ->getJson("/api/mobile/rehearsals/{$rehearsal->id}/conversation")->assertOk();

        $this->assertSame(
            $viaEvent->json('conversation.id'),
            $viaRehearsal->json('conversation.id'),
        );
    }

    public function test_booking_conversation_is_reachable_and_distinct_from_event_thread(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $event   = $this->makeBookingEvent($band);
        $booking = $event->eventable;

        $bookingThread = $this->actingAs($owner)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}/conversation")
            ->assertOk();
        $eventThread = $this->actingAs($owner)
            ->getJson("/api/mobile/events/{$event->id}/conversation")->assertOk();

        $this->assertNotSame(
            $bookingThread->json('conversation.id'),
            $eventThread->json('conversation.id'),
        );
    }

    public function test_entitled_sub_reaches_event_thread_but_unentitled_sub_is_403(): void
    {
        [, $band] = $this->makeOwnerWithBand();
        $event      = $this->makeBookingEvent($band);
        $otherEvent = $this->makeBookingEvent($band);
        $entitled   = $this->makeSubAssignedTo($band, $event);
        $unentitled = $this->makeSubAssignedTo($band, $otherEvent);

        $this->actingAs($entitled)
            ->getJson("/api/mobile/events/{$event->id}/conversation")->assertOk();
        $this->actingAs($unentitled)
            ->getJson("/api/mobile/events/{$event->id}/conversation")->assertStatus(403);
    }

    public function test_sub_cannot_reach_a_booking_thread(): void
    {
        [, $band] = $this->makeOwnerWithBand();
        $event = $this->makeBookingEvent($band);
        $sub   = $this->makeSubAssignedTo($band, $event);

        $this->actingAs($sub)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/bookings/{$event->eventable->id}/conversation")
            ->assertStatus(403);
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/TopicConversationTest.php
```

Expected: FAIL — 404s (routes not defined).

- [ ] **Step 3: Add controller methods and routes**

Append to `ConversationsController` (and add `use App\Models\Bands; use App\Models\Bookings; use App\Models\Events; use App\Models\Rehearsal;` to the imports):

```php
    /** GET /api/mobile/events/{event}/conversation */
    public function forEvent(Request $request, Events $event): JsonResponse
    {
        return $this->topicResponse($request, $this->conversations->topicFor($event));
    }

    /** GET /api/mobile/rehearsals/{rehearsal}/conversation */
    public function forRehearsal(Request $request, Rehearsal $rehearsal): JsonResponse
    {
        return $this->topicResponse($request, $this->conversations->topicFor($rehearsal));
    }

    /** GET /api/mobile/bands/{band}/bookings/{booking}/conversation */
    public function forBooking(Request $request, Bands $band, Bookings $booking): JsonResponse
    {
        return $this->topicResponse($request, $this->conversations->topicFor($booking));
    }

    private function topicResponse(Request $request, Conversation $conversation): JsonResponse
    {
        $this->authorize('view', $conversation);

        // Opening a thread registers the viewer and marks it read.
        $this->conversations->touchParticipant($conversation, $request->user());

        return $this->threadPage($request, $conversation);
    }

    /**
     * The shared ThreadPage shape: also returned by the messages index
     * (Task 6). Messages come back oldest→newest; `channel` is what the
     * client subscribes to for live updates.
     */
    private function threadPage(Request $request, Conversation $conversation, ?int $before = null): JsonResponse
    {
        $user  = $request->user();
        $limit = 50;

        $page = $conversation->messages()->withTrashed()
            ->with(['user', 'attachments'])
            ->when($before, fn ($q) => $q->where('id', '<', $before))
            ->latest('id')->limit($limit + 1)->get();

        $hasMore  = $page->count() > $limit;
        $messages = $page->take($limit)->reverse()->values()
            ->map(fn ($m) => $this->formatter->format($m));

        $participants = $conversation->participants()->with('user')->get()
            ->map(fn ($p) => [
                'user_id'      => (int) $p->user_id,
                'name'         => $p->user?->name,
                'avatar_url'   => null,
                'last_read_at' => $p->last_read_at?->toIso8601String(),
            ])->values();

        $lastReadAt = ConversationParticipant::where('conversation_id', $conversation->id)
            ->where('user_id', $user->id)->value('last_read_at');

        return response()->json([
            'conversation' => $this->summarize($conversation, $user, $lastReadAt),
            'messages'     => $messages,
            'participants' => $participants,
            'channel'      => 'private-conversation.' . $conversation->id,
            'has_more'     => $hasMore,
        ]);
    }
```

Routes — add after the chat routes from Task 4:

```php
        Route::get('/events/{event}/conversation', [App\Http\Controllers\Api\Mobile\ConversationsController::class, 'forEvent'])->name('mobile.events.conversation');
        Route::get('/rehearsals/{rehearsal}/conversation', [App\Http\Controllers\Api\Mobile\ConversationsController::class, 'forRehearsal'])->name('mobile.rehearsals.conversation');
```

And inside the existing `Route::middleware('mobile.band:read:bookings')->scopeBindings()->group(...)` bookings-read block:

```php
            Route::get('/bands/{band}/bookings/{booking}/conversation', [App\Http\Controllers\Api\Mobile\ConversationsController::class, 'forBooking'])->name('mobile.bookings.conversation');
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/TopicConversationTest.php
```

Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Http/Controllers/Api/Mobile/ConversationsController.php routes/api.php tests/Feature/Api/Mobile/Chat/TopicConversationTest.php
git commit -m "feat(chat): topic conversation resolve endpoints for events, rehearsals, bookings

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Messages — send, paginate, edit, delete, read; attachments upload + serving

**Files:**
- Create: `app/Http/Controllers/Api/Mobile/MessagesController.php`
- Modify: `app/Http/Controllers/Api/Mobile/ConversationsController.php` (add `messages`, `storeMessage`, `read`)
- Modify: `routes/api.php`
- Test: `tests/Feature/Api/Mobile/Chat/MessagesTest.php`, `tests/Feature/Api/Mobile/Chat/MessageAttachmentsTest.php`

**Interfaces:**
- Consumes: `MessageFormatter`, `ConversationService`, `threadPage()` (Tasks 2–5).
- Produces: `GET /conversations/{conversation}/messages?before={messageId}` → the shared **ThreadPage** shape (same as topic resolves, Task 5); `POST /conversations/{conversation}/messages` (multipart `body`, `images[]`) → `{message: Message}` 201; `PATCH /messages/{message} {body}` → `{message: Message}`; `DELETE /messages/{message}` → 204; `POST /conversations/{conversation}/read {last_read_message_id}` → 204; `GET /messages/{message}/attachments/{attachment}` → binary stream (URL constructed client-side). Task 7 wires broadcasts into these same controller methods.

- [ ] **Step 1: Write the failing tests**

`tests/Feature/Api/Mobile/Chat/MessagesTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Services\Chat\ConversationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class MessagesTest extends TestCase
{
    use RefreshDatabase, ChatTestHelpers;

    public function test_participant_can_send_and_list_messages(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);

        $this->actingAs($owner)
            ->postJson("/api/mobile/conversations/{$dm->id}/messages", ['body' => 'first!'])
            ->assertStatus(201)
            ->assertJsonPath('message.body', 'first!')
            ->assertJsonPath('message.user.id', $owner->id);

        $list = $this->actingAs($member)
            ->getJson("/api/mobile/conversations/{$dm->id}/messages")->assertOk();
        $this->assertCount(1, $list->json('messages'));
        $this->assertFalse($list->json('has_more'));
        $this->assertSame('first!', $list->json('messages.0.body'));
        $this->assertSame($owner->name, $list->json('messages.0.user_name'));
        $this->assertSame('dm', $list->json('conversation.type'));
        $this->assertSame('private-conversation.' . $dm->id, $list->json('channel'));
    }

    public function test_non_participant_cannot_send_or_read(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member   = $this->makeMember($band);
        $outsider = \App\Models\User::factory()->create();
        $dm = app(ConversationService::class)->dmBetween($owner, $member);

        $this->actingAs($outsider)
            ->postJson("/api/mobile/conversations/{$dm->id}/messages", ['body' => 'nope'])
            ->assertStatus(403);
        $this->actingAs($outsider)
            ->getJson("/api/mobile/conversations/{$dm->id}/messages")->assertStatus(403);
    }

    public function test_cursor_pagination_walks_backwards(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);
        for ($i = 1; $i <= 60; $i++) {
            $channel->messages()->create(['user_id' => $owner->id, 'body' => "m{$i}"]);
        }

        $page1 = $this->actingAs($owner)
            ->getJson("/api/mobile/conversations/{$channel->id}/messages")->assertOk();
        $this->assertCount(50, $page1->json('messages'));
        $this->assertTrue($page1->json('has_more'));
        $this->assertSame('m60', collect($page1->json('messages'))->last()['body']);

        $oldestId = $page1->json('messages')[0]['id'];
        $page2 = $this->actingAs($owner)
            ->getJson("/api/mobile/conversations/{$channel->id}/messages?before={$oldestId}")->assertOk();
        $this->assertCount(10, $page2->json('messages'));
        $this->assertFalse($page2->json('has_more'));
    }

    public function test_author_can_edit_own_message_and_gets_edited_marker(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);
        $message = $channel->messages()->create(['user_id' => $owner->id, 'body' => 'typo']);

        $response = $this->actingAs($owner)
            ->patchJson("/api/mobile/messages/{$message->id}", ['body' => 'fixed'])
            ->assertOk();

        $this->assertSame('fixed', $response->json('message.body'));
        $this->assertNotNull($response->json('message.edited_at'));
    }

    public function test_only_the_author_can_edit(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member  = $this->makeMember($band);
        $channel = app(ConversationService::class)->bandChannelFor($band);
        $message = $channel->messages()->create(['user_id' => $member->id, 'body' => 'mine']);

        // Even the owner (a moderator) cannot EDIT someone else's message.
        $this->actingAs($owner)
            ->patchJson("/api/mobile/messages/{$message->id}", ['body' => 'hijack'])
            ->assertStatus(403);
    }

    public function test_author_deletes_own_message_leaving_a_tombstone(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);
        $message = $channel->messages()->create(['user_id' => $owner->id, 'body' => 'oops']);

        $this->actingAs($owner)->deleteJson("/api/mobile/messages/{$message->id}")->assertStatus(204);

        $list = $this->actingAs($owner)
            ->getJson("/api/mobile/conversations/{$channel->id}/messages")->assertOk();
        $row = collect($list->json('messages'))->firstWhere('id', $message->id);
        $this->assertTrue($row['is_deleted']);
        $this->assertNull($row['body']);
    }

    public function test_moderator_can_delete_others_messages_in_band_thread_but_plain_member_cannot(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $author  = $this->makeMember($band);
        $plain   = $this->makeMember($band);
        $channel = app(ConversationService::class)->bandChannelFor($band);
        $m1 = $channel->messages()->create(['user_id' => $author->id, 'body' => 'a']);
        $m2 = $channel->messages()->create(['user_id' => $author->id, 'body' => 'b']);

        $this->actingAs($plain)->deleteJson("/api/mobile/messages/{$m1->id}")->assertStatus(403);
        $this->actingAs($owner)->deleteJson("/api/mobile/messages/{$m1->id}")->assertStatus(204);

        setPermissionsTeamId($band->id);
        $plain->givePermissionTo('moderate:chat');
        setPermissionsTeamId(0);
        $this->actingAs($plain)->deleteJson("/api/mobile/messages/{$m2->id}")->assertStatus(204);
    }

    public function test_dm_messages_cannot_be_deleted_by_the_other_participant(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member  = $this->makeMember($band);
        $dm      = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $member->id, 'body' => 'private']);

        $this->actingAs($owner)->deleteJson("/api/mobile/messages/{$message->id}")->assertStatus(403);
    }

    public function test_read_endpoint_zeroes_the_unread_count(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $member->id, 'body' => 'unread me']);

        $this->actingAs($owner)
            ->postJson("/api/mobile/conversations/{$dm->id}/read", ['last_read_message_id' => $message->id])
            ->assertStatus(204);

        $list = $this->actingAs($owner)->getJson('/api/mobile/conversations')->assertOk();
        $dmRow = collect($list->json('conversations'))->firstWhere('type', 'dm');
        $this->assertSame(0, $dmRow['unread_count']);
    }

    public function test_read_marker_never_moves_backwards(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $older = $dm->messages()->create(['user_id' => $member->id, 'body' => 'older']);
        $newer = $dm->messages()->create(['user_id' => $member->id, 'body' => 'newer']);
        $newer->forceFill(['created_at' => now()->addMinute()])->save();

        $this->actingAs($owner)
            ->postJson("/api/mobile/conversations/{$dm->id}/read", ['last_read_message_id' => $newer->id])
            ->assertStatus(204);
        $this->actingAs($owner)
            ->postJson("/api/mobile/conversations/{$dm->id}/read", ['last_read_message_id' => $older->id])
            ->assertStatus(204);

        $list = $this->actingAs($owner)->getJson('/api/mobile/conversations')->assertOk();
        $dmRow = collect($list->json('conversations'))->firstWhere('type', 'dm');
        $this->assertSame(0, $dmRow['unread_count'], 'an out-of-order read call must not resurrect unreads');
    }

    public function test_body_is_required_without_images_and_capped(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);

        $this->actingAs($owner)
            ->postJson("/api/mobile/conversations/{$channel->id}/messages", [])
            ->assertStatus(422);
        $this->actingAs($owner)
            ->postJson("/api/mobile/conversations/{$channel->id}/messages", ['body' => str_repeat('x', 4001)])
            ->assertStatus(422);
    }
}
```

`tests/Feature/Api/Mobile/Chat/MessageAttachmentsTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Services\Chat\ConversationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class MessageAttachmentsTest extends TestCase
{
    use RefreshDatabase, ChatTestHelpers;

    public function test_message_with_images_stores_attachments_and_serves_them(): void
    {
        Storage::fake(config('filesystems.default'));
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);

        $response = $this->actingAs($owner)->post(
            "/api/mobile/conversations/{$dm->id}/messages",
            ['body' => 'look', 'images' => [UploadedFile::fake()->image('pic.jpg', 640, 480)]],
            ['Accept' => 'application/json'],
        )->assertStatus(201);

        $attachment = $response->json('message.attachments.0');
        $this->assertSame(640, $attachment['width']);
        $this->assertSame(480, $attachment['height']);
        $this->assertDatabaseHas('message_attachments', ['id' => $attachment['id']]);

        // Clients construct the binary URL from message id + attachment id.
        $url = "/api/mobile/messages/{$response->json('message.id')}/attachments/{$attachment['id']}";

        // Participant can fetch the binary.
        $this->actingAs($member)->get($url)->assertOk();

        // Non-participant cannot.
        $outsider = \App\Models\User::factory()->create();
        $this->actingAs($outsider)->get($url)->assertStatus(403);
    }

    public function test_image_only_message_needs_no_body(): void
    {
        Storage::fake(config('filesystems.default'));
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);

        $this->actingAs($owner)->post(
            "/api/mobile/conversations/{$channel->id}/messages",
            ['images' => [UploadedFile::fake()->image('solo.png')]],
            ['Accept' => 'application/json'],
        )->assertStatus(201)->assertJsonPath('message.body', null);
    }

    public function test_more_than_four_images_is_rejected(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);

        $images = array_map(fn ($i) => UploadedFile::fake()->image("p{$i}.jpg"), range(1, 5));

        $this->actingAs($owner)->post(
            "/api/mobile/conversations/{$channel->id}/messages",
            ['images' => $images],
            ['Accept' => 'application/json'],
        )->assertStatus(422);
    }

    public function test_non_image_files_are_rejected(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);

        $this->actingAs($owner)->post(
            "/api/mobile/conversations/{$channel->id}/messages",
            ['images' => [UploadedFile::fake()->create('evil.pdf', 100, 'application/pdf')]],
            ['Accept' => 'application/json'],
        )->assertStatus(422);
    }

    public function test_deleted_messages_attachments_are_not_served(): void
    {
        Storage::fake(config('filesystems.default'));
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);

        $response = $this->actingAs($owner)->post(
            "/api/mobile/conversations/{$channel->id}/messages",
            ['images' => [UploadedFile::fake()->image('gone.jpg')]],
            ['Accept' => 'application/json'],
        )->assertStatus(201);
        $messageId = $response->json('message.id');
        $url = "/api/mobile/messages/{$messageId}/attachments/" . $response->json('message.attachments.0.id');

        $this->actingAs($owner)->deleteJson("/api/mobile/messages/{$messageId}")->assertStatus(204);

        $this->actingAs($owner)->get($url)->assertStatus(404);
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/MessagesTest.php tests/Feature/Api/Mobile/Chat/MessageAttachmentsTest.php
```

Expected: FAIL — 404s (routes not defined).

- [ ] **Step 3: Add ConversationsController methods**

Append to `ConversationsController` (add `use Illuminate\Support\Str;` import):

```php
    /** GET /api/mobile/conversations/{conversation}/messages?before={messageId} — ThreadPage. */
    public function messages(Request $request, Conversation $conversation): JsonResponse
    {
        $this->authorize('view', $conversation);

        return $this->threadPage(
            $request,
            $conversation,
            $request->filled('before') ? (int) $request->input('before') : null,
        );
    }

    /** POST /api/mobile/conversations/{conversation}/messages — multipart body and/or images[]. */
    public function storeMessage(Request $request, Conversation $conversation): JsonResponse
    {
        $this->authorize('post', $conversation);

        $validated = $request->validate([
            'body'     => ['nullable', 'string', 'max:4000', 'required_without:images'],
            'images'   => ['nullable', 'array', 'max:4'],
            'images.*' => ['image', 'mimes:jpeg,jpg,png,webp,heic', 'max:10240'],
        ]);

        $user    = $request->user();
        $message = $conversation->messages()->create([
            'user_id' => $user->id,
            'body'    => $validated['body'] ?? null,
        ]);

        $disk = config('filesystems.default');
        foreach ($request->file('images', []) as $file) {
            $path = $file->storeAs(
                'chat/' . $conversation->id,
                Str::uuid() . '.' . $file->extension(),
                $disk,
            );
            $dimensions = @getimagesize($file->getRealPath()) ?: [null, null];
            $message->attachments()->create([
                'path'       => $path,
                'disk'       => $disk,
                'mime'       => $file->getMimeType(),
                'width'      => $dimensions[0],
                'height'     => $dimensions[1],
                'size_bytes' => $file->getSize(),
            ]);
        }

        // Sending implies having read everything up to your own message.
        $this->conversations->touchParticipant($conversation, $user);

        $message->load(['user', 'attachments']);

        return response()->json(['message' => $this->formatter->format($message)], 201);
    }

    /** POST /api/mobile/conversations/{conversation}/read {last_read_message_id} → 204. */
    public function read(Request $request, Conversation $conversation): JsonResponse
    {
        $this->authorize('view', $conversation);

        $validated = $request->validate(['last_read_message_id' => 'required|integer']);

        $message = $conversation->messages()->withTrashed()
            ->findOrFail($validated['last_read_message_id']);

        $participant = ConversationParticipant::firstOrCreate([
            'conversation_id' => $conversation->id,
            'user_id'         => $request->user()->id,
        ]);

        // Never move the marker backwards (out-of-order client calls).
        if (!$participant->last_read_at || $participant->last_read_at->lt($message->created_at)) {
            $participant->forceFill(['last_read_at' => $message->created_at])->save();
        }

        return response()->json(null, 204);
    }
```

- [ ] **Step 4: Write MessagesController**

`app/Http/Controllers/Api/Mobile/MessagesController.php`:

```php
<?php

namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Models\Message;
use App\Models\MessageAttachment;
use App\Services\Chat\MessageFormatter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

class MessagesController extends Controller
{
    public function __construct(private readonly MessageFormatter $formatter) {}

    /** PATCH /api/mobile/messages/{message} — author only, always. */
    public function update(Request $request, Message $message): JsonResponse
    {
        abort_unless($message->user_id === $request->user()->id, 403, 'Only the author may edit a message.');

        $validated = $request->validate(['body' => 'required|string|max:4000']);

        $message->update(['body' => $validated['body'], 'edited_at' => now()]);
        $message->load(['user', 'attachments']);

        return response()->json(['message' => $this->formatter->format($message)]);
    }

    /** DELETE /api/mobile/messages/{message} — author, or moderator on band/topic threads. */
    public function destroy(Request $request, Message $message): JsonResponse
    {
        $user = $request->user();

        if ($message->user_id !== $user->id && !$user->can('moderate', $message->conversation)) {
            abort(403);
        }

        $message->delete();

        return response()->json(null, 204);
    }

    /** GET /api/mobile/messages/{message}/attachments/{attachment} — authenticated binary. */
    public function attachment(Request $request, Message $message, MessageAttachment $attachment): StreamedResponse
    {
        // Route binding excludes soft-deleted messages, so a deleted
        // message's attachments 404 without an explicit check.
        abort_if($attachment->message_id !== $message->id, 404);
        $this->authorize('view', $message->conversation);

        return Storage::disk($attachment->disk)->response(
            $attachment->path,
            null,
            ['Content-Type' => $attachment->mime],
        );
    }
}
```

Routes — add after the topic conversation routes:

```php
        Route::get('/conversations/{conversation}/messages', [App\Http\Controllers\Api\Mobile\ConversationsController::class, 'messages'])->name('mobile.conversations.messages.index');
        Route::post('/conversations/{conversation}/messages', [App\Http\Controllers\Api\Mobile\ConversationsController::class, 'storeMessage'])->name('mobile.conversations.messages.store');
        Route::post('/conversations/{conversation}/read', [App\Http\Controllers\Api\Mobile\ConversationsController::class, 'read'])->name('mobile.conversations.read');
        Route::patch('/messages/{message}', [App\Http\Controllers\Api\Mobile\MessagesController::class, 'update'])->name('mobile.messages.update');
        Route::delete('/messages/{message}', [App\Http\Controllers\Api\Mobile\MessagesController::class, 'destroy'])->name('mobile.messages.destroy');
        Route::get('/messages/{message}/attachments/{attachment}', [App\Http\Controllers\Api\Mobile\MessagesController::class, 'attachment'])->name('mobile.messages.attachments.show');
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/MessagesTest.php tests/Feature/Api/Mobile/Chat/MessageAttachmentsTest.php
```

Expected: PASS (11 + 5 tests).

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Http/Controllers/Api/Mobile/MessagesController.php app/Http/Controllers/Api/Mobile/ConversationsController.php routes/api.php tests/Feature/Api/Mobile/Chat/MessagesTest.php tests/Feature/Api/Mobile/Chat/MessageAttachmentsTest.php
git commit -m "feat(chat): message send/paginate/edit/delete/read + image attachments

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Realtime — band signals, DM user signals, conversation stream, typing

**Files:**
- Create: `app/Events/ConversationChanged.php`, `app/Events/ConversationStreamEvent.php`
- Modify: `app/Models/Message.php` (add trait + hooks)
- Modify: `app/Http/Controllers/Api/Mobile/ConversationsController.php` (stream dispatches + `typing`), `app/Http/Controllers/Api/Mobile/MessagesController.php` (stream dispatches)
- Modify: `routes/channels.php`, `routes/api.php`
- Test: `tests/Feature/Api/Mobile/Chat/ChatBroadcastingTest.php`, `tests/Feature/Api/Mobile/Chat/ConversationChannelAuthTest.php`

**Interfaces:**
- Consumes: everything above.
- Produces (wire contract for the Flutter plan):
  - `private-band.{bandId}` — existing `band.data-changed` with `model: 'message'`, `parent: {model: 'conversation', id}` for band/topic threads.
  - `private-App.Models.User.{userId}` — new event name `user.data-changed`, payload `{model: 'message', id, action, parent: {model: 'conversation', id}}` for DM participants.
  - `private-conversation.{conversationId}` — FIVE distinct wire events (one `ConversationStreamEvent` class whose `broadcastAs()` returns the type; the payload IS the data, no envelope):
    - `message.created` `{message: Message}`
    - `message.updated` `{message: Message}`
    - `message.deleted` `{message_id: int}`
    - `conversation.read` `{user_id: int, last_read_at: iso8601}`
    - `conversation.typing` `{user_id: int, name: string}`
  - `POST /api/mobile/conversations/{conversation}/typing` → 204, nothing stored.

- [ ] **Step 1: Write the failing tests**

`tests/Feature/Api/Mobile/Chat/ChatBroadcastingTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Events\BandDataChanged;
use App\Events\ConversationChanged;
use App\Events\ConversationStreamEvent;
use App\Services\Chat\ConversationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Tests\TestCase;

class ChatBroadcastingTest extends TestCase
{
    use RefreshDatabase, ChatTestHelpers;

    public function test_band_thread_message_broadcasts_thin_band_signal_with_conversation_parent(): void
    {
        Event::fake([BandDataChanged::class]);
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);

        $message = $channel->messages()->create(['user_id' => $owner->id, 'body' => 'hi band']);

        Event::assertDispatched(
            BandDataChanged::class,
            fn (BandDataChanged $e) => $e->bandId === $band->id
                && $e->model === 'message'
                && $e->id === $message->id
                && $e->action === 'created'
                && $e->parent === ['model' => 'conversation', 'id' => $channel->id],
        );
    }

    public function test_dm_message_signals_each_participants_user_channel_not_a_band(): void
    {
        Event::fake([BandDataChanged::class, ConversationChanged::class]);
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);

        $message = $dm->messages()->create(['user_id' => $owner->id, 'body' => 'psst']);

        Event::assertNotDispatched(BandDataChanged::class);
        foreach ([$owner->id, $member->id] as $userId) {
            Event::assertDispatched(
                ConversationChanged::class,
                fn (ConversationChanged $e) => $e->userId === $userId
                    && $e->conversationId === $dm->id
                    && $e->messageId === $message->id
                    && $e->action === 'created',
            );
        }
    }

    public function test_store_message_endpoint_emits_stream_event_with_full_payload(): void
    {
        Event::fake([ConversationStreamEvent::class]);
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);

        $this->actingAs($owner)
            ->postJson("/api/mobile/conversations/{$channel->id}/messages", ['body' => 'live'])
            ->assertStatus(201);

        Event::assertDispatched(
            ConversationStreamEvent::class,
            fn (ConversationStreamEvent $e) => $e->conversationId === $channel->id
                && $e->type === 'message.created'
                && $e->data['message']['body'] === 'live',
        );
    }

    public function test_edit_and_delete_emit_stream_events(): void
    {
        Event::fake([ConversationStreamEvent::class]);
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);
        $message = $channel->messages()->create(['user_id' => $owner->id, 'body' => 'v1']);

        $this->actingAs($owner)->patchJson("/api/mobile/messages/{$message->id}", ['body' => 'v2'])->assertOk();
        Event::assertDispatched(
            ConversationStreamEvent::class,
            fn (ConversationStreamEvent $e) => $e->type === 'message.updated'
                && $e->data['message']['body'] === 'v2',
        );

        $this->actingAs($owner)->deleteJson("/api/mobile/messages/{$message->id}")->assertStatus(204);
        Event::assertDispatched(
            ConversationStreamEvent::class,
            fn (ConversationStreamEvent $e) => $e->type === 'message.deleted'
                && $e->data['message_id'] === $message->id,
        );
    }

    public function test_read_and_typing_emit_stream_events(): void
    {
        Event::fake([ConversationStreamEvent::class]);
        [$owner, $band] = $this->makeOwnerWithBand();
        $channel = app(ConversationService::class)->bandChannelFor($band);
        $message = $channel->messages()->create(['user_id' => $owner->id, 'body' => 'mark me']);

        $this->actingAs($owner)
            ->postJson("/api/mobile/conversations/{$channel->id}/read", ['last_read_message_id' => $message->id])
            ->assertStatus(204);
        Event::assertDispatched(
            ConversationStreamEvent::class,
            fn (ConversationStreamEvent $e) => $e->type === 'conversation.read'
                && $e->data['user_id'] === $owner->id
                && is_string($e->data['last_read_at']),
        );

        $this->actingAs($owner)->postJson("/api/mobile/conversations/{$channel->id}/typing")->assertStatus(204);
        Event::assertDispatched(
            ConversationStreamEvent::class,
            fn (ConversationStreamEvent $e) => $e->type === 'conversation.typing'
                && $e->data['user_id'] === $owner->id
                && $e->data['name'] === $owner->name,
        );
    }

    public function test_stream_event_broadcasts_as_its_type_with_no_envelope(): void
    {
        $event = new ConversationStreamEvent(7, 'message.deleted', ['message_id' => 42]);

        $this->assertSame('message.deleted', $event->broadcastAs());
        $this->assertSame(['message_id' => 42], $event->broadcastWith());
    }
}
```

`tests/Feature/Api/Mobile/Chat/ConversationChannelAuthTest.php` (mirrors `tests/Feature/Broadcasting/BandChannelAuthTest.php` conventions — POST `/broadcasting/auth` with `channel_name`):

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Models\User;
use App\Services\Chat\ConversationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ConversationChannelAuthTest extends TestCase
{
    use RefreshDatabase, ChatTestHelpers;

    private function authChannel(User $user, int $conversationId)
    {
        return $this->actingAs($user)->post('/broadcasting/auth', [
            'channel_name' => 'private-conversation.' . $conversationId,
            'socket_id'    => '123.456',
        ]);
    }

    public function test_participant_passes_and_outsider_fails_conversation_channel_auth(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member   = $this->makeMember($band);
        $outsider = User::factory()->create();
        $dm = app(ConversationService::class)->dmBetween($owner, $member);

        $this->authChannel($owner, $dm->id)->assertOk();
        $this->authChannel($outsider, $dm->id)->assertStatus(403);
    }

    public function test_entitled_sub_passes_topic_channel_auth(): void
    {
        [, $band] = $this->makeOwnerWithBand();
        $event      = $this->makeBookingEvent($band);
        $otherEvent = $this->makeBookingEvent($band);
        $entitled   = $this->makeSubAssignedTo($band, $event);
        $unentitled = $this->makeSubAssignedTo($band, $otherEvent);
        $topic = app(ConversationService::class)->topicFor($event);

        $this->authChannel($entitled, $topic->id)->assertOk();
        $this->authChannel($unentitled, $topic->id)->assertStatus(403);
    }

    public function test_unknown_conversation_fails_auth(): void
    {
        [$owner] = $this->makeOwnerWithBand();
        $this->authChannel($owner, 999999)->assertStatus(403);
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ChatBroadcastingTest.php tests/Feature/Api/Mobile/Chat/ConversationChannelAuthTest.php
```

Expected: FAIL — `Class "App\Events\ConversationChanged" not found`.

- [ ] **Step 3: Create the broadcast events**

`app/Events/ConversationChanged.php`:

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
 * Thin per-user change signal for DM conversations — the DM analogue of
 * BandDataChanged (DMs have no band channel to ride). One event per
 * participant, on their standard App.Models.User.{id} private channel.
 */
class ConversationChanged implements ShouldBroadcast, ShouldDispatchAfterCommit
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public int $userId,
        public int $conversationId,
        public int $messageId,
        public string $action,
    ) {}

    public function broadcastOn(): array
    {
        return [new PrivateChannel('App.Models.User.' . $this->userId)];
    }

    public function broadcastAs(): string
    {
        return 'user.data-changed';
    }

    public function broadcastWith(): array
    {
        return [
            'model'  => 'message',
            'id'     => $this->messageId,
            'action' => $this->action,
            'parent' => ['model' => 'conversation', 'id' => $this->conversationId],
        ];
    }
}
```

`app/Events/ConversationStreamEvent.php` (mirrors `RehearsalPlannerStreamEvent`):

```php
<?php

namespace App\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Full-payload live event for an OPEN conversation screen: instant message
 * append/edit/delete, read receipts, and typing — no refetch round-trip.
 * ShouldBroadcastNow: latency matters more than queue smoothing here.
 *
 * One class, FIVE wire events — broadcastAs() returns the type itself, so
 * clients bind to five distinct event names with no envelope:
 *   message.created {message} | message.updated {message}
 *   message.deleted {message_id} | conversation.read {user_id, last_read_at}
 *   conversation.typing {user_id, name}
 */
class ConversationStreamEvent implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    /** @param array<string,mixed> $data */
    public function __construct(
        public int $conversationId,
        public string $type,
        public array $data = [],
    ) {}

    public function broadcastOn(): array
    {
        return [new PrivateChannel('conversation.' . $this->conversationId)];
    }

    public function broadcastAs(): string
    {
        return $this->type;
    }

    public function broadcastWith(): array
    {
        return $this->data;
    }
}
```

- [ ] **Step 4: Wire the Message model signals**

In `app/Models/Message.php`: add imports `use App\Events\ConversationChanged; use App\Models\Traits\BroadcastsBandChanges;`, add `BroadcastsBandChanges` to the `use` line inside the class, and add:

```php
    protected static function booted(): void
    {
        // DM threads have no band — signal each participant's user channel
        // instead. Band/topic threads are covered by BroadcastsBandChanges.
        $signalDm = function (self $message, string $action) {
            $conversation = $message->conversation;
            if (!$conversation || $conversation->type !== Conversation::TYPE_DM) {
                return;
            }
            foreach ($conversation->participants()->pluck('user_id') as $userId) {
                broadcast(new ConversationChanged((int) $userId, $conversation->id, $message->id, $action))
                    ->toOthers();
            }
        };

        static::created(fn (self $m) => $signalDm($m, 'created'));
        static::updated(fn (self $m) => $signalDm($m, 'updated'));
        static::deleted(fn (self $m) => $signalDm($m, 'deleted'));
    }

    protected function broadcastBandId(): ?int
    {
        // Null for DMs → the band-channel trait skips them silently.
        return $this->conversation?->band_id ? (int) $this->conversation->band_id : null;
    }

    protected function broadcastParent(): ?array
    {
        return ['model' => 'conversation', 'id' => (int) $this->conversation_id];
    }
```

- [ ] **Step 5: Dispatch stream events from the controllers and add the typing endpoint**

In `ConversationsController` add `use App\Events\ConversationStreamEvent;` and:

- at the end of `storeMessage()`, just before the `return`:

```php
        broadcast(new ConversationStreamEvent($conversation->id, 'message.created', [
            'message' => $this->formatter->format($message),
        ]))->toOthers();
```

- at the end of `read()`, just before the `return`:

```php
        broadcast(new ConversationStreamEvent($conversation->id, 'conversation.read', [
            'user_id'      => $request->user()->id,
            'last_read_at' => $participant->last_read_at->toIso8601String(),
        ]))->toOthers();
```

- new method:

```php
    /** POST /api/mobile/conversations/{conversation}/typing — ephemeral, nothing stored. */
    public function typing(Request $request, Conversation $conversation): JsonResponse
    {
        $this->authorize('post', $conversation);

        broadcast(new ConversationStreamEvent($conversation->id, 'conversation.typing', [
            'user_id' => $request->user()->id,
            'name'    => $request->user()->name,
        ]))->toOthers();

        return response()->json(null, 204);
    }
```

In `MessagesController` add `use App\Events\ConversationStreamEvent;` and:

- in `update()`, after `$message->load([...])`:

```php
        broadcast(new ConversationStreamEvent($message->conversation_id, 'message.updated', [
            'message' => $this->formatter->format($message),
        ]))->toOthers();
```

- in `destroy()`, after `$message->delete()`:

```php
        broadcast(new ConversationStreamEvent($message->conversation_id, 'message.deleted', [
            'message_id' => $message->id,
        ]))->toOthers();
```

Route — add with the other chat routes:

```php
        Route::post('/conversations/{conversation}/typing', [App\Http\Controllers\Api\Mobile\ConversationsController::class, 'typing'])->name('mobile.conversations.typing');
```

- [ ] **Step 6: Authorize the conversation channel**

Append to `routes/channels.php`:

```php
// Open-thread channel: full message payloads (append/edit/delete), read
// receipts, and typing for whoever has the conversation on screen. Unlike
// band.{id}, payloads carry data, so auth is the full ConversationPolicy.
Broadcast::channel('conversation.{conversationId}', function ($user, $conversationId) {
    $conversation = \App\Models\Conversation::find($conversationId);

    return $conversation !== null && $user->can('view', $conversation);
});
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ChatBroadcastingTest.php tests/Feature/Api/Mobile/Chat/ConversationChannelAuthTest.php
```

Expected: PASS (6 + 3 tests). Then re-run the earlier chat suites to catch regressions from the model hooks:

```bash
docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat
```

Expected: PASS (all files).

- [ ] **Step 8: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Events/ConversationChanged.php app/Events/ConversationStreamEvent.php app/Models/Message.php app/Http/Controllers/Api/Mobile/ConversationsController.php app/Http/Controllers/Api/Mobile/MessagesController.php routes/channels.php routes/api.php tests/Feature/Api/Mobile/Chat/ChatBroadcastingTest.php tests/Feature/Api/Mobile/Chat/ConversationChannelAuthTest.php
git commit -m "feat(chat): realtime — band/user thin signals, conversation stream channel, typing

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Push notifications

**Files:**
- Create: `app/Jobs/ProcessChatMessagePush.php`
- Modify: `app/Http/Controllers/Api/Mobile/ConversationsController.php` (dispatch in `storeMessage`)
- Test: `tests/Feature/Api/Mobile/Chat/ChatPushTest.php`

**Interfaces:**
- Consumes: `SendUserPush::dispatch(int $userId, array $data, string $dedupeKey, bool $alert = false)` (existing), `ConversationPolicy`, chat models.
- Produces: FCM data payload contract for the Flutter plan (all values strings, per FCM data-message rules): `{type: 'chat_message', conversationId: '<int>', title, body}`, dedupe key `chat_message:{messageId}`.

- [ ] **Step 1: Write the failing test**

`tests/Feature/Api/Mobile/Chat/ChatPushTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Jobs\SendUserPush;
use App\Services\Chat\ConversationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

class ChatPushTest extends TestCase
{
    use RefreshDatabase, ChatTestHelpers;

    public function test_dm_message_pushes_only_to_the_other_participant(): void
    {
        Queue::fake([SendUserPush::class]);
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);

        $this->actingAs($owner)
            ->postJson("/api/mobile/conversations/{$dm->id}/messages", ['body' => 'ping'])
            ->assertStatus(201);

        Queue::assertPushed(SendUserPush::class, 1);
        Queue::assertPushed(SendUserPush::class, fn (SendUserPush $job) =>
            $job->userId === $member->id
            && $job->data['type'] === 'chat_message'
            && $job->data['conversationId'] === (string) $dm->id
            && $job->data['title'] === $owner->name
            && $job->data['body'] === 'ping'
            && str_starts_with($job->dedupeKey, 'chat_message:'));
    }

    public function test_band_channel_message_pushes_to_owner_and_members_except_author(): void
    {
        Queue::fake([SendUserPush::class]);
        [$owner, $band] = $this->makeOwnerWithBand();
        $memberA = $this->makeMember($band);
        $memberB = $this->makeMember($band);
        $channel = app(ConversationService::class)->bandChannelFor($band);

        $this->actingAs($memberA)
            ->postJson("/api/mobile/conversations/{$channel->id}/messages", ['body' => 'sound check 6pm'])
            ->assertStatus(201);

        Queue::assertPushed(SendUserPush::class, 2);
        foreach ([$owner->id, $memberB->id] as $expected) {
            Queue::assertPushed(SendUserPush::class, fn (SendUserPush $job) => $job->userId === $expected);
        }
        Queue::assertNotPushed(SendUserPush::class, fn (SendUserPush $job) => $job->userId === $memberA->id);
    }

    public function test_event_topic_message_pushes_to_readers_and_entitled_subs(): void
    {
        Queue::fake([SendUserPush::class]);
        [$owner, $band] = $this->makeOwnerWithBand();
        $member     = $this->makeMember($band, ['read:events']);
        $noRead     = $this->makeMember($band, []);
        $event      = $this->makeBookingEvent($band);
        $otherEvent = $this->makeBookingEvent($band);
        $entitled   = $this->makeSubAssignedTo($band, $event);
        $unentitled = $this->makeSubAssignedTo($band, $otherEvent);
        $topic = app(ConversationService::class)->topicFor($event);

        $this->actingAs($owner)
            ->postJson("/api/mobile/conversations/{$topic->id}/messages", ['body' => 'comment'])
            ->assertStatus(201);

        Queue::assertPushed(SendUserPush::class, 2); // member + entitled sub
        Queue::assertPushed(SendUserPush::class, fn (SendUserPush $job) => $job->userId === $member->id);
        Queue::assertPushed(SendUserPush::class, fn (SendUserPush $job) => $job->userId === $entitled->id);
        Queue::assertNotPushed(SendUserPush::class, fn (SendUserPush $job) => in_array($job->userId, [$noRead->id, $unentitled->id, $owner->id]));
    }

    public function test_image_only_message_pushes_a_photo_placeholder_body(): void
    {
        Queue::fake([SendUserPush::class]);
        \Illuminate\Support\Facades\Storage::fake(config('filesystems.default'));
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);

        $this->actingAs($owner)->post(
            "/api/mobile/conversations/{$dm->id}/messages",
            ['images' => [\Illuminate\Http\UploadedFile::fake()->image('pic.jpg')]],
            ['Accept' => 'application/json'],
        )->assertStatus(201);

        Queue::assertPushed(SendUserPush::class, fn (SendUserPush $job) => $job->data['body'] === '📷 Photo');
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ChatPushTest.php
```

Expected: FAIL — `Queue::assertPushed` finds 0 `SendUserPush` jobs.

- [ ] **Step 3: Write the fan-out job**

`app/Jobs/ProcessChatMessagePush.php`:

```php
<?php

namespace App\Jobs;

use App\Models\Conversation;
use App\Models\Message;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

/**
 * Resolves a message's audience ("push everything" per the spec) and fans
 * out one SendUserPush per recipient. Queued so the per-user permission
 * checks never sit on the send-message request path.
 */
class ProcessChatMessagePush implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public int $messageId) {}

    public function handle(): void
    {
        $message = Message::with(['conversation.band', 'user'])->find($this->messageId);
        if (!$message || $message->trashed()) {
            return;
        }

        $conversation = $message->conversation;
        $body  = $message->body !== null && $message->body !== '' ? $message->body : '📷 Photo';
        $title = $conversation->type === Conversation::TYPE_DM
            ? $message->user->name
            : ($conversation->band?->name ?? 'Band') . ' — ' . $message->user->name;

        // FCM data messages carry strings only; conversationId is stringified.
        $data = [
            'type'           => 'chat_message',
            'conversationId' => (string) $conversation->id,
            'title'          => $title,
            'body'           => $body,
        ];

        foreach ($this->recipients($conversation) as $userId) {
            if ((int) $userId === (int) $message->user_id) {
                continue;
            }
            SendUserPush::dispatch((int) $userId, $data, 'chat_message:' . $message->id);
        }
    }

    /** @return list<int> */
    private function recipients(Conversation $conversation): array
    {
        if ($conversation->type === Conversation::TYPE_DM) {
            return $conversation->participants()->pluck('user_id')->map(fn ($id) => (int) $id)->all();
        }

        $band = $conversation->band;
        if (!$band) {
            return [];
        }

        $memberIds = $band->owners()->pluck('user_id')
            ->merge($band->members()->pluck('user_id'))
            ->unique();

        if ($conversation->type === Conversation::TYPE_BAND) {
            return $memberIds->map(fn ($id) => (int) $id)->values()->all();
        }

        // Topic: audience == everyone the policy admits. Reuse the policy so
        // recipients can never drift from visibility (incl. entitled subs).
        $subIds = \DB::table('band_subs')->where('band_id', $band->id)->pluck('user_id');

        return $memberIds->merge($subIds)->unique()
            ->filter(function ($userId) use ($conversation) {
                $user = User::find($userId);

                return $user && $user->can('view', $conversation);
            })
            ->map(fn ($id) => (int) $id)->values()->all();
    }
}
```

- [ ] **Step 4: Dispatch it from storeMessage**

In `ConversationsController::storeMessage()`, add `use App\Jobs\ProcessChatMessagePush;` and, directly after the `broadcast(new ConversationStreamEvent(...))` call:

```php
        ProcessChatMessagePush::dispatch($message->id);
```

Note: `Queue::fake([SendUserPush::class])` in the tests fakes ONLY `SendUserPush`, so `ProcessChatMessagePush` still runs (sync driver in tests) and its inner dispatches are captured.

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ChatPushTest.php
```

Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Jobs/ProcessChatMessagePush.php app/Http/Controllers/Api/Mobile/ConversationsController.php tests/Feature/Api/Mobile/Chat/ChatPushTest.php
git commit -m "feat(chat): fan out chat_message pushes to conversation audience via SendUserPush

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Token ability + member-permissions exposure + full suite

**Files:**
- Modify: `app/Services/Mobile/TokenService.php` (line 14)
- Modify: `app/Http/Controllers/Api/Mobile/BandSettingsController.php` (`allPermissionNames()`, ~line 132)
- Test: `tests/Feature/Api/Mobile/Chat/ChatTokenAbilityTest.php`

**Interfaces:**
- Consumes: `TokenService::buildAbilities` (existing).
- Produces: every mobile token carries a bare `chat` ability; the member-permissions screen (`GET /bands/{band}/members`) lists `moderate:chat` so owners can grant it via the existing `setPermission` endpoint.

- [ ] **Step 1: Write the failing test**

`tests/Feature/Api/Mobile/Chat/ChatTokenAbilityTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Services\Mobile\TokenService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ChatTokenAbilityTest extends TestCase
{
    use RefreshDatabase, ChatTestHelpers;

    public function test_every_token_carries_the_chat_ability(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $event = $this->makeBookingEvent($band);
        $sub   = $this->makeSubAssignedTo($band, $event);

        $service = app(TokenService::class);
        $this->assertContains('chat', $service->buildAbilities($owner));
        $this->assertContains('chat', $service->buildAbilities($sub));
    }

    public function test_members_endpoint_exposes_moderate_chat_for_granting(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);

        $response = $this->actingAs($owner)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->getJson("/api/mobile/bands/{$band->id}/members")
            ->assertOk();

        $memberRow = collect($response->json('members'))->firstWhere('id', $member->id);
        $this->assertArrayHasKey('moderate:chat', $memberRow['permissions']);
        $this->assertFalse($memberRow['permissions']['moderate:chat']);

        $this->actingAs($owner)
            ->withHeaders(['X-Band-ID' => $band->id])
            ->patchJson("/api/mobile/bands/{$band->id}/members/{$member->id}/permissions", [
                'permission' => 'moderate:chat', 'granted' => true,
            ])->assertOk();

        $this->assertTrue($member->fresh()->canModerateChat($band->id));
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ChatTokenAbilityTest.php
```

Expected: FAIL — `'chat'` not in abilities; `moderate:chat` key missing from permissions map.

- [ ] **Step 3: Implement both edits**

In `app/Services/Mobile/TokenService.php` change line 14 from `$abilities = ['mobile'];` to:

```php
        // `chat` is structural, not permission-derived: every band role
        // (owner/member/sub) can use SOME slice of chat, and
        // ConversationPolicy is the per-conversation authority. A bare
        // ability keeps the door open for coarse route gating later.
        $abilities = ['mobile', 'chat'];
```

In `app/Http/Controllers/Api/Mobile/BandSettingsController.php` `allPermissionNames()`, append to the returned array:

```php
            'moderate:chat',
```

- [ ] **Step 4: Run the test, then the whole chat suite, to verify green**

```bash
cd /home/eddie/github/TTS && docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/ChatTokenAbilityTest.php
docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat
docker compose exec app php artisan test tests/Feature/Broadcasting tests/Feature/Api/Mobile/MobileSubEventsParityTest.php
```

Expected: PASS everywhere (the last command guards the trait/entitlement surfaces this feature touched).

- [ ] **Step 5: Commit and push**

```bash
cd /home/eddie/github/TTS && git add app/Services/Mobile/TokenService.php app/Http/Controllers/Api/Mobile/BandSettingsController.php tests/Feature/Api/Mobile/Chat/ChatTokenAbilityTest.php
git commit -m "feat(chat): chat token ability + moderate:chat grantable from member permissions

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin feat/comments-chat
```

PR (when the user asks): `gh pr create --base staging ...` — staging auto-deploys on merge.

---

## Self-review notes (done at plan-writing time)

- **Spec coverage:** data model ✓ (Task 1; `dm_key` realized as the more general `unique_key`), canonicalization ✓ (T2), policy matrix incl. sub entitlement + booking exclusion ✓ (T3), list/DM/contacts ✓ (T4), topic resolves ✓ (T5), messages CRUD/read/pagination/attachments serving ✓ (T6), all three realtime rails + typing ✓ (T7), push-everything ✓ (T8), `moderate:chat` + token ability ✓ (T1/T9). Web Vue UI and Flutter intentionally out of scope.
- **Deviations from spec, intentional:** (1) `unique_key` replaces `dm_key` so band/topic uniqueness is also DB-enforced; (2) the `chat` token ability is granted unconditionally rather than via `canRead('chat')` — chat access is structural per role and `ConversationPolicy` is the authority, avoiding a permissions backfill for every existing member; (3) typing uses a POST endpoint + server broadcast (no Pusher client-events app setting needed).
- **Wire contract (canonical, shared with the Flutter plan):** Message JSON is FLAT (`user_id`/`user_name`/`user_avatar_url`, `is_deleted`; attachments carry only `{id, width, height}` — binaries fetched via client-constructed `/api/mobile/messages/{message_id}/attachments/{id}`). Conversation JSON is `{id, type, band_id, title, last_message_preview, last_message_at, unread_count, can_moderate}`. Topic resolves AND the messages index both return the ThreadPage shape `{conversation, messages (oldest→newest), participants, channel, has_more}`. The live channel emits FIVE distinct events (`message.created`, `message.updated`, `message.deleted`, `conversation.read`, `conversation.typing`) — `ConversationStreamEvent::broadcastAs()` returns the type, payload has no envelope. Read is `POST …/read {last_read_message_id}` → 204, marker never moves backwards. Push data is `{type: 'chat_message', conversationId: '<int>', title, body}` (strings). Contacts rows are `{id, name, avatar_url, context, is_sub}`.
- **Type consistency:** `MessageFormatter::format` is used by thread pages (T5/T6) and stream payloads (T7); `summarize()` (T4) is the single Conversation JSON producer, reused by `threadPage()` (T5) and `storeDm`; `threadPage()` defined in T5 is consumed by `messages()` in T6; the five stream-event type strings in the T7 event class, controller dispatches, and Event::fake assertions match exactly.
