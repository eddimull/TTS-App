# Rehearsal Cancel/Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let band members cancel (and restore) a single rehearsal occurrence from the mobile app, notifying the rest of the band via in-app, email, and push — with the push layer generalized for future features (event chat).

**Architecture:** Backend adds `PATCH /api/mobile/rehearsals/{rehearsal}/cancelled` on the existing mobile RehearsalsController, a queued `ProcessRehearsalCancelled` job that fans out a `RehearsalCancelled` notification (database+mail) to `$band->everyone()` minus the actor, and a generic `SendUserPush` job (refactored from `SendEventPush`) keyed on a caller-supplied dedupe key. Mobile adds a repository method, cancel/restore UI on the rehearsal detail screen, new push payload types with a generic title/body fallback, and tap-to-open deep-linking.

**Tech Stack:** Laravel 11 (repo `/home/eddie/github/TTS`, branch `feat/rehearsal-cancel` off `staging`), Flutter/Riverpod v2 (repo `/home/eddie/github/tts_bandmate`, branch `feat/rehearsal-cancel` off `main`, already created), kreait/laravel-firebase, firebase_messaging + flutter_local_notifications.

**Spec:** `docs/superpowers/specs/2026-07-04-rehearsal-cancel-design.md`

## Global Constraints

- Backend commands run in Docker: `docker compose exec app php artisan test --filter=...` — NEVER run php/artisan/composer on the host.
- Backend PR targets `staging`; mobile PR targets `main`.
- No manual version bump: release-please cuts 1.10.0 from `feat:` commits on mobile `main`.
- Spec deviation (agreed rationale documented in Task 2): rehearsal pushes are sent as **notification+data hybrid** FCM messages (`alert: true` in `SendUserPush`), not data-only. A no-op background handler means data-only messages never display when the app is backgrounded/killed — the common case for a cancellation. Leave-by reminders stay data-only (unchanged behavior). The payload contract (`type`/`title`/`body` in `data`) holds for both.
- Push payload contract: every push's `data` map carries `type`, `title`, `body` (display-ready), plus type-specific routing keys. FCM data values must be strings.
- Mobile: use `context.secondaryText` (never raw `CupertinoColors.secondaryLabel` in a `color:`).
- Dates in tests: never hardcode calendar dates that will expire; compute relative to `now()`.

---

# Part 1 — Backend (repo `/home/eddie/github/TTS`)

### Task 1: Branch + generalize `push_notification_log` (dedupe key)

**Files:**
- Create: `database/migrations/2026_07_04_000001_add_dedupe_key_to_push_notification_log.php`
- Modify: `app/Models/PushNotificationLog.php`
- Test: `tests/Unit/Push/PushNotificationLogTest.php` (extend existing)

**Interfaces:**
- Consumes: existing `push_notification_log` table (`event_id` NOT NULL, unique `(event_id,user_id,type)`).
- Produces: `push_notification_log.dedupe_key` (string 120, nullable) with unique `(user_id, dedupe_key)`; `event_id` nullable; existing rows backfilled with `dedupe_key = "event:{event_id}:{type}"`. `PushNotificationLog::$fillable` includes `dedupe_key`.

- [ ] **Step 1: Create the backend branch**

```bash
cd /home/eddie/github/TTS && git checkout staging && git pull && git checkout -b feat/rehearsal-cancel
```

- [ ] **Step 2: Write the failing test**

Add to `tests/Unit/Push/PushNotificationLogTest.php` (inside the existing class; match its existing imports — it already uses `RefreshDatabase`):

```php
public function test_log_row_can_be_created_with_dedupe_key_and_no_event(): void
{
    $user = \App\Models\User::factory()->create();

    $log = \App\Models\PushNotificationLog::create([
        'user_id'    => $user->id,
        'type'       => 'rehearsal_cancelled',
        'dedupe_key' => 'rehearsal:1:cancelled:1234567890',
        'sent_at'    => now(),
    ]);

    $this->assertNull($log->event_id);
    $this->assertSame('rehearsal:1:cancelled:1234567890', $log->fresh()->dedupe_key);
}

public function test_dedupe_key_is_unique_per_user(): void
{
    $user = \App\Models\User::factory()->create();
    $attrs = [
        'user_id'    => $user->id,
        'type'       => 'rehearsal_cancelled',
        'dedupe_key' => 'rehearsal:1:cancelled:1234567890',
        'sent_at'    => now(),
    ];

    \App\Models\PushNotificationLog::create($attrs);

    $this->expectException(\Illuminate\Database\QueryException::class);
    \App\Models\PushNotificationLog::create($attrs);
}
```

- [ ] **Step 3: Run to verify failure**

Run: `docker compose exec app php artisan test --filter=PushNotificationLogTest`
Expected: FAIL — column `dedupe_key` doesn't exist / `event_id` cannot be null.

- [ ] **Step 4: Write the migration**

`database/migrations/2026_07_04_000001_add_dedupe_key_to_push_notification_log.php`:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('push_notification_log', function (Blueprint $table) {
            $table->unsignedBigInteger('event_id')->nullable()->change();
            $table->string('dedupe_key', 120)->nullable()->after('type');
        });

        // Backfill so leave-by's dedupe pre-checks keep seeing historical sends.
        DB::statement(
            "UPDATE push_notification_log SET dedupe_key = CONCAT('event:', event_id, ':', type) WHERE dedupe_key IS NULL"
        );

        Schema::table('push_notification_log', function (Blueprint $table) {
            $table->unique(['user_id', 'dedupe_key']);
        });
    }

    public function down(): void
    {
        Schema::table('push_notification_log', function (Blueprint $table) {
            $table->dropUnique(['user_id', 'dedupe_key']);
            $table->dropColumn('dedupe_key');
        });
        // event_id stays nullable on rollback: restoring NOT NULL would fail
        // if generic rows were written. Acceptable for a dev rollback.
    }
};
```

- [ ] **Step 5: Update the model**

In `app/Models/PushNotificationLog.php` change the fillable line:

```php
protected $fillable = ['event_id', 'user_id', 'type', 'dedupe_key', 'sent_at'];
```

- [ ] **Step 6: Migrate + run tests**

Run: `docker compose exec app php artisan migrate`
Then: `docker compose exec app php artisan test --filter=PushNotificationLogTest`
Expected: PASS (new tests and the pre-existing ones).

- [ ] **Step 7: Commit**

```bash
cd /home/eddie/github/TTS && git add database/migrations/2026_07_04_000001_add_dedupe_key_to_push_notification_log.php app/Models/PushNotificationLog.php tests/Unit/Push/PushNotificationLogTest.php && git commit -m "feat(push): generic dedupe_key on push_notification_log"
```

---

### Task 2: `FcmSender::sendAlert` + generic `SendUserPush` job

**Files:**
- Modify: `app/Services/Push/FcmSender.php`
- Create: `app/Jobs/SendUserPush.php`
- Test: `tests/Feature/Push/SendUserPushTest.php` (new; port assertions from `tests/Feature/Push/SendEventPushTest.php` — do NOT delete the old test yet, Task 3 does)

**Interfaces:**
- Consumes: `FcmSender::sendData(string $token, array $data): string` (existing), `PushNotificationLog` with `dedupe_key` (Task 1).
- Produces:
  - `FcmSender::sendAlert(string $token, string $title, string $body, array $data = []): string` — hybrid notification+data message on Android channel `band_updates`; returns the same DELIVERED/PRUNE/TRANSIENT constants as `sendData`.
  - `SendUserPush::__construct(public int $userId, public array $data, public string $dedupeKey, public bool $alert = false)` — job; on any delivery writes `PushNotificationLog` keyed `(user_id, dedupe_key)`; prunes dead tokens.

- [ ] **Step 1: Write the failing test**

`tests/Feature/Push/SendUserPushTest.php` — copy the mocking approach from the existing `tests/Feature/Push/SendEventPushTest.php` (read it first; it fakes/mocks `FcmSender` or the Kreait `Messaging` contract — reuse the exact same style). The behaviors to cover:

```php
<?php

namespace Tests\Feature\Push;

use App\Jobs\SendUserPush;
use App\Models\DeviceToken;
use App\Models\PushNotificationLog;
use App\Models\User;
use App\Services\Push\FcmSender;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Mockery;
use Tests\TestCase;

class SendUserPushTest extends TestCase
{
    use RefreshDatabase;

    private function fakeSender(string $result): FcmSender
    {
        $sender = Mockery::mock(FcmSender::class);
        $sender->shouldReceive('sendData')->andReturn($result)->byDefault();
        $sender->shouldReceive('sendAlert')->andReturn($result)->byDefault();
        return $sender;
    }

    public function test_delivered_send_writes_log_row_keyed_on_dedupe_key(): void
    {
        $user = User::factory()->create();
        DeviceToken::create(['user_id' => $user->id, 'token' => 'tok-1', 'platform' => 'android']);

        $job = new SendUserPush($user->id, ['type' => 'rehearsal_cancelled', 'title' => 'T', 'body' => 'B'], 'rehearsal:1:cancelled:111');
        $job->handle($this->fakeSender(FcmSender::DELIVERED));

        $this->assertDatabaseHas('push_notification_log', [
            'user_id'    => $user->id,
            'dedupe_key' => 'rehearsal:1:cancelled:111',
            'type'       => 'rehearsal_cancelled',
        ]);
    }

    public function test_alert_flag_uses_send_alert_with_title_and_body(): void
    {
        $user = User::factory()->create();
        DeviceToken::create(['user_id' => $user->id, 'token' => 'tok-1', 'platform' => 'android']);

        $sender = Mockery::mock(FcmSender::class);
        $sender->shouldReceive('sendAlert')
            ->once()
            ->with('tok-1', 'Rehearsal cancelled', 'Tuesday practice', Mockery::type('array'))
            ->andReturn(FcmSender::DELIVERED);

        $data = ['type' => 'rehearsal_cancelled', 'title' => 'Rehearsal cancelled', 'body' => 'Tuesday practice'];
        (new SendUserPush($user->id, $data, 'k1', alert: true))->handle($sender);
    }

    public function test_data_only_by_default(): void
    {
        $user = User::factory()->create();
        DeviceToken::create(['user_id' => $user->id, 'token' => 'tok-1', 'platform' => 'android']);

        $sender = Mockery::mock(FcmSender::class);
        $sender->shouldReceive('sendData')->once()->andReturn(FcmSender::DELIVERED);
        $sender->shouldNotReceive('sendAlert');

        (new SendUserPush($user->id, ['type' => 'event_reminder_8h', 'title' => 'T'], 'k2'))->handle($sender);
    }

    public function test_pruned_token_is_deleted_and_no_log_written(): void
    {
        $user = User::factory()->create();
        DeviceToken::create(['user_id' => $user->id, 'token' => 'dead', 'platform' => 'ios']);

        (new SendUserPush($user->id, ['type' => 't'], 'k3'))->handle($this->fakeSender(FcmSender::PRUNE));

        $this->assertDatabaseMissing('device_tokens', ['token' => 'dead']);
        $this->assertDatabaseMissing('push_notification_log', ['dedupe_key' => 'k3']);
    }

    public function test_duplicate_dedupe_key_does_not_create_second_row(): void
    {
        $user = User::factory()->create();
        DeviceToken::create(['user_id' => $user->id, 'token' => 'tok-1', 'platform' => 'android']);

        $data = ['type' => 'rehearsal_cancelled', 'title' => 'T', 'body' => 'B'];
        (new SendUserPush($user->id, $data, 'dup-key'))->handle($this->fakeSender(FcmSender::DELIVERED));
        (new SendUserPush($user->id, $data, 'dup-key'))->handle($this->fakeSender(FcmSender::DELIVERED));

        $this->assertSame(1, PushNotificationLog::where('dedupe_key', 'dup-key')->count());
    }
}
```

Note: if `DeviceToken::create` fails on fillable, check `app/Models/DeviceToken.php` fillable (it is `['user_id','token','platform']`).

- [ ] **Step 2: Run to verify failure**

Run: `docker compose exec app php artisan test --filter=SendUserPushTest`
Expected: FAIL — `Class "App\Jobs\SendUserPush" not found`.

- [ ] **Step 3: Add `sendAlert` to FcmSender**

In `app/Services/Push/FcmSender.php`, add imports and method:

```php
use Kreait\Firebase\Messaging\AndroidConfig;
use Kreait\Firebase\Messaging\Notification;
```

```php
    /**
     * Send a notification+data (hybrid) message to one token. The OS renders
     * the notification when the app is backgrounded/terminated; the data map
     * still carries the full payload contract for in-app routing.
     * @param array<string,string> $data
     */
    public function sendAlert(string $token, string $title, string $body, array $data = []): string
    {
        try {
            $message = CloudMessage::new()
                ->withToken($token)
                ->withNotification(Notification::create($title, $body))
                ->withData($data)
                ->withAndroidConfig(AndroidConfig::fromArray([
                    'notification' => ['channel_id' => 'band_updates'],
                ]));
            $this->messaging->send($message);
            return self::DELIVERED;
        } catch (NotFound | InvalidMessage | InvalidArgument) {
            return self::PRUNE;
        } catch (MessagingException $e) {
            Log::warning('FcmSender transient error', ['error' => $e->getMessage()]);
            return self::TRANSIENT;
        }
    }
```

- [ ] **Step 4: Create the job**

`app/Jobs/SendUserPush.php`:

```php
<?php

namespace App\Jobs;

use App\Models\DeviceToken;
use App\Models\PushNotificationLog;
use App\Services\Push\FcmSender;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

/**
 * Generic per-user push send. Callers supply the full data payload
 * (contract: type/title/body + routing keys) and a dedupe key that is
 * unique per logical send — the (user_id, dedupe_key) log row guarantees
 * at-most-one recorded delivery per user per logical send.
 */
class SendUserPush implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * @param array<string,string> $data
     */
    public function __construct(
        public int $userId,
        public array $data,
        public string $dedupeKey,
        public bool $alert = false,
    ) {}

    public function handle(FcmSender $fcm): void
    {
        $tokens = DeviceToken::where('user_id', $this->userId)->get();
        $anyDelivered = false;

        foreach ($tokens as $deviceToken) {
            $result = $this->alert
                ? $fcm->sendAlert(
                    $deviceToken->token,
                    (string) ($this->data['title'] ?? ''),
                    (string) ($this->data['body'] ?? ''),
                    $this->data,
                )
                : $fcm->sendData($deviceToken->token, $this->data);

            if ($result === FcmSender::PRUNE) {
                $deviceToken->delete();
            } elseif ($result === FcmSender::DELIVERED) {
                $anyDelivered = true;
            }
        }

        if ($anyDelivered) {
            PushNotificationLog::firstOrCreate(
                ['user_id' => $this->userId, 'dedupe_key' => $this->dedupeKey],
                ['type' => (string) ($this->data['type'] ?? 'generic'), 'sent_at' => now()],
            );
        }
    }
}
```

- [ ] **Step 5: Run tests**

Run: `docker compose exec app php artisan test --filter=SendUserPushTest`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Services/Push/FcmSender.php app/Jobs/SendUserPush.php tests/Feature/Push/SendUserPushTest.php && git commit -m "feat(push): generic SendUserPush job + FcmSender::sendAlert hybrid messages"
```

---

### Task 3: Rewire LeaveByPushService onto SendUserPush; delete SendEventPush

**Files:**
- Modify: `app/Services/Push/LeaveByPushService.php:83-104` (the dispatch loop)
- Delete: `app/Jobs/SendEventPush.php`, `tests/Feature/Push/SendEventPushTest.php`
- Test: `tests/Feature/Push/LeaveByPushServiceTest.php` (update expectations)

**Interfaces:**
- Consumes: `SendUserPush` (Task 2).
- Produces: leave-by dedupe keys of the form `event:{eventId}:{type}` (matching Task 1's backfill format); no more `SendEventPush` anywhere.

- [ ] **Step 1: Update LeaveByPushService**

In `app/Services/Push/LeaveByPushService.php`:
- Replace `use App\Jobs\SendEventPush;` with `use App\Jobs\SendUserPush;`
- Replace the body of the member loop in `dispatchForRecipients` (currently the `PushNotificationLog::where('event_id'...)` pre-check + `SendEventPush::dispatch(...)`) with:

```php
        foreach ($members as $member) {
            $dedupeKey = "event:{$event->id}:{$type}";

            // Idempotency pre-check. NOTE: the log row is written by SendUserPush
            // only after delivery, so two ticks within the grace window could both
            // pass this check and dispatch before either logs — a user could get a
            // duplicate push. The (user_id,dedupe_key) unique index guarantees a
            // single log row regardless. Acceptable for a reminder; if at-most-once
            // delivery is ever required, claim the log row here before dispatching.
            $already = PushNotificationLog::where('user_id', $member->user_id)
                ->where('dedupe_key', $dedupeKey)
                ->exists();
            if ($already) {
                continue;
            }

            SendUserPush::dispatch(
                $member->user_id,
                $this->payload($event, $type, $firstItem, $tz, $firstItemDt),
                $dedupeKey,
            );
        }
```

- [ ] **Step 2: Update LeaveByPushServiceTest**

Read `tests/Feature/Push/LeaveByPushServiceTest.php`. Everywhere it asserts `SendEventPush` was pushed/dispatched (e.g. `Queue::fake()` + `Queue::assertPushed(SendEventPush::class, ...)`), change to `SendUserPush` and adjust closure property access: the job's properties are `userId`, `data`, `dedupeKey` (there is no `eventId`/`type`/`payload` property — assert on `$job->data['type']` and `$job->dedupeKey === "event:{$event->id}:event_departure"` instead). Where the test seeds `PushNotificationLog` rows to simulate an already-sent push, set `dedupe_key => "event:{$event->id}:{$type}"` (keep `event_id`/`type` too if the factory/columns allow — both work now).

- [ ] **Step 3: Delete the old job and its test**

```bash
cd /home/eddie/github/TTS && git rm app/Jobs/SendEventPush.php tests/Feature/Push/SendEventPushTest.php
```

Then: `grep -rn "SendEventPush" app/ tests/` — expected: no matches.

- [ ] **Step 4: Run the whole push suite**

Run: `docker compose exec app php artisan test tests/Feature/Push tests/Unit/Push`
Expected: PASS (LeaveByPushServiceTest, SendUserPushTest, PushNotificationLogTest, PayloadContractTest).
If `PayloadContractTest` references `SendEventPush`, port it the same way as Step 2.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS && git add -A && git commit -m "refactor(push): leave-by reminders ride the generic SendUserPush job"
```

---

### Task 4: `RehearsalCancelled` notification (database + mail)

**Files:**
- Create: `app/Notifications/RehearsalCancelled.php`
- Test: `tests/Feature/RehearsalCancelledNotificationTest.php`

**Interfaces:**
- Consumes: `App\Models\Rehearsal` (with `rehearsalSchedule` relation), web route path `/rehearsal-schedules` (all-bands index — a link target that exists regardless of band).
- Produces: `RehearsalCancelled::__construct(Rehearsal $rehearsal, bool $isCancelled, ?string $date)`; `headline(): string`; channels `['database']` + `mail` when `$notifiable->emailNotifications`; `toArray()` includes `text`, `link`, `rehearsal_id`, `is_cancelled`, `date` (web notification dropdown reads `text`/`link` like `TTSNotification` payloads).

- [ ] **Step 1: Write the failing test**

`tests/Feature/RehearsalCancelledNotificationTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\Bands;
use App\Models\Rehearsal;
use App\Models\RehearsalSchedule;
use App\Models\User;
use App\Notifications\RehearsalCancelled;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RehearsalCancelledNotificationTest extends TestCase
{
    use RefreshDatabase;

    private function makeRehearsal(): Rehearsal
    {
        $band = Bands::factory()->create();
        $schedule = RehearsalSchedule::factory()->weekly()->create([
            'band_id' => $band->id,
            'name'    => 'Tuesday Practice',
        ]);

        return Rehearsal::factory()->create([
            'rehearsal_schedule_id' => $schedule->id,
            'band_id'               => $band->id,
        ]);
    }

    public function test_channels_are_database_plus_mail_when_email_enabled(): void
    {
        $rehearsal = $this->makeRehearsal();
        $emailOn  = User::factory()->create(['emailNotifications' => true]);
        $emailOff = User::factory()->create(['emailNotifications' => false]);

        $n = new RehearsalCancelled($rehearsal, true, now()->addDays(3)->toDateString());

        $this->assertEqualsCanonicalizing(['database', 'mail'], $n->via($emailOn));
        $this->assertSame(['database'], $n->via($emailOff));
    }

    public function test_cancelled_headline_and_payload(): void
    {
        $rehearsal = $this->makeRehearsal();
        $date = now()->addDays(3)->toDateString();

        $n = new RehearsalCancelled($rehearsal, true, $date);
        $payload = $n->toArray(User::factory()->create());

        $this->assertStringContainsString('Tuesday Practice', $payload['text']);
        $this->assertStringContainsString('cancelled', $payload['text']);
        $this->assertSame($rehearsal->id, $payload['rehearsal_id']);
        $this->assertTrue($payload['is_cancelled']);
        $this->assertSame($date, $payload['date']);
        $this->assertSame('/rehearsal-schedules', $payload['link']);
    }

    public function test_restored_headline(): void
    {
        $rehearsal = $this->makeRehearsal();
        $n = new RehearsalCancelled($rehearsal, false, now()->addDays(3)->toDateString());

        $this->assertStringContainsString('back on', $n->toArray(User::factory()->create())['text']);
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `docker compose exec app php artisan test --filter=RehearsalCancelledNotificationTest`
Expected: FAIL — class not found.

- [ ] **Step 3: Create the notification**

`app/Notifications/RehearsalCancelled.php`:

```php
<?php

namespace App\Notifications;

use App\Models\Rehearsal;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;
use Illuminate\Support\Carbon;

class RehearsalCancelled extends Notification
{
    use Queueable;

    public function __construct(
        public Rehearsal $rehearsal,
        public bool $isCancelled,
        public ?string $date,
    ) {}

    public function via($notifiable): array
    {
        $channels = ['database'];
        if ($notifiable->emailNotifications) {
            $channels[] = 'mail';
        }

        return $channels;
    }

    public function headline(): string
    {
        $name = $this->rehearsal->rehearsalSchedule?->name ?? 'Rehearsal';
        $when = '';
        if ($this->date) {
            try {
                $when = ' on ' . Carbon::parse($this->date)->format('F j, Y');
            } catch (\Throwable) {
                $when = '';
            }
        }

        return $this->isCancelled
            ? "{$name}{$when} was cancelled"
            : "{$name}{$when} is back on";
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject($this->headline())
            ->line($this->headline())
            ->action('View Rehearsals', config('app.url') . '/rehearsal-schedules');
    }

    public function toArray($notifiable): array
    {
        return [
            'text'         => $this->headline(),
            'link'         => '/rehearsal-schedules',
            'rehearsal_id' => $this->rehearsal->id,
            'is_cancelled' => $this->isCancelled,
            'date'         => $this->date,
        ];
    }
}
```

- [ ] **Step 4: Run tests**

Run: `docker compose exec app php artisan test --filter=RehearsalCancelledNotificationTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Notifications/RehearsalCancelled.php tests/Feature/RehearsalCancelledNotificationTest.php && git commit -m "feat(rehearsals): RehearsalCancelled notification (database + gated mail)"
```

---

### Task 5: `ProcessRehearsalCancelled` fan-out job

**Files:**
- Create: `app/Jobs/ProcessRehearsalCancelled.php`
- Test: `tests/Feature/ProcessRehearsalCancelledTest.php`

**Interfaces:**
- Consumes: `RehearsalCancelled` (Task 4), `SendUserPush` (Task 2), `Bands::everyone()` (merged owners+members collection; each item has `->user` and a `user_id` attribute).
- Produces: `ProcessRehearsalCancelled::__construct(Rehearsal $rehearsal, int $actorId, bool $isCancelled, string $dedupeKey)`. Behavior: notifies every band member+owner except the actor; dispatches `SendUserPush(..., alert: true)` only for recipients with device tokens; push data `type` is `rehearsal_cancelled`/`rehearsal_restored` with `title`, `body`, `rehearsalId`, `date` (all strings).

- [ ] **Step 1: Write the failing test**

`tests/Feature/ProcessRehearsalCancelledTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Jobs\ProcessRehearsalCancelled;
use App\Jobs\SendUserPush;
use App\Models\Bands;
use App\Models\DeviceToken;
use App\Models\Events;
use App\Models\EventTypes;
use App\Models\Rehearsal;
use App\Models\RehearsalSchedule;
use App\Models\User;
use App\Notifications\RehearsalCancelled;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

class ProcessRehearsalCancelledTest extends TestCase
{
    use RefreshDatabase;

    /** @return array{rehearsal: Rehearsal, actor: User, member: User, memberWithDevice: User} */
    private function setUpBandWithRehearsal(): array
    {
        $actor  = User::factory()->create();
        $member = User::factory()->create();
        $memberWithDevice = User::factory()->create();

        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $actor->id]);
        $band->members()->create(['user_id' => $member->id]);
        $band->members()->create(['user_id' => $memberWithDevice->id]);

        DeviceToken::create(['user_id' => $memberWithDevice->id, 'token' => 'tok-x', 'platform' => 'android']);

        $schedule = RehearsalSchedule::factory()->weekly()->create([
            'band_id' => $band->id,
            'name'    => 'Tuesday Practice',
        ]);
        $rehearsal = Rehearsal::factory()->create([
            'rehearsal_schedule_id' => $schedule->id,
            'band_id'               => $band->id,
        ]);
        Events::factory()->create([
            'eventable_id'   => $rehearsal->id,
            'eventable_type' => 'App\\Models\\Rehearsal',
            'event_type_id'  => EventTypes::factory()->create()->id,
            'date'           => now()->addDays(5)->format('Y-m-d'),
            'start_time'     => '19:00:00',
        ]);

        return compact('rehearsal', 'actor', 'member', 'memberWithDevice');
    }

    public function test_notifies_everyone_except_actor(): void
    {
        Notification::fake();
        Queue::fake();
        ['rehearsal' => $rehearsal, 'actor' => $actor, 'member' => $member, 'memberWithDevice' => $withDevice] =
            $this->setUpBandWithRehearsal();

        (new ProcessRehearsalCancelled($rehearsal, $actor->id, true, 'key-1'))->handle();

        Notification::assertSentTo($member, RehearsalCancelled::class);
        Notification::assertSentTo($withDevice, RehearsalCancelled::class);
        Notification::assertNotSentTo($actor, RehearsalCancelled::class);
    }

    public function test_push_only_to_members_with_device_tokens(): void
    {
        Notification::fake();
        Queue::fake();
        ['rehearsal' => $rehearsal, 'actor' => $actor, 'member' => $member, 'memberWithDevice' => $withDevice] =
            $this->setUpBandWithRehearsal();

        (new ProcessRehearsalCancelled($rehearsal, $actor->id, true, 'key-2'))->handle();

        Queue::assertPushed(SendUserPush::class, function (SendUserPush $job) use ($withDevice, $rehearsal) {
            return $job->userId === $withDevice->id
                && $job->alert === true
                && $job->dedupeKey === 'key-2'
                && $job->data['type'] === 'rehearsal_cancelled'
                && $job->data['rehearsalId'] === (string) $rehearsal->id
                && $job->data['title'] !== ''
                && $job->data['body'] !== '';
        });
        Queue::assertNotPushed(SendUserPush::class, fn (SendUserPush $job) => $job->userId === $member->id);
        Queue::assertNotPushed(SendUserPush::class, fn (SendUserPush $job) => $job->userId === $actor->id);
    }

    public function test_restore_sends_restored_type(): void
    {
        Notification::fake();
        Queue::fake();
        ['rehearsal' => $rehearsal, 'actor' => $actor] = $this->setUpBandWithRehearsal();

        (new ProcessRehearsalCancelled($rehearsal, $actor->id, false, 'key-3'))->handle();

        Queue::assertPushed(SendUserPush::class, fn (SendUserPush $job) => $job->data['type'] === 'rehearsal_restored');
    }
}
```

Note: if `$band->members()->create(...)` fails, check how other tests attach plain members (e.g. grep `members()->create` in `tests/`) and use that idiom; `BandMembers` may require additional columns.

- [ ] **Step 2: Run to verify failure**

Run: `docker compose exec app php artisan test --filter=ProcessRehearsalCancelledTest`
Expected: FAIL — class not found.

- [ ] **Step 3: Create the job**

`app/Jobs/ProcessRehearsalCancelled.php`:

```php
<?php

namespace App\Jobs;

use App\Models\Rehearsal;
use App\Notifications\RehearsalCancelled;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Carbon;

class ProcessRehearsalCancelled implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(
        public Rehearsal $rehearsal,
        public int $actorId,
        public bool $isCancelled,
        public string $dedupeKey,
    ) {}

    public function handle(): void
    {
        $this->rehearsal->loadMissing(['rehearsalSchedule.band', 'events', 'band']);
        $band = $this->rehearsal->rehearsalSchedule?->band ?? $this->rehearsal->band;
        if (!$band) {
            return;
        }

        $event = $this->rehearsal->events->first();
        $date = $event
            ? (is_string($event->date) ? $event->date : $event->date->format('Y-m-d'))
            : null;

        $name = $this->rehearsal->rehearsalSchedule?->name ?? 'Rehearsal';
        $whenText = $date ? Carbon::parse($date)->format('D, M j') : 'upcoming';

        $push = [
            'type'        => $this->isCancelled ? 'rehearsal_cancelled' : 'rehearsal_restored',
            'title'       => $this->isCancelled ? 'Rehearsal cancelled' : 'Rehearsal back on',
            'body'        => "{$name} · {$whenText}",
            'rehearsalId' => (string) $this->rehearsal->id,
        ];
        if ($date) {
            $push['date'] = $date;
        }

        foreach ($band->everyone() as $member) {
            $user = $member->user;
            if (!$user || $user->id === $this->actorId) {
                continue;
            }

            $user->notify(new RehearsalCancelled($this->rehearsal, $this->isCancelled, $date));

            if ($user->deviceTokens()->exists()) {
                SendUserPush::dispatch($user->id, $push, $this->dedupeKey, true);
            }
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `docker compose exec app php artisan test --filter=ProcessRehearsalCancelledTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS && git add app/Jobs/ProcessRehearsalCancelled.php tests/Feature/ProcessRehearsalCancelledTest.php && git commit -m "feat(rehearsals): fan-out job notifying band on cancel/restore"
```

---

### Task 6: Mobile endpoint `PATCH /api/mobile/rehearsals/{rehearsal}/cancelled`

**Files:**
- Create: `app/Http/Requests/Mobile/SetRehearsalCancelledRequest.php`
- Modify: `app/Http/Controllers/Api/Mobile/RehearsalsController.php` (add `setCancelled` after `updateNotes`), `routes/api.php` (next to the `mobile.rehearsals.update-notes` route, around line 332)
- Test: `tests/Feature/Api/Mobile/RehearsalsTest.php` (extend)

**Interfaces:**
- Consumes: `ProcessRehearsalCancelled` (Task 5), `RehearsalService::formatDetail` (existing), the test helper `createUserWithBandAndRehearsal()` already in `RehearsalsTest`.
- Produces: route name `mobile.rehearsals.set-cancelled`; response `{"rehearsal": {…formatDetail…}}`; dispatches `ProcessRehearsalCancelled` only on a real state change.

- [ ] **Step 1: Write the failing tests**

Append to `tests/Feature/Api/Mobile/RehearsalsTest.php` (add `use App\Jobs\ProcessRehearsalCancelled;` and `use Illuminate\Support\Facades\Queue;` to the imports):

```php
    // -------------------------------------------------------------------------
    // rehearsals.set-cancelled
    // -------------------------------------------------------------------------

    public function test_set_cancelled_cancels_a_rehearsal_and_dispatches_fanout(): void
    {
        Queue::fake();
        ['rehearsal' => $rehearsal, 'token' => $token] = $this->createUserWithBandAndRehearsal();

        $response = $this->withToken($token)
            ->patchJson("/api/mobile/rehearsals/{$rehearsal->id}/cancelled", ['is_cancelled' => true]);

        $response->assertOk();
        $this->assertTrue($response->json('rehearsal.is_cancelled'));
        $this->assertTrue($rehearsal->fresh()->is_cancelled);
        Queue::assertPushed(ProcessRehearsalCancelled::class, 1);
    }

    public function test_set_cancelled_restores_a_cancelled_rehearsal(): void
    {
        Queue::fake();
        ['rehearsal' => $rehearsal, 'token' => $token] = $this->createUserWithBandAndRehearsal();
        $rehearsal->update(['is_cancelled' => true]);

        $response = $this->withToken($token)
            ->patchJson("/api/mobile/rehearsals/{$rehearsal->id}/cancelled", ['is_cancelled' => false]);

        $response->assertOk();
        $this->assertFalse($response->json('rehearsal.is_cancelled'));
        $this->assertFalse($rehearsal->fresh()->is_cancelled);
        Queue::assertPushed(ProcessRehearsalCancelled::class, 1);
    }

    public function test_set_cancelled_is_idempotent_and_skips_fanout_when_unchanged(): void
    {
        Queue::fake();
        ['rehearsal' => $rehearsal, 'token' => $token] = $this->createUserWithBandAndRehearsal();
        $rehearsal->update(['is_cancelled' => true]);

        $this->withToken($token)
            ->patchJson("/api/mobile/rehearsals/{$rehearsal->id}/cancelled", ['is_cancelled' => true])
            ->assertOk();

        Queue::assertNotPushed(ProcessRehearsalCancelled::class);
    }

    public function test_set_cancelled_requires_boolean_body(): void
    {
        ['rehearsal' => $rehearsal, 'token' => $token] = $this->createUserWithBandAndRehearsal();

        $this->withToken($token)
            ->patchJson("/api/mobile/rehearsals/{$rehearsal->id}/cancelled", [])
            ->assertStatus(422);
    }

    public function test_set_cancelled_returns_403_for_user_without_access(): void
    {
        ['rehearsal' => $rehearsal] = $this->createUserWithBandAndRehearsal();
        $otherToken = User::factory()->create()->createToken('test-device')->plainTextToken;

        $this->withToken($otherToken)
            ->patchJson("/api/mobile/rehearsals/{$rehearsal->id}/cancelled", ['is_cancelled' => true])
            ->assertStatus(403);
    }

    public function test_set_cancelled_requires_authentication(): void
    {
        ['rehearsal' => $rehearsal] = $this->createUserWithBandAndRehearsal();

        $this->patchJson("/api/mobile/rehearsals/{$rehearsal->id}/cancelled", ['is_cancelled' => true])
            ->assertUnauthorized();
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `docker compose exec app php artisan test --filter=RehearsalsTest`
Expected: new tests FAIL (405/404 — route missing); pre-existing tests PASS.

- [ ] **Step 3: Create the FormRequest**

`app/Http/Requests/Mobile/SetRehearsalCancelledRequest.php`:

```php
<?php

namespace App\Http\Requests\Mobile;

use Illuminate\Foundation\Http\FormRequest;

class SetRehearsalCancelledRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // Auth handled by middleware (auth:sanctum) + controller canWrite check
    }

    public function rules(): array
    {
        return [
            'is_cancelled' => ['required', 'boolean'],
        ];
    }
}
```

- [ ] **Step 4: Add the controller action**

In `app/Http/Controllers/Api/Mobile/RehearsalsController.php`, add imports:

```php
use App\Http\Requests\Mobile\SetRehearsalCancelledRequest;
use App\Jobs\ProcessRehearsalCancelled;
```

Add after `updateNotes()`:

```php
    /**
     * PATCH /api/mobile/rehearsals/{rehearsal}/cancelled
     *
     * Explicitly set (not toggle) the cancelled flag. Idempotent: setting the
     * current value succeeds without notifying the band again.
     */
    public function setCancelled(SetRehearsalCancelledRequest $request, int $rehearsal): JsonResponse
    {
        $rehearsalModel = Rehearsal::with(['rehearsalSchedule.band', 'events', 'bookings'])
            ->findOrFail($rehearsal);

        $band = $rehearsalModel->rehearsalSchedule?->band ?? $rehearsalModel->band;

        if (!$band) {
            abort(404, 'Band not found for this rehearsal.');
        }

        if (!$request->user()->canWrite('rehearsals', $band->id)) {
            abort(403, 'You do not have permission to edit this rehearsal.');
        }

        $isCancelled = (bool) $request->validated()['is_cancelled'];

        if ($rehearsalModel->is_cancelled !== $isCancelled) {
            $rehearsalModel->update(['is_cancelled' => $isCancelled]);
            $rehearsalModel->refresh();

            ProcessRehearsalCancelled::dispatch(
                $rehearsalModel,
                $request->user()->id,
                $isCancelled,
                sprintf(
                    'rehearsal:%d:%s:%d',
                    $rehearsalModel->id,
                    $isCancelled ? 'cancelled' : 'restored',
                    $rehearsalModel->updated_at->timestamp,
                ),
            );
        }

        $rehearsalModel->load(['rehearsalSchedule', 'events', 'bookings']);

        return response()->json([
            'rehearsal' => $this->rehearsalService->formatDetail($rehearsalModel),
        ]);
    }
```

- [ ] **Step 5: Register the route**

In `routes/api.php`, directly below the `mobile.rehearsals.update-notes` line:

```php
        Route::patch('/rehearsals/{rehearsal}/cancelled', [App\Http\Controllers\Api\Mobile\RehearsalsController::class, 'setCancelled'])->name('mobile.rehearsals.set-cancelled');
```

- [ ] **Step 6: Run tests**

Run: `docker compose exec app php artisan test --filter=RehearsalsTest`
Expected: ALL PASS.

- [ ] **Step 7: Full backend suite + commit**

Run: `docker compose exec app php artisan test`
Expected: PASS (if the two known flaky tests from memory — band_roles / bands.site_name — fail under parallel, re-run those sequentially before concluding breakage).

```bash
cd /home/eddie/github/TTS && git add app/Http/Requests/Mobile/SetRehearsalCancelledRequest.php app/Http/Controllers/Api/Mobile/RehearsalsController.php routes/api.php tests/Feature/Api/Mobile/RehearsalsTest.php && git commit -m "feat(rehearsals): mobile endpoint to cancel/restore a rehearsal occurrence"
```

---

# Part 2 — Mobile (repo `/home/eddie/github/tts_bandmate`, branch `feat/rehearsal-cancel` already exists)

### Task 7: Repository method + endpoint constant

**Files:**
- Modify: `lib/core/network/api_endpoints.dart` (after `mobileRehearsalUpdateNotes`, ~line 91), `lib/features/rehearsals/data/rehearsals_repository.dart`
- Test: `test/features/rehearsals/rehearsals_repository_test.dart` (create; `test/features/rehearsals/` doesn't exist yet)

**Interfaces:**
- Consumes: backend endpoint from Task 6.
- Produces: `ApiEndpoints.mobileRehearsalSetCancelled(int rehearsalId)`; `RehearsalsRepository.setCancelled(int rehearsalId, bool isCancelled) → Future<RehearsalDetail>`.

- [ ] **Step 1: Write the failing test**

`test/features/rehearsals/rehearsals_repository_test.dart` — mock Dio with a handcrafted adapter. Look at an existing repository test for the project's Dio-mocking idiom first (`grep -rl "DioAdapter\|Interceptor\|MockDio" test/ | head`); if the project has none for PATCH, use this pattern with a `Dio` whose `HttpClientAdapter` is faked:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsals/data/rehearsals_repository.dart';

/// Adapter that records the request and returns a canned JSON response.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responseBody);

  final Map<String, dynamic> responseBody;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(responseBody),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('setCancelled PATCHes the cancelled endpoint and parses the detail', () async {
    final adapter = _FakeAdapter({
      'rehearsal': {
        'id': 42,
        'date': '2099-01-05',
        'time': '19:00',
        'venue_name': 'The Shed',
        'is_cancelled': true,
        'notes': null,
        'event_key': 'k-1',
        'schedule': {'id': 7, 'name': 'Tuesday Practice', 'location_name': 'The Shed'},
        'associated_bookings': [],
      },
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = adapter;
    final repo = RehearsalsRepository(dio);

    final detail = await repo.setCancelled(42, true);

    expect(adapter.lastRequest!.method, 'PATCH');
    expect(adapter.lastRequest!.path, '/api/mobile/rehearsals/42/cancelled');
    expect(adapter.lastRequest!.data, {'is_cancelled': true});
    expect(detail.id, 42);
    expect(detail.isCancelled, isTrue);
  });
}
```

(Add `import 'dart:typed_data';` if `Uint8List` is unresolved.)

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/rehearsals/rehearsals_repository_test.dart`
Expected: FAIL — `setCancelled` isn't defined.

- [ ] **Step 3: Implement**

`lib/core/network/api_endpoints.dart`, after `mobileRehearsalUpdateNotes`:

```dart
  static String mobileRehearsalSetCancelled(int rehearsalId) =>
      '/api/mobile/rehearsals/$rehearsalId/cancelled';
```

`lib/features/rehearsals/data/rehearsals_repository.dart`, after `updateNotes`:

```dart
  /// Sets (not toggles) the cancelled flag on a rehearsal. Returns the
  /// refreshed [RehearsalDetail].
  Future<RehearsalDetail> setCancelled(int rehearsalId, bool isCancelled) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalSetCancelled(rehearsalId),
      data: {'is_cancelled': isCancelled},
    );

    final data = response.data!;
    return RehearsalDetail.fromJson(data['rehearsal'] as Map<String, dynamic>);
  }
```

(Note: this file references `ApiEndpoints` already via `core_providers.dart` import chain — check the top of the file; it uses `ApiEndpoints` from `package:tts_bandmate/core/network/api_endpoints.dart`; add the import if not present.)

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/rehearsals/rehearsals_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/core/network/api_endpoints.dart lib/features/rehearsals/data/rehearsals_repository.dart test/features/rehearsals/rehearsals_repository_test.dart && git commit -m "feat(rehearsals): repository setCancelled + endpoint constant"
```

---

### Task 8: Cancel/restore UI on the rehearsal detail screen

**Files:**
- Modify: `lib/features/rehearsals/screens/rehearsal_detail_screen.dart`
- Test: `test/features/rehearsals/rehearsal_cancel_widget_test.dart` (create)

**Interfaces:**
- Consumes: `RehearsalsRepository.setCancelled` (Task 7), `rehearsalDetailProvider` / `schedulesProvider` (`lib/features/rehearsals/providers/rehearsals_provider.dart`), `selectedBandProvider` (`lib/shared/providers/selected_band_provider.dart`, `AsyncNotifier<int?>`), `dashboardProvider` (`lib/features/dashboard/providers/dashboard_provider.dart`).
- Produces: "Cancel Rehearsal" destructive button at the bottom of the detail ListView (upcoming, non-cancelled only) behind a `CupertinoActionSheet`; "Restore" button inside the cancelled banner behind a `CupertinoAlertDialog`; local state updates immediately from the PATCH response; invalidates detail/schedules/dashboard providers.

- [ ] **Step 1: Write the failing widget test**

`test/features/rehearsals/rehearsal_cancel_widget_test.dart`. The screen takes `preloaded:` which skips network on first build — perfect for widget tests. Override `rehearsalsRepositoryProvider` with a fake:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_detail.dart';
import 'package:tts_bandmate/features/rehearsals/data/rehearsals_repository.dart';
import 'package:tts_bandmate/features/rehearsals/screens/rehearsal_detail_screen.dart';

class _FakeRehearsalsRepository extends RehearsalsRepository {
  _FakeRehearsalsRepository() : super(Dio());

  final calls = <(int, bool)>[];

  @override
  Future<RehearsalDetail> setCancelled(int rehearsalId, bool isCancelled) async {
    calls.add((rehearsalId, isCancelled));
    return _detail(isCancelled: isCancelled);
  }
}

RehearsalDetail _detail({bool isCancelled = false}) {
  final future = DateTime.now().add(const Duration(days: 7));
  final date =
      '${future.year}-${future.month.toString().padLeft(2, '0')}-${future.day.toString().padLeft(2, '0')}';
  return RehearsalDetail.fromJson({
    'id': 42,
    'date': date,
    'time': '19:00',
    'venue_name': 'The Shed',
    'is_cancelled': isCancelled,
    'notes': null,
    'event_key': 'k-1',
    'schedule': {'id': 7, 'name': 'Tuesday Practice', 'location_name': 'The Shed'},
    'associated_bookings': [],
  });
}

Widget _app(_FakeRehearsalsRepository repo, RehearsalDetail preloaded) {
  return ProviderScope(
    overrides: [rehearsalsRepositoryProvider.overrideWithValue(repo)],
    child: CupertinoApp(home: RehearsalDetailScreen(preloaded: preloaded)),
  );
}

void main() {
  testWidgets('upcoming rehearsal shows cancel button; confirming calls repo', (tester) async {
    final repo = _FakeRehearsalsRepository();
    await tester.pumpWidget(_app(repo, _detail()));

    expect(find.text('Cancel Rehearsal'), findsOneWidget);

    await tester.tap(find.text('Cancel Rehearsal'));
    await tester.pumpAndSettle();

    // Action sheet with a destructive confirm.
    expect(find.text('Cancel this rehearsal?'), findsOneWidget);
    await tester.tap(find.text('Cancel Rehearsal').last);
    await tester.pumpAndSettle();

    expect(repo.calls, [(42, true)]);
    // UI flipped to cancelled state.
    expect(find.text('This rehearsal has been cancelled.'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
  });

  testWidgets('cancelled rehearsal shows restore; confirming calls repo', (tester) async {
    final repo = _FakeRehearsalsRepository();
    await tester.pumpWidget(_app(repo, _detail(isCancelled: true)));

    expect(find.text('Cancel Rehearsal'), findsNothing);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Restore this rehearsal?'), findsOneWidget);
    await tester.tap(find.text('Restore').last);
    await tester.pumpAndSettle();

    expect(repo.calls, [(42, false)]);
    expect(find.text('This rehearsal has been cancelled.'), findsNothing);
  });

  testWidgets('past rehearsal shows no cancel button', (tester) async {
    final repo = _FakeRehearsalsRepository();
    final past = RehearsalDetail.fromJson({
      'id': 42,
      'date': '2020-01-01',
      'time': '19:00',
      'venue_name': 'The Shed',
      'is_cancelled': false,
      'notes': null,
      'event_key': 'k-1',
      'schedule': {'id': 7, 'name': 'Tuesday Practice', 'location_name': 'The Shed'},
      'associated_bookings': [],
    });
    await tester.pumpWidget(_app(repo, past));

    expect(find.text('Cancel Rehearsal'), findsNothing);
  });
}
```

Note: if `ref.invalidate(dashboardProvider)` / `selectedBandProvider` reads inside the handler make the ProviderScope throw in tests (network-backed providers), the implementation guards them (see Step 3's `_invalidateCaches` — reads are wrapped so overrides aren't required). If a test still trips on an uninitialized provider, add the minimal `overrideWith` for it rather than removing the invalidation.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/rehearsals/rehearsal_cancel_widget_test.dart`
Expected: FAIL — no 'Cancel Rehearsal' text found.

- [ ] **Step 3: Implement**

In `lib/features/rehearsals/screens/rehearsal_detail_screen.dart`:

1. Add imports:

```dart
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
```

2. In `_RehearsalDetailViewState`, make the rehearsal mutable local state. Add fields and change `initState`:

```dart
  late RehearsalDetail _rehearsal;
  bool _togglingCancelled = false;
```

```dart
  @override
  void initState() {
    super.initState();
    _rehearsal = widget.rehearsal;
    _notes = widget.rehearsal.notes;
    _notesController = TextEditingController(text: _notes ?? '');
  }
```

3. In `build()`, replace `final rehearsal = widget.rehearsal;` with `final rehearsal = _rehearsal;`. In `_canPlan` nothing changes (it receives the rehearsal). Everywhere else in the state class that reads `widget.rehearsal` (the planner button's `rehearsal.id` usages already go through the local `rehearsal` variable — verify with a grep for `widget.rehearsal` and switch remaining reads to `_rehearsal`).

4. Add the mutation + helpers to `_RehearsalDetailViewState`:

```dart
  /// Upcoming (today or later) — mirrors _canPlan's date logic without the
  /// cancelled check.
  bool _isUpcoming(RehearsalDetail rehearsal) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = rehearsal.parsedDate;
    return !DateTime(d.year, d.month, d.day).isBefore(today);
  }

  Future<void> _setCancelled(bool cancel) async {
    setState(() => _togglingCancelled = true);
    try {
      final repo = ref.read(rehearsalsRepositoryProvider);
      final updated = await repo.setCancelled(_rehearsal.id, cancel);
      if (!mounted) return;
      setState(() => _rehearsal = updated);
      _invalidateCaches();
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(
                'Failed to ${cancel ? 'cancel' : 'restore'} the rehearsal: $e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingCancelled = false);
    }
  }

  /// Refresh every surface that renders this rehearsal's cancelled state.
  /// Guarded: cache invalidation must never break the mutation UX.
  void _invalidateCaches() {
    try {
      ref.invalidate(rehearsalDetailProvider(_rehearsal.id));
      final bandId = ref.read(selectedBandProvider).value;
      if (bandId != null) ref.invalidate(schedulesProvider(bandId));
      ref.invalidate(dashboardProvider);
    } catch (_) {
      // Providers may be absent in tests; the local state is already correct.
    }
  }

  void _confirmCancel() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Cancel this rehearsal?'),
        message: const Text(
            'Everyone in the band will be notified. You can restore it later.'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(sheetContext);
              _setCancelled(true);
            },
            child: const Text('Cancel Rehearsal'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Keep Rehearsal'),
        ),
      ),
    );
  }

  void _confirmRestore() {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Restore this rehearsal?'),
        content: const Text('Everyone in the band will be notified.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Keep Cancelled'),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Restore'),
            onPressed: () {
              Navigator.pop(dialogContext);
              _setCancelled(false);
            },
          ),
        ],
      ),
    );
  }
```

5. Add a "Restore" button to the cancelled banner. The banner's `Row` (currently icon + text) becomes:

```dart
              child: Row(
                children: [
                  Icon(CupertinoIcons.xmark_circle,
                      color: CupertinoColors.systemRed.resolveFrom(context), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This rehearsal has been cancelled.',
                      style: TextStyle(
                        color: CupertinoColors.systemRed.resolveFrom(context),
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
                    onPressed: _togglingCancelled ? null : _confirmRestore,
                    child: _togglingCancelled
                        ? const CupertinoActivityIndicator()
                        : const Text('Restore', style: TextStyle(fontSize: 15)),
                  ),
                ],
              ),
```

6. Add the cancel button at the bottom of the `ListView`, just before the closing `const SizedBox(height: 32),`:

```dart
          if (!rehearsal.isCancelled && _isUpcoming(rehearsal)) ...[
            const SizedBox(height: 24),
            CupertinoButton(
              onPressed: _togglingCancelled ? null : _confirmCancel,
              child: _togglingCancelled
                  ? const CupertinoActivityIndicator()
                  : Text(
                      'Cancel Rehearsal',
                      style: TextStyle(
                        color: CupertinoColors.systemRed.resolveFrom(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ],
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/rehearsals/`
Expected: PASS (all three widget tests + repository test).

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/rehearsals/screens/rehearsal_detail_screen.dart test/features/rehearsals/rehearsal_cancel_widget_test.dart && git commit -m "feat(rehearsals): cancel/restore actions on rehearsal detail screen"
```

---

### Task 9: Push payload types + generic title/body fallback + band_updates channel

**Files:**
- Modify: `lib/features/notifications/data/push_payload.dart`, `lib/features/notifications/services/push_service.dart`
- Test: `test/notifications/push_payload_test.dart` (extend)

**Interfaces:**
- Consumes: backend payload contract (`type`/`title`/`body` strings; `rehearsalId` for rehearsal types).
- Produces: `PushType.rehearsalCancelled`, `PushType.rehearsalRestored`; `PushPayload.body` and `PushPayload.rehearsalId` fields; `_show` renders `title`/`body` verbatim for non-reminder payloads on Android channel `band_updates`; unknown types with `title`+`body` render generically (no more hardcoded "Event today" for them).

- [ ] **Step 1: Write the failing tests**

Add to `test/notifications/push_payload_test.dart` (match its existing imports/group style):

```dart
  test('rehearsal_cancelled parses type, body and rehearsalId', () {
    final p = PushPayload.fromData({
      'type': 'rehearsal_cancelled',
      'title': 'Rehearsal cancelled',
      'body': 'Tuesday Practice · Tue, Jul 7',
      'rehearsalId': '42',
    });
    expect(p.type, PushType.rehearsalCancelled);
    expect(p.body, 'Tuesday Practice · Tue, Jul 7');
    expect(p.rehearsalId, '42');
  });

  test('rehearsal_restored parses', () {
    final p = PushPayload.fromData({'type': 'rehearsal_restored', 'title': 't', 'body': 'b'});
    expect(p.type, PushType.rehearsalRestored);
  });

  test('unknown type keeps title and body for generic rendering', () {
    final p = PushPayload.fromData({'type': 'event_chat_message', 'title': 'New message', 'body': 'hi'});
    expect(p.type, PushType.unknown);
    expect(p.title, 'New message');
    expect(p.body, 'hi');
  });

  test('notification ids differ per type for the same rehearsal', () {
    final a = PushPayload.fromData({'type': 'rehearsal_cancelled', 'rehearsalId': '42'});
    final b = PushPayload.fromData({'type': 'rehearsal_restored', 'rehearsalId': '42'});
    expect(a.notificationId, isNot(b.notificationId));
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/notifications/push_payload_test.dart`
Expected: FAIL — `PushType.rehearsalCancelled` / `body` / `rehearsalId` undefined.

- [ ] **Step 3: Implement `push_payload.dart` changes**

In `lib/features/notifications/data/push_payload.dart`:

```dart
enum PushType { reminder8h, departure, rehearsalCancelled, rehearsalRestored, unknown }
```

Extend `_typeFromString`:

```dart
PushType _typeFromString(String? raw) {
  switch (raw) {
    case 'event_reminder_8h':
      return PushType.reminder8h;
    case 'event_departure':
      return PushType.departure;
    case 'rehearsal_cancelled':
      return PushType.rehearsalCancelled;
    case 'rehearsal_restored':
      return PushType.rehearsalRestored;
    default:
      return PushType.unknown;
  }
}
```

Add fields `body` and `rehearsalId` to `PushPayload` (constructor params `this.body, this.rehearsalId`, final fields, and in `fromData`: `body: str('body'), rehearsalId: str('rehearsalId'),`).

Change `notificationId` so payloads without an eventKey still get a stable, distinct slot:

```dart
  /// Stable id for deduping notifications: one slot per entity+type. Departure
  /// keeps its shared-slot contract with the enrichment scheduler; everything
  /// else hashes its best entity key (eventKey, else rehearsalId) with its type.
  int get notificationId {
    if (type == PushType.departure) return departureNotificationId(eventKey);
    final entity = eventKey.isNotEmpty ? eventKey : (rehearsalId ?? '');
    return Object.hash(entity, type).toUnsigned(31);
  }
```

- [ ] **Step 4: Implement `push_service.dart` changes**

In `lib/features/notifications/services/push_service.dart`:

1. Add the channel constant next to `_channel`:

```dart
  static const _bandUpdatesChannel = AndroidNotificationChannel(
    'band_updates',
    'Band Updates',
    description: 'Changes to your band\'s schedule and activity',
    importance: Importance.high,
  );
```

2. In `init()`, create it alongside the existing one:

```dart
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_bandUpdatesChannel);
```

3. In `_show`, replace the title/body/channel resolution (the block from `final title = ...` through the `NotificationDetails`) with type-aware rendering:

```dart
    final isReminder =
        payload.type == PushType.reminder8h || payload.type == PushType.departure;
    final title = payload.title ??
        (isReminder ? 'Event today' : 'TTS Bandmate');
    final body = isReminder
        ? renderBody(payload)
        : (payload.body ?? renderBody(payload));
    final android = isReminder
        ? const AndroidNotificationDetails(
            'event_reminders',
            'Event Reminders',
            importance: Importance.high,
            priority: Priority.high,
          )
        : const AndroidNotificationDetails(
            'band_updates',
            'Band Updates',
            importance: Importance.high,
            priority: Priority.high,
          );
    await _local.show(
      payload.notificationId,
      title,
      body,
      NotificationDetails(
        android: android,
        iOS: const DarwinNotificationDetails(),
      ),
    );
```

(The `import '../data/push_payload.dart';` at the top already exposes `PushType`.)

- [ ] **Step 5: Run tests**

Run: `flutter test test/notifications/`
Expected: PASS (new + all pre-existing notification tests, including `render_body_test.dart`).

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/notifications/data/push_payload.dart lib/features/notifications/services/push_service.dart test/notifications/push_payload_test.dart && git commit -m "feat(push): rehearsal push types, generic title/body fallback, band_updates channel"
```

---

### Task 10: Tap-to-open deep-linking for rehearsal pushes

**Files:**
- Modify: `lib/features/notifications/services/push_service.dart`, `lib/features/notifications/providers/notifications_provider.dart`
- Create: `lib/features/notifications/data/push_route.dart`
- Test: `test/notifications/push_route_test.dart` (create)

**Interfaces:**
- Consumes: FCM `onMessageOpenedApp` stream + `getInitialMessage()` (fire when the user taps an OS-rendered hybrid notification from background/terminated), `routerProvider` (`lib/core/config/router.dart`).
- Produces: `routeForPushData(Map<String, dynamic> data) → String?` (pure, unit-testable — pattern: `inviteRouteForUri` in `lib/core/deeplink/deep_link_service.dart`); `PushService.listenTaps(void Function(String route) onRoute)` (idempotent like `listenForeground`); wired in `PushRegistrar.registerCurrentToken` next to `listenForeground()`.

- [ ] **Step 1: Write the failing test**

`test/notifications/push_route_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/push_route.dart';

void main() {
  test('rehearsal_cancelled routes to the rehearsal detail', () {
    expect(
      routeForPushData({'type': 'rehearsal_cancelled', 'rehearsalId': '42'}),
      '/rehearsals/42',
    );
  });

  test('rehearsal_restored routes to the rehearsal detail', () {
    expect(
      routeForPushData({'type': 'rehearsal_restored', 'rehearsalId': '7'}),
      '/rehearsals/7',
    );
  });

  test('missing or non-numeric rehearsalId does not route', () {
    expect(routeForPushData({'type': 'rehearsal_cancelled'}), isNull);
    expect(routeForPushData({'type': 'rehearsal_cancelled', 'rehearsalId': 'abc'}), isNull);
  });

  test('unknown types do not route', () {
    expect(routeForPushData({'type': 'event_reminder_8h', 'eventKey': 'k'}), isNull);
    expect(routeForPushData({}), isNull);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/notifications/push_route_test.dart`
Expected: FAIL — file/function missing.

- [ ] **Step 3: Implement the pure mapper**

`lib/features/notifications/data/push_route.dart`:

```dart
/// Pure mapper: turn a push notification's data map into the in-app route to
/// open when the user taps it, or null if the type has no destination.
/// Kept free of platform channels so it is unit-testable (see
/// `inviteRouteForUri` in core/deeplink for the same pattern).
String? routeForPushData(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  if (type != 'rehearsal_cancelled' && type != 'rehearsal_restored') {
    return null;
  }
  final rehearsalId = int.tryParse(data['rehearsalId']?.toString() ?? '');
  if (rehearsalId == null) return null;
  return '/rehearsals/$rehearsalId';
}
```

- [ ] **Step 4: Add `listenTaps` to PushService and wire it**

In `lib/features/notifications/services/push_service.dart`, add import `../data/push_route.dart`; add below `listenForeground()`:

```dart
  bool _tapsListening = false;

  /// Wire tap-to-open for OS-rendered (hybrid) pushes: background taps arrive
  /// via onMessageOpenedApp, terminated-state taps via getInitialMessage.
  /// Idempotent like [listenForeground].
  void listenTaps(void Function(String route) onRoute) {
    if (!_pushSupported || _tapsListening) return;
    _tapsListening = true;

    void handle(RemoteMessage message) {
      final route = routeForPushData(message.data);
      if (route != null) onRoute(route);
    }

    FirebaseMessaging.onMessageOpenedApp.listen(handle);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) handle(message);
    });
  }
```

In `lib/features/notifications/providers/notifications_provider.dart`, inside `PushRegistrar.registerCurrentToken()` directly after `push.listenForeground();`, add:

```dart
    push.listenTaps((route) => _ref.read(routerProvider).go(route));
```

and add the import:

```dart
import '../../../core/config/router.dart';
```

- [ ] **Step 5: Run tests + analyzer**

Run: `flutter test test/notifications/ && flutter analyze`
Expected: tests PASS; analyze reports no new issues.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate && git add lib/features/notifications/data/push_route.dart lib/features/notifications/services/push_service.dart lib/features/notifications/providers/notifications_provider.dart test/notifications/push_route_test.dart && git commit -m "feat(push): tap-to-open deep-linking for rehearsal pushes"
```

---

### Task 11: Full-suite verification (both repos)

**Files:** none (verification only)

- [ ] **Step 1: Mobile full test suite + analyzer**

Run: `cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test`
Expected: analyze clean (no NEW issues vs `main`); all tests pass.

- [ ] **Step 2: Backend full test suite**

Run: `cd /home/eddie/github/TTS && docker compose exec app php artisan test`
Expected: PASS. Known flakes (memory): `band_roles` under `--parallel` and `bands.site_name` — re-run those filters sequentially before concluding breakage.

- [ ] **Step 3: Route sanity check**

Run: `docker compose exec app php artisan route:list --path=api/mobile/rehearsals`
Expected output includes: `PATCH api/mobile/rehearsals/{rehearsal}/cancelled … mobile.rehearsals.set-cancelled`.

- [ ] **Step 4: Commit any stragglers**

```bash
cd /home/eddie/github/tts_bandmate && git status --short && cd /home/eddie/github/TTS && git status --short
```

Expected: both clean. If not, review and commit with an appropriate message.

---

## Post-plan (not tasks — handled by the finishing skill)

- Backend PR → `staging` (auto-deploys staging on merge). Mobile PR → `main`.
- Wait for Copilot's PR review on both and address comments before calling either done.
- On-device verification via the run-on-device skill: cancel an occurrence of a recurring rehearsal on the phone, verify the strikethrough in the list + dashboard, verify a second logged-in user receives the in-app notification (and push, if a second device is available).
- release-please cuts mobile 1.10.0 from these `feat:` commits.
