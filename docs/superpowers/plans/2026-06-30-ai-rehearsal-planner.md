# AI Rehearsal Planner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a multi-turn, AI-powered rehearsal planner: the band leader opens a chat, the AI assesses upcoming events + recently-rehearsed songs + roster/instruments + the song library, then proposes what to rehearse (or suggests repertoire when nothing is pending), streaming its replies in real time.

**Architecture:** Backend-driven, reusing the existing Laravel AI integration (Anthropic, the `SetlistAgent`/`SetlistAiService` pattern) and Pusher streaming. A new `RehearsalPlannerService` gathers context from existing models, persists a session + messages, and streams the agent's reply over a private Pusher channel. The Flutter app renders a Cupertino chat that subscribes to that channel.

**Tech Stack:** Laravel 11 + `laravel/ai ^0.5.1` (Anthropic) + Pusher broadcasting (backend); Flutter + Riverpod v3 + Dio + `pusher_channels_flutter ^2.6.0` + `go_router` (mobile).

**Repos:**
- Backend: `/home/eddie/github/TTS` (Laravel). Run PHP via `docker compose exec app …` (never on host).
- Mobile: `/home/eddie/github/tts_bandmate` (Flutter). Branch `feat/ai-rehearsal-planner`.

## Global Constraints

- Models: hand-written `fromJson()` only — no json_serializable/freezed codegen (mobile).
- Dark-mode-safe colors: use `context.primaryText` / `secondaryText` / `tertiaryText` / `placeholderText` (from `lib/core/theme/context_colors.dart`), never raw `CupertinoColors.label`/`secondaryLabel` in a `color:`.
- Riverpod v3: chat state uses `NotifierProvider.family<Notifier, State, int>` keyed by bandId; repos are plain `Provider`.
- Agent model tier: `claude-sonnet-4-6` (cheaper/faster tier, per design decision).
- Context windows: **next 5 upcoming events**, **last 5 past rehearsals**.
- AI key guard: `config('services.anthropic.key')` missing → HTTP 503 `{ "error": "Anthropic API key not configured." }`.
- Empty song library is NOT an error — the planner still runs (leans on events + new-repertoire ideas).
- Backend tests run via `docker compose exec app php artisan test`. Mobile tests via `flutter test`.
- Streaming events on the wire (from `laravel/ai`): `text_delta` (`{type, delta, message_id, ...}`) and `stream_end` (`{type, reason, usage, ...}`).
- Pusher private channel name: `private-rehearsal-planner.{sessionId}`; authorize in `routes/channels.php` mirroring the existing `setlist.{sessionId}` rule with `canRead('rehearsals', $session->band_id)`.
- TTS PRs target `staging`; mobile PRs target `main`.

---

## Part A — Backend (Laravel, repo `/home/eddie/github/TTS`)

### Task A1: Migrations + models for planner sessions & messages

**Files:**
- Create: `database/migrations/2026_06_30_000001_create_rehearsal_planner_sessions_table.php`
- Create: `database/migrations/2026_06_30_000002_create_rehearsal_planner_messages_table.php`
- Create: `app/Models/RehearsalPlannerSession.php`
- Create: `app/Models/RehearsalPlannerMessage.php`
- Create: `database/factories/RehearsalPlannerSessionFactory.php`
- Create: `database/factories/RehearsalPlannerMessageFactory.php`
- Test: `tests/Feature/RehearsalPlanner/PlannerModelsTest.php`

**Interfaces:**
- Produces:
  - `RehearsalPlannerSession` with `$fillable = ['band_id','user_id','title']`, relations `band()`, `user()`, `messages()` (hasMany ordered by id).
  - `RehearsalPlannerMessage` with `$fillable = ['session_id','role','content','payload','status']`, `$casts = ['payload' => 'array']`, relation `session()`. `role` ∈ {`user`,`assistant`}; `status` ∈ {`streaming`,`complete`,`failed`}.

- [ ] **Step 1: Write the sessions migration**

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('rehearsal_planner_sessions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('band_id')->constrained()->onDelete('cascade');
            $table->foreignId('user_id')->constrained()->onDelete('cascade');
            $table->string('title')->nullable();
            $table->timestamps();
            $table->index('band_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('rehearsal_planner_sessions');
    }
};
```

- [ ] **Step 2: Write the messages migration**

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('rehearsal_planner_messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('session_id')
                ->constrained('rehearsal_planner_sessions')
                ->onDelete('cascade');
            $table->string('role', 16);            // 'user' | 'assistant'
            $table->longText('content')->nullable();
            $table->json('payload')->nullable();   // suggestions / plan
            $table->string('status', 16)->default('complete'); // streaming|complete|failed
            $table->timestamps();
            $table->index('session_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('rehearsal_planner_messages');
    }
};
```

- [ ] **Step 3: Write the models**

`app/Models/RehearsalPlannerSession.php`:
```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class RehearsalPlannerSession extends Model
{
    use HasFactory;

    protected $fillable = ['band_id', 'user_id', 'title'];

    public function band(): BelongsTo
    {
        return $this->belongsTo(Bands::class, 'band_id');
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function messages(): HasMany
    {
        return $this->hasMany(RehearsalPlannerMessage::class, 'session_id')->orderBy('id');
    }
}
```

`app/Models/RehearsalPlannerMessage.php`:
```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class RehearsalPlannerMessage extends Model
{
    use HasFactory;

    protected $fillable = ['session_id', 'role', 'content', 'payload', 'status'];

    protected $casts = ['payload' => 'array'];

    public function session(): BelongsTo
    {
        return $this->belongsTo(RehearsalPlannerSession::class, 'session_id');
    }
}
```

- [ ] **Step 4: Write the factories**

`database/factories/RehearsalPlannerSessionFactory.php`:
```php
<?php

namespace Database\Factories;

use App\Models\Bands;
use App\Models\RehearsalPlannerSession;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

class RehearsalPlannerSessionFactory extends Factory
{
    protected $model = RehearsalPlannerSession::class;

    public function definition(): array
    {
        return [
            'band_id' => Bands::factory(),
            'user_id' => User::factory(),
            'title'   => null,
        ];
    }
}
```

`database/factories/RehearsalPlannerMessageFactory.php`:
```php
<?php

namespace Database\Factories;

use App\Models\RehearsalPlannerMessage;
use App\Models\RehearsalPlannerSession;
use Illuminate\Database\Eloquent\Factories\Factory;

class RehearsalPlannerMessageFactory extends Factory
{
    protected $model = RehearsalPlannerMessage::class;

    public function definition(): array
    {
        return [
            'session_id' => RehearsalPlannerSession::factory(),
            'role'       => 'assistant',
            'content'    => $this->faker->sentence(),
            'payload'    => null,
            'status'     => 'complete',
        ];
    }
}
```

- [ ] **Step 5: Write the failing test**

`tests/Feature/RehearsalPlanner/PlannerModelsTest.php`:
```php
<?php

namespace Tests\Feature\RehearsalPlanner;

use App\Models\RehearsalPlannerMessage;
use App\Models\RehearsalPlannerSession;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PlannerModelsTest extends TestCase
{
    use RefreshDatabase;

    public function test_session_has_ordered_messages_and_payload_casts_to_array(): void
    {
        $session = RehearsalPlannerSession::factory()->create();

        RehearsalPlannerMessage::factory()->create([
            'session_id' => $session->id,
            'role'       => 'user',
            'content'    => 'Plan next week',
            'status'     => 'complete',
        ]);
        RehearsalPlannerMessage::factory()->create([
            'session_id' => $session->id,
            'role'       => 'assistant',
            'content'    => 'Here is a plan',
            'payload'    => ['suggestions' => ['A', 'B'], 'plan' => null],
            'status'     => 'complete',
        ]);

        $session->refresh()->load('messages');

        $this->assertCount(2, $session->messages);
        $this->assertSame('user', $session->messages->first()->role);
        $this->assertIsArray($session->messages->last()->payload);
        $this->assertSame(['A', 'B'], $session->messages->last()->payload['suggestions']);
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=PlannerModelsTest`
Expected: FAIL (tables/models don't exist yet) — then after migrate, PASS.

- [ ] **Step 7: Migrate & run to pass**

Run: `docker compose exec app php artisan migrate && docker compose exec app php artisan test --filter=PlannerModelsTest`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add database/migrations/2026_06_30_00000*_*.php app/Models/RehearsalPlanner*.php database/factories/RehearsalPlanner*Factory.php tests/Feature/RehearsalPlanner/PlannerModelsTest.php
git commit -m "feat(rehearsal-planner): sessions + messages schema and models"
```

---

### Task A2: Context builder service

Builds the plain-text context block the agent is prompted with. Pure (no AI calls) so it's unit-testable.

**Files:**
- Create: `app/Services/RehearsalPlannerContextBuilder.php`
- Test: `tests/Feature/RehearsalPlanner/ContextBuilderTest.php`

**Interfaces:**
- Consumes: models from Task A1 + existing `Bands`, `Rehearsal`, `Bookings`, `Events`, `EventSetlist`, `SetlistSong`, `Song`, `RosterMember`, `BandRole`.
- Produces: `RehearsalPlannerContextBuilder::build(Bands $band): array` returning
  `['text' => string, 'has_upcoming_requests' => bool, 'song_count' => int]`.
  `text` contains four labeled sections: UPCOMING EVENTS, RECENTLY REHEARSED, PERSONNEL & INSTRUMENTS, SONG LIBRARY.

- [ ] **Step 1: Write the service**

```php
<?php

namespace App\Services;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\Events;
use App\Models\Rehearsal;
use Carbon\Carbon;
use Illuminate\Support\Collection;

class RehearsalPlannerContextBuilder
{
    private const UPCOMING_LIMIT = 5;
    private const PAST_REHEARSAL_LIMIT = 5;

    /** @return array{text: string, has_upcoming_requests: bool, song_count: int} */
    public function build(Bands $band): array
    {
        [$upcomingText, $hasRequests] = $this->upcomingEvents($band);
        $rehearsedText = $this->recentlyRehearsed($band);
        $personnelText = $this->personnel($band);
        [$libraryText, $songCount] = $this->songLibrary($band);

        $text = implode("\n\n", [
            "UPCOMING EVENTS (next " . self::UPCOMING_LIMIT . "):\n" . $upcomingText,
            "RECENTLY REHEARSED (from last " . self::PAST_REHEARSAL_LIMIT . " rehearsals' bookings):\n" . $rehearsedText,
            "PERSONNEL & INSTRUMENTS:\n" . $personnelText,
            "SONG LIBRARY (active):\n" . $libraryText,
        ]);

        return [
            'text' => $text,
            'has_upcoming_requests' => $hasRequests,
            'song_count' => $songCount,
        ];
    }

    /** @return array{0: string, 1: bool} */
    private function upcomingEvents(Bands $band): array
    {
        $today = Carbon::today()->toDateString();

        $events = Events::query()
            ->where('eventable_type', Bookings::class)
            ->whereHasMorph('eventable', [Bookings::class], fn ($q) => $q->where('band_id', $band->id))
            ->whereDate('date', '>=', $today)
            ->with(['setlist.songs.song'])
            ->orderBy('date')
            ->limit(self::UPCOMING_LIMIT)
            ->get();

        if ($events->isEmpty()) {
            return ['(none scheduled)', false];
        }

        $hasRequests = false;
        $lines = $events->map(function (Events $e) use (&$hasRequests) {
            $songs = $e->setlist?->songs
                ?->map(fn ($s) => $s->song?->title)
                ->filter()
                ->values() ?? collect();
            if ($songs->isNotEmpty()) {
                $hasRequests = true;
            }
            $songList = $songs->isEmpty() ? 'no setlist yet' : $songs->implode(', ');
            $date = is_string($e->date) ? $e->date : optional($e->date)->format('Y-m-d');
            return "- {$e->title} ({$date}) — {$songList}";
        })->implode("\n");

        return [$lines, $hasRequests];
    }

    private function recentlyRehearsed(Bands $band): string
    {
        $rehearsals = Rehearsal::query()
            ->where('band_id', $band->id)
            ->whereDate('date', '<', Carbon::today()->toDateString())
            ->with(['bookings.events.setlist.songs.song'])
            ->orderByDesc('date')
            ->limit(self::PAST_REHEARSAL_LIMIT)
            ->get();

        $titles = collect();
        foreach ($rehearsals as $rehearsal) {
            foreach ($rehearsal->bookings as $booking) {
                foreach ($booking->events as $event) {
                    $songs = $event->setlist?->songs ?? collect();
                    foreach ($songs as $setlistSong) {
                        if ($setlistSong->song?->title) {
                            $titles->push($setlistSong->song->title);
                        }
                    }
                }
            }
        }

        $unique = $titles->unique()->values();
        return $unique->isEmpty() ? '(no song data from recent rehearsals)' : $unique->implode(', ');
    }

    private function personnel(Bands $band): string
    {
        $members = $this->rosterMembers($band);
        if ($members->isEmpty()) {
            return '(no roster members)';
        }
        return $members->map(function ($m) {
            $role = $m->bandRole?->name ?? 'Unassigned';
            $name = $m->display_name ?? ($m->name ?? 'Unknown');
            return "- {$name}: {$role}";
        })->implode("\n");
    }

    /** @return Collection */
    private function rosterMembers(Bands $band): Collection
    {
        // Bands -> rosters -> members (with bandRole). Flatten + de-dupe by id.
        return $band->rosters()
            ->with('members.bandRole')
            ->get()
            ->flatMap(fn ($roster) => $roster->members)
            ->unique('id')
            ->values();
    }

    /** @return array{0: string, 1: int} */
    private function songLibrary(Bands $band): array
    {
        $songs = $band->songs()->where('active', true)->with('leadSinger')->get();
        if ($songs->isEmpty()) {
            return ['(empty library)', 0];
        }
        $lines = $songs->map(function ($s) {
            $parts = array_filter([
                $s->title,
                $s->artist ? "by {$s->artist}" : null,
                $s->genre,
                $s->song_key ? "key {$s->song_key}" : null,
                $s->bpm ? "{$s->bpm}bpm" : null,
                $s->leadSinger?->display_name ? "lead {$s->leadSinger->display_name}" : null,
            ]);
            return "- [{$s->id}] " . implode(' · ', $parts);
        })->implode("\n");
        return [$lines, $songs->count()];
    }
}
```

> NOTE for implementer: confirm the `Bands::rosters()` relation name and `RosterMember::display_name` accessor via the recon (Bands has `rosters()`; RosterMember has `getDisplayNameAttribute`). If `rosters()` differs, adjust `rosterMembers()` only.

- [ ] **Step 2: Write the failing test**

`tests/Feature/RehearsalPlanner/ContextBuilderTest.php`:
```php
<?php

namespace Tests\Feature\RehearsalPlanner;

use App\Models\Bands;
use App\Models\Song;
use App\Services\RehearsalPlannerContextBuilder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ContextBuilderTest extends TestCase
{
    use RefreshDatabase;

    public function test_build_includes_four_sections_and_song_count(): void
    {
        $band = Bands::factory()->create();
        Song::factory()->count(2)->create(['band_id' => $band->id, 'active' => true]);
        Song::factory()->create(['band_id' => $band->id, 'active' => false]); // excluded

        $result = app(RehearsalPlannerContextBuilder::class)->build($band->fresh());

        $this->assertStringContainsString('UPCOMING EVENTS', $result['text']);
        $this->assertStringContainsString('RECENTLY REHEARSED', $result['text']);
        $this->assertStringContainsString('PERSONNEL & INSTRUMENTS', $result['text']);
        $this->assertStringContainsString('SONG LIBRARY', $result['text']);
        $this->assertSame(2, $result['song_count']);          // only active songs
        $this->assertFalse($result['has_upcoming_requests']); // no events with setlists
    }

    public function test_empty_band_does_not_throw(): void
    {
        $band = Bands::factory()->create();
        $result = app(RehearsalPlannerContextBuilder::class)->build($band);
        $this->assertSame(0, $result['song_count']);
        $this->assertStringContainsString('(empty library)', $result['text']);
    }
}
```

- [ ] **Step 3: Run test to verify it fails, then passes**

Run: `docker compose exec app php artisan test --filter=ContextBuilderTest`
Expected: FAIL (service missing) → after Step 1 in place, PASS. If a relation name is wrong, fix `rosterMembers()`/`songLibrary()` until green. Confirm a `SongFactory` exists; if not, create a minimal one mirroring `database/factories` style.

- [ ] **Step 4: Commit**

```bash
git add app/Services/RehearsalPlannerContextBuilder.php tests/Feature/RehearsalPlanner/ContextBuilderTest.php
git commit -m "feat(rehearsal-planner): context builder for AI prompt"
```

---

### Task A3: Agent + stream-broadcast event class

**Files:**
- Create: `app/Ai/Agents/RehearsalPlannerAgent.php`
- Create: `app/Events/RehearsalPlannerStreamEvent.php`
- Test: `tests/Feature/RehearsalPlanner/StreamEventTest.php`

**Interfaces:**
- Produces:
  - `RehearsalPlannerAgent` (mirrors `SetlistAgent`): `#[Provider(Lab::Anthropic)] #[Model('claude-sonnet-4-6')]`, implements `Agent, Conversational`, uses `Promptable`, has `withHistory(array $messages): static` and `instructions()`.
  - `RehearsalPlannerStreamEvent implements ShouldBroadcastNow` with constructor `(int $sessionId, string $type, array $data)`, `broadcastOn()` → `PrivateChannel("rehearsal-planner.{$sessionId}")`, `broadcastAs()` → `'planner.stream'`, `broadcastWith()` → `['type' => $type, ...$data]`. `type` ∈ {`text_delta`,`done`,`error`}.

- [ ] **Step 1: Write the agent** (mirror `app/Ai/Agents/SetlistAgent.php`)

```php
<?php

namespace App\Ai\Agents;

use Laravel\Ai\Attributes\Model;
use Laravel\Ai\Attributes\Provider;
use Laravel\Ai\Contracts\Agent;
use Laravel\Ai\Contracts\Conversational;
use Laravel\Ai\Enums\Lab;
use Laravel\Ai\Messages\Message;
use Laravel\Ai\Promptable;

#[Provider(Lab::Anthropic)]
#[Model('claude-sonnet-4-6')]
class RehearsalPlannerAgent implements Agent, Conversational
{
    use Promptable;

    /** @var Message[] */
    private array $priorMessages = [];

    public function withHistory(array $messages): static
    {
        $clone = clone $this;
        $clone->priorMessages = $messages;
        return $clone;
    }

    public function instructions(): string
    {
        return <<<'TXT'
You are a professional band rehearsal planner. Help the band leader decide what to
rehearse, using the supplied context (upcoming events and their requested songs,
recently rehearsed songs, the roster and their instruments, and the song library).

Behaviour:
- If upcoming events have requested/setlist songs, focus there. Call out songs on
  upcoming setlists that do NOT appear in recently rehearsed.
- If nothing is pending, suggest material in TWO clearly separated groups:
  "Revisit from your library" (existing songs, reference them by their [id]) and
  "New repertoire ideas" (real songs NOT in the library that fit the roster/genre).
- Be concise. End each reply by offering a couple of concrete next steps or an open
  question.
- Stay strictly on rehearsal/repertoire planning; politely decline unrelated requests.

When the user asks for a concrete plan, finish your reply with a fenced block:
```plan
{"title":"...","items":[{"song_id":123,"title":"...","reason":"..."},{"song_id":null,"title":"...","reason":"..."}]}
```
Use song_id from the library where applicable; null for new-repertoire ideas.
Also, when helpful, finish with a suggestions block of up to 3 quick replies:
```suggestions
["Draft a plan for the wedding","Explore new material"]
```
TXT;
    }

    public function messages(): iterable
    {
        return $this->priorMessages;
    }
}
```

- [ ] **Step 2: Write the broadcast event**

```php
<?php

namespace App\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class RehearsalPlannerStreamEvent implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    /** @param array<string,mixed> $data */
    public function __construct(
        public int $sessionId,
        public string $type,   // 'text_delta' | 'done' | 'error'
        public array $data = [],
    ) {}

    public function broadcastOn(): array
    {
        return [new PrivateChannel('rehearsal-planner.' . $this->sessionId)];
    }

    public function broadcastAs(): string
    {
        return 'planner.stream';
    }

    public function broadcastWith(): array
    {
        return array_merge(['type' => $this->type], $this->data);
    }
}
```

- [ ] **Step 3: Write the failing test** (no AI call — just the broadcast contract)

`tests/Feature/RehearsalPlanner/StreamEventTest.php`:
```php
<?php

namespace Tests\Feature\RehearsalPlanner;

use App\Events\RehearsalPlannerStreamEvent;
use Tests\TestCase;

class StreamEventTest extends TestCase
{
    public function test_broadcast_shape(): void
    {
        $event = new RehearsalPlannerStreamEvent(7, 'text_delta', ['delta' => 'Hi']);

        $this->assertSame('planner.stream', $event->broadcastAs());
        $this->assertSame('private-rehearsal-planner.7', $event->broadcastOn()[0]->name);
        $this->assertSame(['type' => 'text_delta', 'delta' => 'Hi'], $event->broadcastWith());
    }
}
```

- [ ] **Step 4: Run test**

Run: `docker compose exec app php artisan test --filter=StreamEventTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/Ai/Agents/RehearsalPlannerAgent.php app/Events/RehearsalPlannerStreamEvent.php tests/Feature/RehearsalPlanner/StreamEventTest.php
git commit -m "feat(rehearsal-planner): agent + stream broadcast event"
```

---

### Task A4: Planner service (orchestrates context + agent + streaming + persistence)

**Files:**
- Create: `app/Services/RehearsalPlannerService.php`
- Test: `tests/Feature/RehearsalPlanner/PlannerServiceTest.php`

**Interfaces:**
- Consumes: `RehearsalPlannerContextBuilder` (A2), `RehearsalPlannerAgent` (A3), `RehearsalPlannerStreamEvent` (A3), models (A1).
- Produces:
  - `runTurn(RehearsalPlannerSession $session, RehearsalPlannerMessage $assistantMessage, ?string $userText): void`
    — builds context (system preamble injected as the first turn's content), assembles history from prior `complete` messages, streams the agent via `->stream()`, dispatches a `text_delta` `RehearsalPlannerStreamEvent` per chunk, and on completion parses any ```plan```/```suggestions``` fenced blocks, persists `content` + `payload` + `status='complete'` on `$assistantMessage`, then dispatches a `done` event carrying the final payload. On exception: sets `status='failed'` and dispatches an `error` event.
  - Static helpers `parsePlan(string $text): ?array` and `parseSuggestions(string $text): array` (also strip the fenced blocks from the user-visible `content`).

- [ ] **Step 1: Write the service**

```php
<?php

namespace App\Services;

use App\Ai\Agents\RehearsalPlannerAgent;
use App\Events\RehearsalPlannerStreamEvent;
use App\Models\RehearsalPlannerMessage;
use App\Models\RehearsalPlannerSession;
use Illuminate\Support\Facades\Log;
use Laravel\Ai\Messages\Message;

class RehearsalPlannerService
{
    public function __construct(
        private RehearsalPlannerContextBuilder $contextBuilder,
    ) {}

    public function runTurn(
        RehearsalPlannerSession $session,
        RehearsalPlannerMessage $assistantMessage,
        ?string $userText,
    ): void {
        try {
            $session->loadMissing('band');
            $context = $this->contextBuilder->build($session->band);

            $history = $this->buildHistory($session, $assistantMessage->id);

            // The opening turn has no userText; prompt the agent to assess the context.
            $prompt = $userText !== null && $userText !== ''
                ? $userText
                : 'Assess what the band should rehearse and open the conversation.';

            // Prepend the context as a system-style preamble on the first user turn.
            $promptWithContext = "BAND CONTEXT:\n{$context['text']}\n\n---\n{$prompt}";

            $agent = (new RehearsalPlannerAgent())->withHistory($history);

            $full = '';
            $stream = $agent->stream($promptWithContext, timeout: 120);
            foreach ($stream as $event) {
                $arr = method_exists($event, 'toArray') ? $event->toArray() : (array) $event;
                if (($arr['type'] ?? null) === 'text_delta' && isset($arr['delta'])) {
                    $full .= $arr['delta'];
                    RehearsalPlannerStreamEvent::dispatch($session->id, 'text_delta', ['delta' => $arr['delta']]);
                }
            }

            $plan        = self::parsePlan($full);
            $suggestions = self::parseSuggestions($full);
            $visible     = self::stripBlocks($full);

            $assistantMessage->update([
                'content' => $visible,
                'payload' => ['suggestions' => $suggestions, 'plan' => $plan],
                'status'  => 'complete',
            ]);

            RehearsalPlannerStreamEvent::dispatch($session->id, 'done', [
                'message_id'  => $assistantMessage->id,
                'content'     => $visible,
                'suggestions' => $suggestions,
                'plan'        => $plan,
            ]);
        } catch (\Throwable $e) {
            Log::error('RehearsalPlannerService failed', ['error' => $e->getMessage()]);
            $assistantMessage->update(['status' => 'failed']);
            RehearsalPlannerStreamEvent::dispatch($session->id, 'error', [
                'message_id' => $assistantMessage->id,
                'error'      => 'The planner failed to respond. Please retry.',
            ]);
        }
    }

    /** @return Message[] */
    private function buildHistory(RehearsalPlannerSession $session, int $excludeMessageId): array
    {
        return $session->messages()
            ->where('id', '<', $excludeMessageId)
            ->where('status', 'complete')
            ->get()
            ->map(fn (RehearsalPlannerMessage $m) => new Message($m->role, (string) $m->content))
            ->all();
    }

    public static function parsePlan(string $text): ?array
    {
        if (!preg_match('/```plan\s*(\{.*?\})\s*```/s', $text, $m)) {
            return null;
        }
        $decoded = json_decode($m[1], true);
        return is_array($decoded) ? $decoded : null;
    }

    /** @return array<int,string> */
    public static function parseSuggestions(string $text): array
    {
        if (!preg_match('/```suggestions\s*(\[.*?\])\s*```/s', $text, $m)) {
            return [];
        }
        $decoded = json_decode($m[1], true);
        return is_array($decoded) ? array_values(array_filter($decoded, 'is_string')) : [];
    }

    public static function stripBlocks(string $text): string
    {
        $text = preg_replace('/```plan\s*\{.*?\}\s*```/s', '', $text);
        $text = preg_replace('/```suggestions\s*\[.*?\]\s*```/s', '', $text);
        return trim($text);
    }
}
```

- [ ] **Step 2: Write the failing test** (parsing helpers are pure — no AI needed)

`tests/Feature/RehearsalPlanner/PlannerServiceTest.php`:
```php
<?php

namespace Tests\Feature\RehearsalPlanner;

use App\Services\RehearsalPlannerService;
use Tests\TestCase;

class PlannerServiceTest extends TestCase
{
    public function test_parse_plan_and_suggestions_and_strip(): void
    {
        $text = "Here is my plan.\n".
            "```plan\n{\"title\":\"T\",\"items\":[{\"song_id\":1,\"title\":\"A\",\"reason\":\"r\"}]}\n```\n".
            "```suggestions\n[\"One\",\"Two\"]\n```";

        $plan = RehearsalPlannerService::parsePlan($text);
        $this->assertSame('T', $plan['title']);
        $this->assertSame(1, $plan['items'][0]['song_id']);

        $this->assertSame(['One', 'Two'], RehearsalPlannerService::parseSuggestions($text));

        $stripped = RehearsalPlannerService::stripBlocks($text);
        $this->assertStringNotContainsString('```plan', $stripped);
        $this->assertStringNotContainsString('```suggestions', $stripped);
        $this->assertStringContainsString('Here is my plan.', $stripped);
    }

    public function test_no_blocks_returns_null_and_empty(): void
    {
        $text = 'Just a normal reply.';
        $this->assertNull(RehearsalPlannerService::parsePlan($text));
        $this->assertSame([], RehearsalPlannerService::parseSuggestions($text));
        $this->assertSame('Just a normal reply.', RehearsalPlannerService::stripBlocks($text));
    }
}
```

- [ ] **Step 3: Run test**

Run: `docker compose exec app php artisan test --filter=PlannerServiceTest`
Expected: PASS.

> NOTE for implementer: the streaming loop reads `text_delta` events per the recon (`laravel/ai` `TextDelta::toArray()` → `['type' => 'text_delta', 'delta' => ...]`). If the installed version's iterator yields typed objects without `toArray()`, adapt the `foreach` to read `$event->delta` / `$event->type` (check `vendor/laravel/ai/src/Streaming/Events/TextDelta.php`). Keep the dispatched payload shape identical.

- [ ] **Step 4: Commit**

```bash
git add app/Services/RehearsalPlannerService.php tests/Feature/RehearsalPlanner/PlannerServiceTest.php
git commit -m "feat(rehearsal-planner): turn orchestration + plan/suggestion parsing"
```

---

### Task A5: Controller, routes, channel auth

**Files:**
- Create: `app/Http/Controllers/Api/Mobile/RehearsalPlannerController.php`
- Modify: `routes/api.php` (add band-scoped planner routes in the `auth:sanctum` group)
- Modify: `routes/channels.php` (authorize `rehearsal-planner.{sessionId}`)
- Test: `tests/Feature/RehearsalPlanner/PlannerControllerTest.php`

**Interfaces:**
- Consumes: `RehearsalPlannerService` (A4), models (A1).
- Produces three endpoints (band-scoped, `mobile.band:read:rehearsals` middleware):
  - `POST /api/mobile/bands/{band}/rehearsal-planner/sessions` → creates session + placeholder assistant message (`status='streaming'`), runs the opening turn, returns `{ session_id, channel, assistant_message_id }`.
  - `POST /api/mobile/bands/{band}/rehearsal-planner/sessions/{session}/messages` (body `{text}`) → persists user message + placeholder assistant message, runs turn, returns `{ user_message: {...}, assistant_message_id, channel }`.
  - `GET /api/mobile/bands/{band}/rehearsal-planner/sessions/{session}` → `{ session_id, messages: [{id, role, content, payload, status}] }`.

- [ ] **Step 1: Write the controller**

```php
<?php

namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Models\Bands;
use App\Models\RehearsalPlannerSession;
use App\Services\RehearsalPlannerService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class RehearsalPlannerController extends Controller
{
    public function __construct(private RehearsalPlannerService $service) {}

    public function start(Bands $band): JsonResponse
    {
        if ($guard = $this->keyGuard()) {
            return $guard;
        }

        $session = RehearsalPlannerSession::create([
            'band_id' => $band->id,
            'user_id' => Auth::id(),
        ]);

        $assistant = $session->messages()->create([
            'role'   => 'assistant',
            'status' => 'streaming',
        ]);

        $this->service->runTurn($session, $assistant, null);

        return response()->json([
            'session_id'           => $session->id,
            'channel'              => 'private-rehearsal-planner.' . $session->id,
            'assistant_message_id' => $assistant->id,
        ]);
    }

    public function message(Request $request, Bands $band, RehearsalPlannerSession $session): JsonResponse
    {
        abort_unless($session->band_id === $band->id, 404);

        if ($guard = $this->keyGuard()) {
            return $guard;
        }

        $validated = $request->validate(['text' => 'required|string|max:4000']);

        $user = $session->messages()->create([
            'role'    => 'user',
            'content' => $validated['text'],
            'status'  => 'complete',
        ]);

        $assistant = $session->messages()->create([
            'role'   => 'assistant',
            'status' => 'streaming',
        ]);

        $this->service->runTurn($session, $assistant, $validated['text']);

        return response()->json([
            'user_message'         => $this->formatMessage($user),
            'assistant_message_id' => $assistant->id,
            'channel'              => 'private-rehearsal-planner.' . $session->id,
        ]);
    }

    public function show(Bands $band, RehearsalPlannerSession $session): JsonResponse
    {
        abort_unless($session->band_id === $band->id, 404);

        return response()->json([
            'session_id' => $session->id,
            'messages'   => $session->messages()->get()->map(fn ($m) => $this->formatMessage($m))->values(),
        ]);
    }

    private function formatMessage($m): array
    {
        return [
            'id'      => $m->id,
            'role'    => $m->role,
            'content' => $m->content,
            'payload' => $m->payload,
            'status'  => $m->status,
        ];
    }

    private function keyGuard(): ?JsonResponse
    {
        if (!config('services.anthropic.key')) {
            return response()->json(['error' => 'Anthropic API key not configured.'], 503);
        }
        return null;
    }
}
```

- [ ] **Step 2: Add routes** in `routes/api.php` inside the `auth:sanctum` group, near the rehearsals routes:

```php
Route::middleware('mobile.band:read:rehearsals')->scopeBindings()->group(function () {
    Route::post('/bands/{band}/rehearsal-planner/sessions', [RehearsalPlannerController::class, 'start'])
        ->name('mobile.rehearsal-planner.start');
    Route::post('/bands/{band}/rehearsal-planner/sessions/{session}/messages', [RehearsalPlannerController::class, 'message'])
        ->name('mobile.rehearsal-planner.message');
    Route::get('/bands/{band}/rehearsal-planner/sessions/{session}', [RehearsalPlannerController::class, 'show'])
        ->name('mobile.rehearsal-planner.show');
});
```

Add the `use App\Http\Controllers\Api\Mobile\RehearsalPlannerController;` import at the top of `routes/api.php`. The `{session}` binding resolves `RehearsalPlannerSession` by id; `scopeBindings()` keeps it consistent with the band.

- [ ] **Step 3: Authorize the channel** in `routes/channels.php`:

```php
Broadcast::channel('rehearsal-planner.{sessionId}', function ($user, $sessionId) {
    $session = \App\Models\RehearsalPlannerSession::find($sessionId);
    if (!$session) {
        return false;
    }
    return $user->canRead('rehearsals', $session->band_id);
});
```

- [ ] **Step 4: Write the failing test** (fake the service so no AI call happens)

`tests/Feature/RehearsalPlanner/PlannerControllerTest.php`:
```php
<?php

namespace Tests\Feature\RehearsalPlanner;

use App\Models\Bands;
use App\Models\RehearsalPlannerMessage;
use App\Models\RehearsalPlannerSession;
use App\Models\User;
use App\Services\RehearsalPlannerService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Mockery;
use Tests\TestCase;

class PlannerControllerTest extends TestCase
{
    use RefreshDatabase;

    private function actingMember(): array
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        // Give the user read:rehearsals on this band. Mirror how other mobile tests
        // grant band permissions (band membership + role). See existing rehearsal
        // mobile feature tests for the exact helper; replicate it here.
        $this->grantBandRead($user, $band, 'rehearsals');
        Sanctum::actingAs($user);
        config(['services.anthropic.key' => 'test-key']);
        return [$user, $band];
    }

    public function test_start_creates_session_and_placeholder_and_returns_channel(): void
    {
        // Stub the service so runTurn does nothing (no AI).
        $this->mock(RehearsalPlannerService::class, function ($m) {
            $m->shouldReceive('runTurn')->once();
        });

        [$user, $band] = $this->actingMember();

        $res = $this->postJson("/api/mobile/bands/{$band->id}/rehearsal-planner/sessions");

        $res->assertOk()->assertJsonStructure(['session_id', 'channel', 'assistant_message_id']);
        $this->assertSame('private-rehearsal-planner.' . $res->json('session_id'), $res->json('channel'));
        $this->assertDatabaseHas('rehearsal_planner_messages', [
            'id'     => $res->json('assistant_message_id'),
            'role'   => 'assistant',
            'status' => 'streaming',
        ]);
    }

    public function test_message_persists_user_turn(): void
    {
        $this->mock(RehearsalPlannerService::class, fn ($m) => $m->shouldReceive('runTurn')->once());
        [$user, $band] = $this->actingMember();
        $session = RehearsalPlannerSession::factory()->create(['band_id' => $band->id, 'user_id' => $user->id]);

        $res = $this->postJson(
            "/api/mobile/bands/{$band->id}/rehearsal-planner/sessions/{$session->id}/messages",
            ['text' => 'What should we rehearse?']
        );

        $res->assertOk()->assertJsonStructure(['user_message' => ['id', 'role', 'content'], 'assistant_message_id', 'channel']);
        $this->assertDatabaseHas('rehearsal_planner_messages', ['session_id' => $session->id, 'role' => 'user', 'content' => 'What should we rehearse?']);
    }

    public function test_missing_api_key_returns_503(): void
    {
        [$user, $band] = $this->actingMember();
        config(['services.anthropic.key' => null]);

        $this->postJson("/api/mobile/bands/{$band->id}/rehearsal-planner/sessions")
            ->assertStatus(503)
            ->assertJson(['error' => 'Anthropic API key not configured.']);
    }

    public function test_requires_auth(): void
    {
        $band = Bands::factory()->create();
        $this->postJson("/api/mobile/bands/{$band->id}/rehearsal-planner/sessions")->assertUnauthorized();
    }
}
```

> NOTE for implementer: `grantBandRead($user, $band, 'rehearsals')` is a placeholder for whatever the repo's existing mobile rehearsal tests use to give band read permission (band membership + role/ability). Find that pattern in `tests/Feature` (search for `mobile.band:read:rehearsals` test setup) and inline it; do not invent a new permission mechanism.

- [ ] **Step 5: Run test**

Run: `docker compose exec app php artisan test --filter=PlannerControllerTest`
Expected: PASS (after wiring routes/imports). Fix permission-grant helper until green.

- [ ] **Step 6: Commit**

```bash
git add app/Http/Controllers/Api/Mobile/RehearsalPlannerController.php routes/api.php routes/channels.php tests/Feature/RehearsalPlanner/PlannerControllerTest.php
git commit -m "feat(rehearsal-planner): mobile API endpoints + channel auth"
```

---

### Task A6: Backend smoke + open PR to staging

- [ ] **Step 1:** Run the full planner suite + analyzer.

Run: `docker compose exec app php artisan test --filter=RehearsalPlanner`
Expected: all green.

- [ ] **Step 2:** Commit any fixups, push branch, open PR.

```bash
git push -u origin feat/ai-rehearsal-planner
gh pr create --base staging --title "feat(mobile-api): AI rehearsal planner endpoints" --body "Backend for the AI rehearsal planner: sessions/messages schema, context builder, RehearsalPlannerAgent (Anthropic, claude-sonnet-4-6), streamed turns over Pusher (private-rehearsal-planner.{session}), and band-scoped mobile endpoints. Part of the cross-repo AI rehearsal planner feature."
```

- [ ] **Step 3:** Wait for Copilot review; address comments (see memory: Copilot auto-reviews PRs).

---

## Part B — Mobile (Flutter, repo `/home/eddie/github/tts_bandmate`, branch `feat/ai-rehearsal-planner`)

### Task B1: Models

**Files:**
- Create: `lib/features/rehearsal_planner/data/models/planner_message.dart`
- Create: `lib/features/rehearsal_planner/data/models/planner_plan.dart`
- Test: `test/features/rehearsal_planner/models/planner_message_test.dart`

**Interfaces:**
- Produces:
  - `PlannerPlanItem { int? songId; String title; String reason; fromJson }`
  - `PlannerPlan { String title; List<PlannerPlanItem> items; fromJson }`
  - `PlannerMessage { int id; String role; String text; List<String> suggestions; PlannerPlan? plan; String status; fromJson; copyWith }` — `role` ∈ {`user`,`assistant`}; `status` ∈ {`streaming`,`complete`,`failed`}.

- [ ] **Step 1: Write `planner_plan.dart`**

```dart
class PlannerPlanItem {
  const PlannerPlanItem({this.songId, required this.title, required this.reason});

  final int? songId;
  final String title;
  final String reason;

  factory PlannerPlanItem.fromJson(Map<String, dynamic> json) => PlannerPlanItem(
        songId: (json['song_id'] as num?)?.toInt(),
        title: json['title'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
      );
}

class PlannerPlan {
  const PlannerPlan({required this.title, required this.items});

  final String title;
  final List<PlannerPlanItem> items;

  factory PlannerPlan.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw.cast<Map<String, dynamic>>().map(PlannerPlanItem.fromJson).toList()
        : <PlannerPlanItem>[];
    return PlannerPlan(title: json['title'] as String? ?? 'Rehearsal plan', items: items);
  }
}
```

- [ ] **Step 2: Write `planner_message.dart`**

```dart
import 'planner_plan.dart';

class PlannerMessage {
  const PlannerMessage({
    required this.id,
    required this.role,
    required this.text,
    this.suggestions = const [],
    this.plan,
    this.status = 'complete',
  });

  final int id;
  final String role;      // 'user' | 'assistant'
  final String text;
  final List<String> suggestions;
  final PlannerPlan? plan;
  final String status;    // 'streaming' | 'complete' | 'failed'

  bool get isUser => role == 'user';

  factory PlannerMessage.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    final payloadMap = payload is Map<String, dynamic> ? payload : const <String, dynamic>{};

    final rawSuggestions = payloadMap['suggestions'];
    final suggestions = rawSuggestions is List ? rawSuggestions.cast<String>().toList() : <String>[];

    final rawPlan = payloadMap['plan'];
    final plan = rawPlan is Map<String, dynamic> ? PlannerPlan.fromJson(rawPlan) : null;

    return PlannerMessage(
      id: (json['id'] as num).toInt(),
      role: json['role'] as String? ?? 'assistant',
      text: json['content'] as String? ?? '',
      suggestions: suggestions,
      plan: plan,
      status: json['status'] as String? ?? 'complete',
    );
  }

  PlannerMessage copyWith({
    String? text,
    List<String>? suggestions,
    PlannerPlan? plan,
    String? status,
  }) =>
      PlannerMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        suggestions: suggestions ?? this.suggestions,
        plan: plan ?? this.plan,
        status: status ?? this.status,
      );
}
```

- [ ] **Step 3: Write the failing test**

`test/features/rehearsal_planner/models/planner_message_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_message.dart';

void main() {
  test('parses message with payload suggestions and plan', () {
    final msg = PlannerMessage.fromJson({
      'id': 5,
      'role': 'assistant',
      'content': 'Here is a plan',
      'status': 'complete',
      'payload': {
        'suggestions': ['Draft a plan', 'New material'],
        'plan': {
          'title': 'Wedding plan',
          'items': [
            {'song_id': 42, 'title': 'At Last', 'reason': 'On the setlist'},
            {'song_id': null, 'title': 'New Tune', 'reason': 'Fits the horns'},
          ],
        },
      },
    });

    expect(msg.isUser, isFalse);
    expect(msg.text, 'Here is a plan');
    expect(msg.suggestions, ['Draft a plan', 'New material']);
    expect(msg.plan!.title, 'Wedding plan');
    expect(msg.plan!.items.first.songId, 42);
    expect(msg.plan!.items.last.songId, isNull);
  });

  test('parses message with no payload', () {
    final msg = PlannerMessage.fromJson({'id': 1, 'role': 'user', 'content': 'hi', 'status': 'complete'});
    expect(msg.isUser, isTrue);
    expect(msg.suggestions, isEmpty);
    expect(msg.plan, isNull);
  });
}
```

- [ ] **Step 4: Run test**

Run: `flutter test test/features/rehearsal_planner/models/planner_message_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rehearsal_planner/data/models/ test/features/rehearsal_planner/models/
git commit -m "feat(rehearsal-planner): chat message + plan models"
```

---

### Task B2: API endpoints + repository

**Files:**
- Modify: `lib/core/network/api_endpoints.dart` (add three planner paths)
- Create: `lib/features/rehearsal_planner/data/rehearsal_planner_repository.dart`
- Test: `test/features/rehearsal_planner/rehearsal_planner_repository_test.dart`

**Interfaces:**
- Consumes: `apiClientProvider` (exposes `.dio`), `ApiEndpoints`, models (B1).
- Produces:
  - `ApiEndpoints.mobileRehearsalPlannerSessions(int bandId)`, `…Messages(int bandId, int sessionId)`, `…Session(int bandId, int sessionId)`.
  - `RehearsalPlannerRepository` with:
    - `Future<({int sessionId, String channel, int assistantMessageId})> startSession(int bandId)`
    - `Future<({PlannerMessage userMessage, int assistantMessageId, String channel})> sendMessage(int bandId, int sessionId, String text)`
    - `Future<List<PlannerMessage>> history(int bandId, int sessionId)`
  - `rehearsalPlannerRepositoryProvider = Provider<RehearsalPlannerRepository>(...)`.

- [ ] **Step 1: Add endpoints** to `api_endpoints.dart` (match the existing static-method style):

```dart
static String mobileRehearsalPlannerSessions(int bandId) =>
    '/api/mobile/bands/$bandId/rehearsal-planner/sessions';

static String mobileRehearsalPlannerMessages(int bandId, int sessionId) =>
    '/api/mobile/bands/$bandId/rehearsal-planner/sessions/$sessionId/messages';

static String mobileRehearsalPlannerSession(int bandId, int sessionId) =>
    '/api/mobile/bands/$bandId/rehearsal-planner/sessions/$sessionId';
```

- [ ] **Step 2: Write the repository**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/planner_message.dart';

class RehearsalPlannerRepository {
  RehearsalPlannerRepository(this._dio);
  final Dio _dio;

  Future<({int sessionId, String channel, int assistantMessageId})> startSession(int bandId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalPlannerSessions(bandId),
    );
    final data = res.data!;
    return (
      sessionId: (data['session_id'] as num).toInt(),
      channel: data['channel'] as String,
      assistantMessageId: (data['assistant_message_id'] as num).toInt(),
    );
  }

  Future<({PlannerMessage userMessage, int assistantMessageId, String channel})> sendMessage(
    int bandId,
    int sessionId,
    String text,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalPlannerMessages(bandId, sessionId),
      data: {'text': text},
    );
    final data = res.data!;
    return (
      userMessage: PlannerMessage.fromJson(data['user_message'] as Map<String, dynamic>),
      assistantMessageId: (data['assistant_message_id'] as num).toInt(),
      channel: data['channel'] as String,
    );
  }

  Future<List<PlannerMessage>> history(int bandId, int sessionId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileRehearsalPlannerSession(bandId, sessionId),
    );
    final raw = res.data?['messages'];
    return raw is List
        ? raw.cast<Map<String, dynamic>>().map(PlannerMessage.fromJson).toList()
        : <PlannerMessage>[];
  }
}

final rehearsalPlannerRepositoryProvider = Provider<RehearsalPlannerRepository>(
  (ref) => RehearsalPlannerRepository(ref.watch(apiClientProvider).dio),
);
```

> NOTE for implementer: confirm `apiClientProvider` exposes `.dio` (recon says yes). If the project exposes the Dio via a different getter, match it.

- [ ] **Step 3: Write the failing test** (use Dio with a `StubAdapter` like the test harness, or mock with mocktail if that's the repo convention)

`test/features/rehearsal_planner/rehearsal_planner_repository_test.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/rehearsal_planner_repository.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responder);
  final ResponseBody Function(RequestOptions options) responder;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      responder(options);
}

void main() {
  Dio dioReturning(Map<String, dynamic> body) {
    final dio = Dio();
    dio.httpClientAdapter = _StubAdapter((_) => ResponseBody.fromString(
          jsonEncode(body),
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        ));
    return dio;
  }

  test('startSession parses ids and channel', () async {
    final repo = RehearsalPlannerRepository(dioReturning({
      'session_id': 9,
      'channel': 'private-rehearsal-planner.9',
      'assistant_message_id': 21,
    }));
    final r = await repo.startSession(3);
    expect(r.sessionId, 9);
    expect(r.channel, 'private-rehearsal-planner.9');
    expect(r.assistantMessageId, 21);
  });

  test('sendMessage parses user message and channel', () async {
    final repo = RehearsalPlannerRepository(dioReturning({
      'user_message': {'id': 50, 'role': 'user', 'content': 'hi', 'status': 'complete'},
      'assistant_message_id': 51,
      'channel': 'private-rehearsal-planner.9',
    }));
    final r = await repo.sendMessage(3, 9, 'hi');
    expect(r.userMessage.text, 'hi');
    expect(r.assistantMessageId, 51);
  });
}
```

> NOTE: add `import 'dart:convert';` and `import 'dart:typed_data';` to the test. If the repo already has a shared stub adapter in `test/helpers/`, use that instead of redefining `_StubAdapter`.

- [ ] **Step 4: Run test**

Run: `flutter test test/features/rehearsal_planner/rehearsal_planner_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/network/api_endpoints.dart lib/features/rehearsal_planner/data/rehearsal_planner_repository.dart test/features/rehearsal_planner/rehearsal_planner_repository_test.dart
git commit -m "feat(rehearsal-planner): API endpoints + repository"
```

---

### Task B3: Chat state Notifier (Pusher streaming)

**Files:**
- Create: `lib/features/rehearsal_planner/providers/rehearsal_planner_provider.dart`
- Test: `test/features/rehearsal_planner/rehearsal_planner_provider_test.dart`

**Interfaces:**
- Consumes: `rehearsalPlannerRepositoryProvider` (B2), `secureStorageProvider`, `AppConfig`, `PusherChannelsFlutter`, models (B1).
- Produces:
  - `RehearsalPlannerState { List<PlannerMessage> messages; bool isStarting; bool isSending; String? error; int? sessionId; copyWith(...) }`
  - `RehearsalPlannerNotifier extends Notifier<RehearsalPlannerState>` with `start()`, `send(String text)`, `retryLast()`, and internal Pusher delta/done/error handling. Subscribes to the session channel once on `start()`; `ref.onDispose` unsubscribes/disconnects.
  - `rehearsalPlannerProvider = NotifierProvider.family<RehearsalPlannerNotifier, RehearsalPlannerState, int>((bandId) => RehearsalPlannerNotifier(bandId))`.
  - **Testability seam:** the Notifier accepts an optional Pusher-subscription injector so tests can drive deltas without a real Pusher. Define:
    `typedef PlannerStreamBinder = void Function(String channel, void Function(String type, Map<String, dynamic> data) onEvent);`
    The Notifier reads `ref.read(plannerStreamBinderProvider)`; production provider wires Pusher, tests override it.

- [ ] **Step 1: Write the provider** (state + notifier + binder seam)

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/models/planner_message.dart';
import '../data/models/planner_plan.dart';
import '../data/rehearsal_planner_repository.dart';

typedef PlannerStreamBinder = void Function(
  String channel,
  void Function(String type, Map<String, dynamic> data) onEvent,
);

/// Production binder: subscribes to the private Pusher channel and forwards
/// 'planner.stream' events (type + data) to [onEvent].
final plannerStreamBinderProvider = Provider<PlannerStreamBinder>((ref) {
  return (channel, onEvent) async {
    final token = await ref.read(secureStorageProvider).readToken();
    if (token == null || AppConfig.pusherKey.isEmpty) return;
    final pusher = PusherChannelsFlutter.getInstance();
    await pusher.init(
      apiKey: AppConfig.pusherKey,
      cluster: AppConfig.pusherCluster,
      authEndpoint: '${AppConfig.baseUrl}/broadcasting/auth',
      onAuthorizer: (channelName, socketId, options) => {
        'headers': {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      },
    );
    await pusher.connect();
    await pusher.subscribe(
      channelName: channel,
      onEvent: (PusherEvent e) {
        if (e.eventName != 'planner.stream') return;
        final raw = e.data;
        if (raw == null) return;
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) return;
        final type = decoded['type'] as String? ?? '';
        onEvent(type, decoded);
      },
    );
    ref.onDispose(() async {
      await pusher.unsubscribe(channelName: channel);
    });
  };
});

class RehearsalPlannerState {
  const RehearsalPlannerState({
    this.messages = const [],
    this.isStarting = false,
    this.isSending = false,
    this.error,
    this.sessionId,
  });

  final List<PlannerMessage> messages;
  final bool isStarting;
  final bool isSending;
  final String? error;
  final int? sessionId;

  RehearsalPlannerState copyWith({
    List<PlannerMessage>? messages,
    bool? isStarting,
    bool? isSending,
    String? Function()? error,
    int? sessionId,
  }) =>
      RehearsalPlannerState(
        messages: messages ?? this.messages,
        isStarting: isStarting ?? this.isStarting,
        isSending: isSending ?? this.isSending,
        error: error != null ? error() : this.error,
        sessionId: sessionId ?? this.sessionId,
      );
}

class RehearsalPlannerNotifier extends Notifier<RehearsalPlannerState> {
  RehearsalPlannerNotifier(this._bandId);
  final int _bandId;

  RehearsalPlannerRepository get _repo => ref.read(rehearsalPlannerRepositoryProvider);

  @override
  RehearsalPlannerState build() => const RehearsalPlannerState();

  Future<void> start() async {
    if (state.sessionId != null) return;
    state = state.copyWith(isStarting: true, error: () => null);
    try {
      final r = await _repo.startSession(_bandId);
      // Insert a streaming placeholder for the assistant's opening turn.
      final placeholder = PlannerMessage(
        id: r.assistantMessageId,
        role: 'assistant',
        text: '',
        status: 'streaming',
      );
      state = state.copyWith(
        sessionId: r.sessionId,
        messages: [placeholder],
        isStarting: false,
      );
      _bind(r.channel);
    } catch (e) {
      state = state.copyWith(isStarting: false, error: () => e.toString());
    }
  }

  Future<void> send(String text) async {
    final sessionId = state.sessionId;
    if (sessionId == null || text.trim().isEmpty) return;
    state = state.copyWith(isSending: true, error: () => null);
    try {
      final r = await _repo.sendMessage(_bandId, sessionId, text.trim());
      final placeholder = PlannerMessage(
        id: r.assistantMessageId,
        role: 'assistant',
        text: '',
        status: 'streaming',
      );
      state = state.copyWith(
        messages: [...state.messages, r.userMessage, placeholder],
        isSending: false,
      );
      // Channel is the same per session; binder is idempotent enough for v1.
      _bind(r.channel);
    } catch (e) {
      state = state.copyWith(isSending: false, error: () => e.toString());
    }
  }

  bool _bound = false;
  void _bind(String channel) {
    if (_bound) return;
    _bound = true;
    ref.read(plannerStreamBinderProvider)(channel, _onStreamEvent);
  }

  void _onStreamEvent(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'text_delta':
        final delta = data['delta'] as String? ?? '';
        _updateStreaming((m) => m.copyWith(text: m.text + delta));
      case 'done':
        final id = (data['message_id'] as num?)?.toInt();
        final content = data['content'] as String? ?? '';
        final suggestions = (data['suggestions'] as List?)?.cast<String>() ?? const <String>[];
        final planRaw = data['plan'];
        final plan = planRaw is Map<String, dynamic> ? PlannerPlan.fromJson(planRaw) : null;
        _updateById(id, (m) => m.copyWith(text: content, suggestions: suggestions, plan: plan, status: 'complete'));
      case 'error':
        final id = (data['message_id'] as num?)?.toInt();
        _updateById(id, (m) => m.copyWith(status: 'failed'));
    }
  }

  /// Apply [fn] to the most recent streaming assistant message.
  void _updateStreaming(PlannerMessage Function(PlannerMessage) fn) {
    final msgs = [...state.messages];
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == 'assistant' && msgs[i].status == 'streaming') {
        msgs[i] = fn(msgs[i]);
        state = state.copyWith(messages: msgs);
        return;
      }
    }
  }

  void _updateById(int? id, PlannerMessage Function(PlannerMessage) fn) {
    if (id == null) return;
    final msgs = [...state.messages];
    final idx = msgs.indexWhere((m) => m.id == id);
    if (idx < 0) return;
    msgs[idx] = fn(msgs[idx]);
    state = state.copyWith(messages: msgs);
  }

  Future<void> retryLast() async {
    // Drop a trailing failed assistant message and re-send the preceding user text.
    final msgs = [...state.messages];
    if (msgs.isEmpty || msgs.last.status != 'failed') return;
    msgs.removeLast();
    final lastUser = msgs.lastWhere((m) => m.isUser, orElse: () => const PlannerMessage(id: -1, role: 'user', text: ''));
    state = state.copyWith(messages: msgs);
    if (lastUser.id != -1) await send(lastUser.text);
  }
}

final rehearsalPlannerProvider =
    NotifierProvider.family<RehearsalPlannerNotifier, RehearsalPlannerState, int>(
  RehearsalPlannerNotifier.new,
);
```

> NOTE for implementer: confirm `secureStorageProvider` and `readToken()` names from the codebase (recon referenced `ref.read(secureStorageProvider).readToken()`). Adjust only those identifiers if they differ. The `_bound` guard keeps v1 simple (one subscription per notifier lifetime, same channel per session).

- [ ] **Step 2: Write the failing test** (override the binder; drive deltas synchronously)

`test/features/rehearsal_planner/rehearsal_planner_provider_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_message.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/rehearsal_planner_repository.dart';
import 'package:tts_bandmate/features/rehearsal_planner/providers/rehearsal_planner_provider.dart';

class FakeRepo implements RehearsalPlannerRepository {
  void Function(String type, Map<String, dynamic> data)? captured;
  @override
  Future<({int sessionId, String channel, int assistantMessageId})> startSession(int bandId) async =>
      (sessionId: 1, channel: 'private-rehearsal-planner.1', assistantMessageId: 100);
  @override
  Future<({PlannerMessage userMessage, int assistantMessageId, String channel})> sendMessage(int bandId, int sessionId, String text) async =>
      (
        userMessage: PlannerMessage(id: 200, role: 'user', text: text, status: 'complete'),
        assistantMessageId: 201,
        channel: 'private-rehearsal-planner.1',
      );
  @override
  Future<List<PlannerMessage>> history(int bandId, int sessionId) async => [];
}

void main() {
  late FakeRepo repo;
  late void Function(String, Map<String, dynamic>)? onEvent;

  ProviderContainer makeContainer() {
    repo = FakeRepo();
    onEvent = null;
    return ProviderContainer(overrides: [
      rehearsalPlannerRepositoryProvider.overrideWithValue(repo),
      plannerStreamBinderProvider.overrideWithValue((channel, cb) => onEvent = cb),
    ]);
  }

  test('start inserts streaming placeholder and binds channel', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(rehearsalPlannerProvider(7).notifier).start();

    final s = c.read(rehearsalPlannerProvider(7));
    expect(s.sessionId, 1);
    expect(s.messages.single.status, 'streaming');
    expect(onEvent, isNotNull); // channel bound
  });

  test('text_delta appends to streaming message; done finalizes', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(rehearsalPlannerProvider(7).notifier).start();

    onEvent!('text_delta', {'delta': 'Hel'});
    onEvent!('text_delta', {'delta': 'lo'});
    expect(c.read(rehearsalPlannerProvider(7)).messages.single.text, 'Hello');

    onEvent!('done', {
      'message_id': 100,
      'content': 'Hello there',
      'suggestions': ['A', 'B'],
      'plan': null,
    });
    final m = c.read(rehearsalPlannerProvider(7)).messages.single;
    expect(m.status, 'complete');
    expect(m.text, 'Hello there');
    expect(m.suggestions, ['A', 'B']);
  });

  test('error marks message failed; retryLast re-sends prior user text', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(7).notifier);
    await n.start();
    onEvent!('done', {'message_id': 100, 'content': 'opening', 'suggestions': [], 'plan': null});

    await n.send('plan please');
    onEvent!('error', {'message_id': 201});
    expect(c.read(rehearsalPlannerProvider(7)).messages.last.status, 'failed');

    await n.retryLast();
    // After retry, a new streaming placeholder exists (id 201 again from fake).
    expect(c.read(rehearsalPlannerProvider(7)).messages.last.status, 'streaming');
  });
}
```

- [ ] **Step 3: Run test**

Run: `flutter test test/features/rehearsal_planner/rehearsal_planner_provider_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/features/rehearsal_planner/providers/ test/features/rehearsal_planner/rehearsal_planner_provider_test.dart
git commit -m "feat(rehearsal-planner): chat notifier with Pusher streaming + retry"
```

---

### Task B4: Chat screen + entry button + route

**Files:**
- Create: `lib/features/rehearsal_planner/screens/rehearsal_planner_screen.dart`
- Modify: `lib/core/config/router.dart` (add `/rehearsal-planner` route)
- Modify: `lib/features/rehearsals/screens/rehearsals_screen.dart` (nav-bar trailing button → push route)
- Test: `test/features/rehearsal_planner/rehearsal_planner_screen_test.dart`

**Interfaces:**
- Consumes: `rehearsalPlannerProvider` (B3), `selectedBandProvider`, `context.*Text` colors, `ErrorView`.
- Produces: `RehearsalPlannerScreen` (Cupertino chat: message list with bubbles, streaming indicator, suggestion chips, plan card, composer with send button). Route `/rehearsal-planner`.

- [ ] **Step 1: Write the screen** (plain `Text` for assistant content — no markdown dependency in v1)

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/context_colors.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/models/planner_message.dart';
import '../providers/rehearsal_planner_provider.dart';

class RehearsalPlannerScreen extends ConsumerWidget {
  const RehearsalPlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandId = ref.watch(selectedBandProvider).value;
    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Rehearsal Planner')),
        child: Center(child: Text('No band selected')),
      );
    }
    return _PlannerView(bandId: bandId);
  }
}

class _PlannerView extends ConsumerStatefulWidget {
  const _PlannerView({required this.bandId});
  final int bandId;
  @override
  ConsumerState<_PlannerView> createState() => _PlannerViewState();
}

class _PlannerViewState extends ConsumerState<_PlannerView> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rehearsalPlannerProvider(widget.bandId).notifier).start();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rehearsalPlannerProvider(widget.bandId));
    final notifier = ref.read(rehearsalPlannerProvider(widget.bandId).notifier);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Rehearsal Planner')),
      child: SafeArea(
        child: Column(
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(ErrorView.friendlyMessage(state.error!),
                    style: TextStyle(color: CupertinoColors.systemRed.resolveFrom(context))),
              ),
            Expanded(
              child: state.isStarting && state.messages.isEmpty
                  ? const Center(child: CupertinoActivityIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: state.messages.length,
                      itemBuilder: (_, i) => _Bubble(
                        message: state.messages[i],
                        onSuggestionTap: (s) => notifier.send(s),
                        onRetry: notifier.retryLast,
                      ),
                    ),
            ),
            _Composer(
              controller: _controller,
              isBusy: state.isSending,
              onSend: () {
                final text = _controller.text;
                _controller.clear();
                notifier.send(text);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onSuggestionTap, required this.onRetry});
  final PlannerMessage message;
  final void Function(String) onSuggestionTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isStreaming = message.status == 'streaming';
    final isFailed = message.status == 'failed';

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          decoration: BoxDecoration(
            color: isUser
                ? CupertinoColors.activeBlue.resolveFrom(context)
                : CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: isStreaming && message.text.isEmpty
              ? const CupertinoActivityIndicator()
              : Text(
                  isFailed ? 'Failed to respond.' : message.text,
                  style: TextStyle(color: isUser ? CupertinoColors.white : context.primaryText, fontSize: 15),
                ),
        ),
        if (isFailed)
          CupertinoButton(padding: EdgeInsets.zero, onPressed: onRetry, child: const Text('Retry')),
        if (message.plan != null) _PlanCard(plan: message.plan!),
        if (message.suggestions.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final s in message.suggestions)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: CupertinoColors.systemGrey5.resolveFrom(context),
                  minimumSize: Size.zero,
                  onPressed: () => onSuggestionTap(s),
                  child: Text(s, style: TextStyle(color: context.primaryText, fontSize: 13)),
                ),
            ],
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});
  final dynamic plan; // PlannerPlan
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(plan.title, style: TextStyle(fontWeight: FontWeight.w600, color: context.primaryText)),
          const SizedBox(height: 6),
          for (final item in plan.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('• ${item.title} — ${item.reason}',
                  style: TextStyle(fontSize: 14, color: context.secondaryText)),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.isBusy, required this.onSend});
  final TextEditingController controller;
  final bool isBusy;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: CupertinoColors.separator.resolveFrom(context), width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: 'Ask the planner…',
              maxLines: null,
              style: TextStyle(color: context.primaryText),
              placeholderStyle: TextStyle(color: context.placeholderText),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: isBusy ? null : onSend,
            child: isBusy
                ? const CupertinoActivityIndicator()
                : Icon(CupertinoIcons.arrow_up_circle_fill, size: 28, color: CupertinoColors.activeBlue.resolveFrom(context)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add the route** in `router.dart` near the rehearsal routes:

```dart
GoRoute(
  path: '/rehearsal-planner',
  builder: (_, __) => const RehearsalPlannerScreen(),
),
```

Add the import: `import '../../features/rehearsal_planner/screens/rehearsal_planner_screen.dart';`

- [ ] **Step 3: Add the entry button** to `rehearsals_screen.dart`'s `CupertinoNavigationBar` (trailing), matching its existing nav-bar button style:

```dart
trailing: CupertinoButton(
  padding: EdgeInsets.zero,
  onPressed: () => context.push('/rehearsal-planner'),
  child: const Icon(CupertinoIcons.sparkles),
),
```

Ensure `import 'package:go_router/go_router.dart';` is present (it is, if `context.push` is used elsewhere there; add if missing).

- [ ] **Step 4: Write the failing widget test** (override providers; no real Pusher)

`test/features/rehearsal_planner/rehearsal_planner_screen_test.dart`:
```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_message.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/rehearsal_planner_repository.dart';
import 'package:tts_bandmate/features/rehearsal_planner/providers/rehearsal_planner_provider.dart';
import 'package:tts_bandmate/features/rehearsal_planner/screens/rehearsal_planner_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class FakeRepo implements RehearsalPlannerRepository {
  @override
  Future<({int sessionId, String channel, int assistantMessageId})> startSession(int bandId) async =>
      (sessionId: 1, channel: 'c', assistantMessageId: 100);
  @override
  Future<({PlannerMessage userMessage, int assistantMessageId, String channel})> sendMessage(int b, int s, String t) async =>
      (userMessage: PlannerMessage(id: 200, role: 'user', text: t, status: 'complete'), assistantMessageId: 201, channel: 'c');
  @override
  Future<List<PlannerMessage>> history(int b, int s) async => [];
}

void main() {
  testWidgets('renders streaming opening bubble and composer', (tester) async {
    void Function(String, Map<String, dynamic>)? onEvent;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedBandProvider.overrideWith((ref) => Future.value(7)),
          rehearsalPlannerRepositoryProvider.overrideWithValue(FakeRepo()),
          plannerStreamBinderProvider.overrideWithValue((c, cb) => onEvent = cb),
        ],
        child: const CupertinoApp(home: RehearsalPlannerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Composer present
    expect(find.byType(CupertinoTextField), findsOneWidget);

    // Drive a delta + done
    onEvent!('text_delta', {'delta': 'Hi there'});
    await tester.pump();
    expect(find.text('Hi there'), findsOneWidget);
  });
}
```

> NOTE for implementer: match how `selectedBandProvider` is overridden in existing widget tests (it's an async provider; the recon shows `ref.watch(selectedBandProvider).value`). If the project's test harness has a helper for overriding the selected band, use it.

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/features/rehearsal_planner/rehearsal_planner_screen_test.dart && flutter analyze lib/features/rehearsal_planner test/features/rehearsal_planner`
Expected: PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/rehearsal_planner/screens/ lib/core/config/router.dart lib/features/rehearsals/screens/rehearsals_screen.dart test/features/rehearsal_planner/rehearsal_planner_screen_test.dart
git commit -m "feat(rehearsal-planner): chat screen, route, and rehearsals entry button"
```

---

### Task B5: Full mobile verification + PR to main

- [ ] **Step 1:** Run the whole planner test set + analyzer.

Run: `flutter test test/features/rehearsal_planner && flutter analyze`
Expected: all green, no issues.

- [ ] **Step 2:** Optional on-device smoke (requires backend deployed to staging or local). Use the `run-on-device` skill to open the rehearsals screen, tap the sparkles button, confirm the opening turn streams in. Skip if backend not yet on staging.

- [ ] **Step 3:** Push + open PR to main.

```bash
git push -u origin feat/ai-rehearsal-planner
gh pr create --base main --title "feat(rehearsal-planner): AI rehearsal planner chat" --body "Interactive AI rehearsal planner. Streams assistant replies over Pusher, shows suggestion chips + structured plans, entry from the rehearsals screen. Backend in TTS staging PR. See docs/superpowers/specs/2026-06-30-ai-rehearsal-planner-design.md."
```

- [ ] **Step 4:** Wait for Copilot review; address comments.

---

## Cross-repo sequencing notes

- Implement **Part A (backend) first**, deploy/merge to staging (auto-deploys), then the mobile app can be smoke-tested on-device against staging.
- The two repos are independently testable: backend tests stub the AI service; mobile tests override the repository + Pusher binder. No live AI calls in any test.
- The wire contract is the contract between them: endpoint shapes (Task A5 / B2) and the `planner.stream` event payload (`text_delta`/`done`/`error`, Task A3/A4 ↔ B3). Keep these identical.

## Self-review notes (addressed)

- **Spec coverage:** four context sources (A2), multi-turn + opening turn (A4/A5), streaming over Pusher (A3/A4/B3), persistence (A1), suggestions + two-section new-repertoire (agent instructions A3), library-only-when-present / empty-library-not-an-error (A2/A5), entry button (B4), tests both sides. ✓
- **Placeholders:** Two intentional "find the existing pattern" notes — band-permission grant helper (A5) and selectedBand test override (B4) — point at real, existing repo conventions rather than inventing them; flagged explicitly for the implementer.
- **Type consistency:** `text_delta`/`done`/`error` event types and the `{message_id, content, suggestions, plan}` done-payload match across A4 (dispatch) and B3 (consume). `assistant_message_id`/`session_id`/`channel` match across A5 and B2.
