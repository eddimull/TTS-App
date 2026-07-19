# Chat Polish Phase 2 — Emoji Reactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** React to any chat message with a quick set of 6 emoji tapbacks, aggregated as chips under the bubble, live across clients.

**Architecture:** Backend adds a `message_reactions` table and two idempotent endpoints; the aggregated `reactions` array is added inside `MessageFormatter::format()` — the single serializer used by the thread page, store/update responses, and every broadcast — and reaction changes fire the existing `message.updated` stream event, so the mobile realtime path needs no new event handling (its `message.updated` case already re-parses and replaces the message). Mobile adds the model field, repository calls, an optimistic toggle in the thread notifier, and UI (action-sheet emoji row + chips).

**Tech Stack:** Laravel (TTS repo) + Flutter/Riverpod (this repo). No new packages either side.

**Spec:** `docs/superpowers/specs/2026-07-18-chat-polish-design.md` (Phase 2 section — wire contract is FROZEN).

## Global Constraints

- **Repos/branches:** TTS backend at `/home/eddie/github/TTS`, new branch `feat/chat-message-reactions` off `staging` (PR → staging, created as DRAFT). Mobile at `/home/eddie/github/tts_bandmate`, branch `feat/chat-reactions` (already created off main; PR → main).
- **Backend commands ALWAYS via container:** `docker compose exec app php artisan test ...` — never host php. Backend tasks are implemented by the `laravel-mobile-api-dev` agent.
- **Frozen wire contract:**
  - Table `message_reactions`: `message_id` FK cascadeOnDelete, `user_id` FK, `emoji` string, timestamps, unique `(message_id, user_id, emoji)`.
  - `POST /api/mobile/messages/{message}/reactions` body `{"emoji":"👍"}` — idempotent add; `DELETE /api/mobile/messages/{message}/reactions/{emoji}` — idempotent remove. Both return `200 {"reactions":[...]}` (the message's updated aggregated array).
  - Message JSON everywhere gains `"reactions": [{"emoji":"👍","count":2,"user_ids":[1,5]}]` (empty list when none).
  - Reaction changes broadcast the existing `message.updated` type on `private-conversation.{id}` with the full formatted message, `toOthers()`.
  - Authorization: conversation participant (`ConversationPolicy::view`); soft-deleted messages 404 via implicit route binding (binding excludes trashed — do NOT add a redundant trashed guard).
  - Emoji validated server-side as `required|string|max:16` (NOT whitelisted — spec allows extending to a full picker later).
  - Quick set (mobile UI): 👍 ❤️ 😂 😮 😢 🎉
- Cupertino widgets; text colors via `context.secondaryText`/`context.tertiaryText` — never raw `CupertinoColors.*Label` in a `color:`.
- Hand-written `fromJson`, no codegen. No version bumps (release-please owns versions).
- Mobile analyze baseline: 4 known items (2× secure_storage deprecation infos, 2× main.dart experimental warnings).
- Commit only files the task names — never `git add -A` (both repos have unrelated untracked/modified files).

---

### Task B1: Backend — reactions table, model, formatter aggregation

**Repo:** `/home/eddie/github/TTS` — create branch `feat/chat-message-reactions` off latest `origin/staging` first.

**Files:**
- Create: `database/migrations/2026_07_18_000001_create_message_reactions_table.php`
- Create: `app/Models/MessageReaction.php`
- Modify: `app/Models/Message.php` (add `reactions()` relation)
- Modify: `app/Services/Chat/MessageFormatter.php` (add `reactions` key)
- Modify: `app/Http/Controllers/Api/Mobile/ConversationsController.php:295` (threadPage eager-load) and `:407` (storeMessage load); `app/Http/Controllers/Api/Mobile/MessagesController.php:27` (update load)
- Test: `tests/Feature/Api/Mobile/Chat/MessageReactionsTest.php` (new; formatter-shape tests here)

**Interfaces:**
- Consumes: existing `Message`, `MessageFormatter::format()`, `ChatTestHelpers` trait.
- Produces (B2 relies on): `MessageReaction` model (fillable `message_id, user_id, emoji`), `Message::reactions()` hasMany, `format()` output containing `reactions` aggregated as the frozen contract (empty `[]` when none, `user_ids` in insertion order).

- [ ] **Step 1: Write failing tests**

Create `tests/Feature/Api/Mobile/Chat/MessageReactionsTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Models\Message;
use App\Models\MessageReaction;
use App\Services\Chat\ConversationService;
use App\Services\Chat\MessageFormatter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

class MessageReactionsTest extends TestCase
{
    use RefreshDatabase;
    use ChatTestHelpers;

    protected function setUp(): void
    {
        parent::setUp();
        Queue::fake();
    }

    public function test_formatter_aggregates_reactions_by_emoji(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $owner->id, 'body' => 'hi']);

        MessageReaction::create(['message_id' => $message->id, 'user_id' => $owner->id, 'emoji' => '👍']);
        MessageReaction::create(['message_id' => $message->id, 'user_id' => $member->id, 'emoji' => '👍']);
        MessageReaction::create(['message_id' => $message->id, 'user_id' => $member->id, 'emoji' => '🎉']);

        $formatted = app(MessageFormatter::class)->format($message->fresh(['user', 'attachments', 'reactions']));

        $this->assertSame([
            ['emoji' => '👍', 'count' => 2, 'user_ids' => [$owner->id, $member->id]],
            ['emoji' => '🎉', 'count' => 1, 'user_ids' => [$member->id]],
        ], $formatted['reactions']);
    }

    public function test_formatter_returns_empty_reactions_array_when_none(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $owner->id, 'body' => 'hi']);

        $formatted = app(MessageFormatter::class)->format($message->fresh(['user', 'attachments', 'reactions']));

        $this->assertSame([], $formatted['reactions']);
    }

    public function test_duplicate_reaction_rows_are_rejected_by_unique_index(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $owner->id, 'body' => 'hi']);

        MessageReaction::create(['message_id' => $message->id, 'user_id' => $owner->id, 'emoji' => '👍']);

        $this->expectException(\Illuminate\Database\QueryException::class);
        MessageReaction::create(['message_id' => $message->id, 'user_id' => $owner->id, 'emoji' => '👍']);
    }

    public function test_deleting_message_cascades_reactions(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $owner->id, 'body' => 'hi']);
        MessageReaction::create(['message_id' => $message->id, 'user_id' => $owner->id, 'emoji' => '👍']);

        $message->forceDelete();

        $this->assertDatabaseCount('message_reactions', 0);
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/MessageReactionsTest.php`
Expected: FAIL — `Class "App\Models\MessageReaction" not found`.

- [ ] **Step 3: Implement**

Migration `database/migrations/2026_07_18_000001_create_message_reactions_table.php` (mirror the `message_attachments` block in `2026_07_12_000001_create_chat_tables.php:47-57`):

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('message_reactions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('message_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('emoji', 16);
            $table->timestamps();
            $table->unique(['message_id', 'user_id', 'emoji']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('message_reactions');
    }
};
```

`app/Models/MessageReaction.php` (mirror `MessageAttachment`):

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MessageReaction extends Model
{
    protected $fillable = ['message_id', 'user_id', 'emoji'];

    public function message()
    {
        return $this->belongsTo(Message::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
```

`app/Models/Message.php` — next to `attachments()` (line ~59):

```php
    public function reactions()
    {
        return $this->hasMany(MessageReaction::class);
    }
```

`app/Services/Chat/MessageFormatter.php` — inside `format()`, after the `attachments` key:

```php
            'reactions' => $message->reactions
                ->groupBy('emoji')
                ->map(fn ($group, $emoji) => [
                    'emoji' => (string) $emoji,
                    'count' => $group->count(),
                    'user_ids' => $group->pluck('user_id')->values()->all(),
                ])
                ->values()
                ->all(),
```

Eager-load updates (prevents N+1; `reactions` relation is small per message):
- `ConversationsController::threadPage()` line ~295: `->with(['user', 'attachments'])` → `->with(['user', 'attachments', 'reactions'])`
- `ConversationsController::storeMessage()` line ~407: `->load(['user', 'attachments'])` → `->load(['user', 'attachments', 'reactions'])`
- `MessagesController::update()` line ~27: same `load` change.

Run migration: `docker compose exec app php artisan migrate`

- [ ] **Step 4: Run tests to verify pass**

Run: `docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/MessageReactionsTest.php`
Expected: 4 passing. Also run the existing chat suite to confirm the formatter change broke nothing:
`docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/` — all green (existing message-shape tests may assert exact arrays; if one fails on the new `reactions` key, update that assertion to include `'reactions' => []` and say so in your report).

- [ ] **Step 5: Commit**

```bash
git add database/migrations/2026_07_18_000001_create_message_reactions_table.php app/Models/MessageReaction.php app/Models/Message.php app/Services/Chat/MessageFormatter.php app/Http/Controllers/Api/Mobile/ConversationsController.php app/Http/Controllers/Api/Mobile/MessagesController.php tests/Feature/Api/Mobile/Chat/MessageReactionsTest.php
git commit -m "feat(chat): message reactions table, model, and formatter aggregation"
```

---

### Task B2: Backend — reaction endpoints + broadcast

**Repo:** `/home/eddie/github/TTS`, same branch.

**Files:**
- Create: `app/Http/Controllers/Api/Mobile/MessageReactionsController.php`
- Modify: `routes/api.php` (chat block, ~L122-134)
- Test: `tests/Feature/Api/Mobile/Chat/MessageReactionsTest.php` (append)

**Interfaces:**
- Consumes (from B1): `MessageReaction`, `Message::reactions()`, `format()['reactions']`.
- Produces (mobile M3 relies on): `POST /api/mobile/messages/{message}/reactions {emoji}` and `DELETE /api/mobile/messages/{message}/reactions/{emoji}`, both → `200 {"reactions":[...]}`; `message.updated` broadcast with full formatted message on both.

- [ ] **Step 1: Write failing tests**

Append to `MessageReactionsTest.php` (add `use App\Events\ConversationStreamEvent;` and `use Illuminate\Support\Facades\Event;` imports):

```php
    public function test_participant_can_add_and_remove_reaction(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $owner->id, 'body' => 'hi']);

        $this->actingAs($member)
            ->postJson("/api/mobile/messages/{$message->id}/reactions", ['emoji' => '👍'])
            ->assertOk()
            ->assertJson(['reactions' => [['emoji' => '👍', 'count' => 1, 'user_ids' => [$member->id]]]]);

        $this->actingAs($member)
            ->deleteJson("/api/mobile/messages/{$message->id}/reactions/" . rawurlencode('👍'))
            ->assertOk()
            ->assertJsonCount(0, 'reactions');

        $this->assertDatabaseCount('message_reactions', 0);
    }

    public function test_add_is_idempotent_and_remove_of_absent_is_ok(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $owner->id, 'body' => 'hi']);

        $this->actingAs($member)->postJson("/api/mobile/messages/{$message->id}/reactions", ['emoji' => '👍'])->assertOk();
        $this->actingAs($member)->postJson("/api/mobile/messages/{$message->id}/reactions", ['emoji' => '👍'])->assertOk();
        $this->assertDatabaseCount('message_reactions', 1);

        $this->actingAs($member)
            ->deleteJson("/api/mobile/messages/{$message->id}/reactions/" . rawurlencode('😂'))
            ->assertOk();
        $this->assertDatabaseCount('message_reactions', 1);
    }

    public function test_non_participant_cannot_react(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        [$outsider] = $this->makeOwnerWithBand();
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $owner->id, 'body' => 'hi']);

        $this->actingAs($outsider)
            ->postJson("/api/mobile/messages/{$message->id}/reactions", ['emoji' => '👍'])
            ->assertForbidden();
    }

    public function test_reacting_to_soft_deleted_message_is_404(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $owner->id, 'body' => 'hi']);
        $message->delete();

        $this->actingAs($member)
            ->postJson("/api/mobile/messages/{$message->id}/reactions", ['emoji' => '👍'])
            ->assertNotFound();
    }

    public function test_emoji_is_required_and_bounded(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $owner->id, 'body' => 'hi']);

        $this->actingAs($member)
            ->postJson("/api/mobile/messages/{$message->id}/reactions", [])
            ->assertUnprocessable();
        $this->actingAs($member)
            ->postJson("/api/mobile/messages/{$message->id}/reactions", ['emoji' => str_repeat('x', 17)])
            ->assertUnprocessable();
    }

    public function test_reaction_changes_broadcast_message_updated(): void
    {
        Event::fake([ConversationStreamEvent::class]);

        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $message = $dm->messages()->create(['user_id' => $owner->id, 'body' => 'hi']);

        $this->actingAs($member)->postJson("/api/mobile/messages/{$message->id}/reactions", ['emoji' => '👍'])->assertOk();

        Event::assertDispatched(ConversationStreamEvent::class, function ($event) use ($dm, $message) {
            return $event->broadcastAs() === 'message.updated'
                && $event->broadcastOn()->name === 'private-conversation.' . $dm->id
                && $event->broadcastWith()['message']['id'] === $message->id
                && $event->broadcastWith()['message']['reactions'][0]['emoji'] === '👍';
        });
    }
```

(If `ConversationStreamEvent::broadcastOn()` returns a channel whose `name` is prefixed differently, match however the existing `ChatBroadcastingTest` asserts channels — follow its idiom and note the adaptation.)

- [ ] **Step 2: Run to verify failure**

Run: `docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/MessageReactionsTest.php`
Expected: new tests FAIL with 404s (routes don't exist); B1 tests still pass.

- [ ] **Step 3: Implement**

`app/Http/Controllers/Api/Mobile/MessageReactionsController.php`:

```php
<?php

namespace App\Http\Controllers\Api\Mobile;

use App\Events\ConversationStreamEvent;
use App\Http\Controllers\Controller;
use App\Models\Message;
use App\Services\Chat\MessageFormatter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Add/remove the caller's emoji reactions on a message.
 * Authorization: conversation participant (ConversationPolicy::view);
 * soft-deleted messages 404 via implicit binding. Both endpoints are
 * idempotent and return the message's aggregated reactions array.
 */
class MessageReactionsController extends Controller
{
    public function __construct(private MessageFormatter $formatter)
    {
    }

    /** POST /api/mobile/messages/{message}/reactions */
    public function store(Request $request, Message $message): JsonResponse
    {
        $this->authorize('view', $message->conversation);
        $data = $request->validate(['emoji' => ['required', 'string', 'max:16']]);

        $message->reactions()->firstOrCreate([
            'user_id' => $request->user()->id,
            'emoji' => $data['emoji'],
        ]);

        return $this->respondWithReactions($message);
    }

    /** DELETE /api/mobile/messages/{message}/reactions/{emoji} */
    public function destroy(Request $request, Message $message, string $emoji): JsonResponse
    {
        $this->authorize('view', $message->conversation);

        $message->reactions()
            ->where('user_id', $request->user()->id)
            ->where('emoji', $emoji)
            ->delete();

        return $this->respondWithReactions($message);
    }

    /** Re-format, stream the change to other open clients, return the aggregate. */
    private function respondWithReactions(Message $message): JsonResponse
    {
        $message->load(['user', 'attachments', 'reactions']);
        $formatted = $this->formatter->format($message);

        broadcast(new ConversationStreamEvent(
            $message->conversation_id,
            'message.updated',
            ['message' => $formatted],
        ))->toOthers();

        return response()->json(['reactions' => $formatted['reactions']]);
    }
}
```

`routes/api.php` — in the chat block next to the existing message routes (~L132-133):

```php
        Route::post('/messages/{message}/reactions', [App\Http\Controllers\Api\Mobile\MessageReactionsController::class, 'store'])->name('mobile.messages.reactions.store');
        Route::delete('/messages/{message}/reactions/{emoji}', [App\Http\Controllers\Api\Mobile\MessageReactionsController::class, 'destroy'])->name('mobile.messages.reactions.destroy');
```

- [ ] **Step 4: Run tests to verify pass**

Run: `docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/MessageReactionsTest.php`
Expected: 10 passing. Then the full chat suite:
`docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/` — all green.

- [ ] **Step 5: Commit**

```bash
git add app/Http/Controllers/Api/Mobile/MessageReactionsController.php routes/api.php tests/Feature/Api/Mobile/Chat/MessageReactionsTest.php
git commit -m "feat(chat): idempotent reaction endpoints with message.updated streaming"
```

---

### Task M3: Mobile — reaction model, endpoints, repository

**Repo:** `/home/eddie/github/tts_bandmate`, branch `feat/chat-reactions` (already checked out).

**Files:**
- Modify: `lib/features/chat/data/models/chat_message.dart`
- Modify: `lib/core/network/api_endpoints.dart` (chat block, ~L252-270)
- Modify: `lib/features/chat/data/chat_repository.dart`
- Test: `test/features/chat/models_test.dart` and `test/features/chat/chat_repository_test.dart` (append)

**Interfaces:**
- Produces (M4/M5 rely on):
  - `class MessageReaction { final String emoji; final int count; final List<int> userIds; bool reactedBy(int userId); }` with `fromJson`.
  - `ChatMessage.reactions` (`List<MessageReaction>`, default const []), parsed from `json['reactions']`, and `copyWith(reactions: ...)`.
  - `ChatRepository.addReaction(int messageId, String emoji)` / `removeReaction(int messageId, String emoji)` → `Future<List<MessageReaction>>`.
  - `ApiEndpoints.mobileMessageReactions(int messageId)` and `mobileMessageReaction(int messageId, String emoji)` (emoji percent-encoded via `Uri.encodeComponent`).

- [ ] **Step 1: Write failing tests**

Append to `test/features/chat/models_test.dart`:

```dart
  test('ChatMessage parses reactions and reactedBy works', () {
    final message = ChatMessage.fromJson({
      'id': 1,
      'conversation_id': 5,
      'user_id': 2,
      'body': 'hi',
      'created_at': '2026-07-12T14:00:00Z',
      'reactions': [
        {'emoji': '👍', 'count': 2, 'user_ids': [2, 3]},
        {'emoji': '🎉', 'count': 1, 'user_ids': [3]},
      ],
    });

    expect(message.reactions, hasLength(2));
    expect(message.reactions.first.emoji, '👍');
    expect(message.reactions.first.count, 2);
    expect(message.reactions.first.reactedBy(2), isTrue);
    expect(message.reactions.first.reactedBy(9), isFalse);

    final cleared = message.copyWith(reactions: const []);
    expect(cleared.reactions, isEmpty);
    expect(message.reactions, hasLength(2)); // original untouched
  });

  test('ChatMessage reactions default to empty when absent', () {
    final message = ChatMessage.fromJson({
      'id': 1,
      'conversation_id': 5,
      'user_id': 2,
      'body': 'hi',
      'created_at': '2026-07-12T14:00:00Z',
    });
    expect(message.reactions, isEmpty);
  });
```

Append to `test/features/chat/chat_repository_test.dart`:

```dart
  test('addReaction posts emoji and parses reactions', () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, {
      'reactions': [
        {'emoji': '👍', 'count': 1, 'user_ids': [2]},
      ],
    }));

    final reactions = await repo.addReaction(9, '👍');

    expect(captured.single.method, 'POST');
    expect(captured.single.path, '/api/mobile/messages/9/reactions');
    expect(captured.single.data, {'emoji': '👍'});
    expect(reactions.single.emoji, '👍');
    expect(reactions.single.userIds, [2]);
  });

  test('removeReaction deletes percent-encoded emoji and parses reactions',
      () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, {'reactions': []}));

    final reactions = await repo.removeReaction(9, '👍');

    expect(captured.single.method, 'DELETE');
    expect(captured.single.path,
        '/api/mobile/messages/9/reactions/${Uri.encodeComponent('👍')}');
    expect(reactions, isEmpty);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/chat/models_test.dart test/features/chat/chat_repository_test.dart`
Expected: FAIL — `reactions` getter / `addReaction` not defined.

- [ ] **Step 3: Implement**

`lib/features/chat/data/models/chat_message.dart` — add above `ChatMessage`:

```dart
class MessageReaction {
  const MessageReaction({
    required this.emoji,
    required this.count,
    required this.userIds,
  });

  final String emoji;
  final int count;
  final List<int> userIds;

  bool reactedBy(int userId) => userIds.contains(userId);

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      MessageReaction(
        emoji: json['emoji'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        userIds: (json['user_ids'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
      );
}
```

In `ChatMessage`: add `this.reactions = const []` to the constructor, `final List<MessageReaction> reactions;` field, in `fromJson`:

```dart
        reactions: (json['reactions'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MessageReaction.fromJson)
            .toList(),
```

and in `copyWith` a `List<MessageReaction>? reactions` param passed as `reactions: reactions ?? this.reactions` (all other copyWith call sites keep working — the param is optional).

`lib/core/network/api_endpoints.dart` — in the chat block next to `mobileMessage`:

```dart
  static String mobileMessageReactions(int messageId) =>
      '/api/mobile/messages/$messageId/reactions';

  static String mobileMessageReaction(int messageId, String emoji) =>
      '/api/mobile/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}';
```

`lib/features/chat/data/chat_repository.dart` — next to `editMessage`:

```dart
  List<MessageReaction> _parseReactions(Map<String, dynamic>? data) =>
      (data?['reactions'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(MessageReaction.fromJson)
          .toList();

  /// Idempotent add of the caller's [emoji] reaction; returns the message's
  /// updated aggregate.
  Future<List<MessageReaction>> addReaction(int messageId, String emoji) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileMessageReactions(messageId),
      data: {'emoji': emoji},
    );
    return _parseReactions(res.data);
  }

  /// Idempotent removal of the caller's [emoji] reaction.
  Future<List<MessageReaction>> removeReaction(
      int messageId, String emoji) async {
    final res = await _dio.delete<Map<String, dynamic>>(
      ApiEndpoints.mobileMessageReaction(messageId, emoji),
    );
    return _parseReactions(res.data);
  }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `flutter test test/features/chat/models_test.dart test/features/chat/chat_repository_test.dart`
Expected: PASS (all, including pre-existing).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/data/models/chat_message.dart lib/core/network/api_endpoints.dart lib/features/chat/data/chat_repository.dart test/features/chat/models_test.dart test/features/chat/chat_repository_test.dart
git commit -m "feat(chat): reaction model, endpoints, and repository calls"
```

---

### Task M4: Mobile — optimistic toggle in the thread notifier

**Files:**
- Modify: `lib/features/chat/providers/chat_thread_provider.dart`
- Test: `test/features/chat/chat_thread_provider_test.dart` (append)

**Interfaces:**
- Consumes (from M3): `MessageReaction`, `ChatMessage.reactions`/`copyWith(reactions:)`, `ChatRepository.addReaction`/`removeReaction`.
- Produces (M5 relies on): `Future<void> toggleReaction(int messageId, String emoji, int userId)` on the thread notifier; exported pure helper `List<MessageReaction> toggleReactionList(List<MessageReaction> reactions, String emoji, int userId)`.

- [ ] **Step 1: Write failing tests**

Append to `test/features/chat/chat_thread_provider_test.dart` (reuse the file's harness: StubAdapter-backed repo, captured channel handler; give the stub a per-path response so reaction calls return a canned aggregate):

```dart
  group('toggleReactionList', () {
    test('adds when absent, removes when present, drops empty groups', () {
      const emoji = '👍';
      var reactions = toggleReactionList(const [], emoji, 2);
      expect(reactions.single.count, 1);
      expect(reactions.single.userIds, [2]);

      reactions = toggleReactionList(reactions, emoji, 3);
      expect(reactions.single.count, 2);

      reactions = toggleReactionList(reactions, emoji, 2);
      expect(reactions.single.count, 1);
      expect(reactions.single.userIds, [3]);

      reactions = toggleReactionList(reactions, emoji, 3);
      expect(reactions, isEmpty);
    });
  });

  test('toggleReaction is optimistic and reconciles with server aggregate',
      () async {
    // Arrange a loaded thread with one message (id 1) and a stub that
    // returns {'reactions': [...]} for the POST. Follow the file's existing
    // load() setup; then:
    await notifier.toggleReaction(1, '👍', currentUserId);
    // Immediately after the await both the optimistic and reconciled state
    // agree; assert the message now carries the server aggregate:
    final message =
        container.read(chatThreadProvider(5)).messages.single;
    expect(message.reactions.single.emoji, '👍');
    expect(message.reactions.single.reactedBy(currentUserId), isTrue);
  });

  test('toggleReaction rolls back on API failure', () async {
    // Same arrangement but the stub returns json(500, {...}) for the
    // reactions POST. After the await the message's reactions are unchanged:
    await notifier.toggleReaction(1, '👍', currentUserId);
    final message =
        container.read(chatThreadProvider(5)).messages.single;
    expect(message.reactions, isEmpty);
    expect(container.read(chatThreadProvider(5)).error, isNotNull);
  });

  test('realtime message.updated with reactions patches the message',
      () async {
    // Using the captured channel handler from the existing harness:
    capturedHandler!('message.updated', {
      'message': {
        'id': 1,
        'conversation_id': 5,
        'user_id': 3,
        'user_name': 'Sam',
        'body': 'you around?',
        'created_at': '2026-07-12T14:00:00Z',
        'reactions': [
          {'emoji': '🎉', 'count': 1, 'user_ids': [3]},
        ],
      },
    });
    final message =
        container.read(chatThreadProvider(5)).messages.single;
    expect(message.reactions.single.emoji, '🎉');
  });
```

(The three thread tests above are sketches of the assertions; wire the arrangement — container, overrides, load, canned pages — exactly like the file's existing tests do. The `toggleReactionList` group is complete as written.)

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/chat/chat_thread_provider_test.dart`
Expected: FAIL — `toggleReactionList` / `toggleReaction` not defined. (The realtime test may already pass once M3 landed the model parsing — that is fine; say so in the report.)

- [ ] **Step 3: Implement**

In `lib/features/chat/providers/chat_thread_provider.dart`, top level (exported for tests and reuse):

```dart
/// Pure toggle of [userId]'s [emoji] within an aggregated reactions list:
/// adds the user (creating the group at count 1) when absent, removes them
/// (dropping the group at count 0) when present.
List<MessageReaction> toggleReactionList(
  List<MessageReaction> reactions,
  String emoji,
  int userId,
) {
  final existing = reactions.where((r) => r.emoji == emoji).firstOrNull;
  if (existing == null) {
    return [
      ...reactions,
      MessageReaction(emoji: emoji, count: 1, userIds: [userId]),
    ];
  }
  if (!existing.userIds.contains(userId)) {
    return [
      for (final r in reactions)
        r.emoji == emoji
            ? MessageReaction(
                emoji: emoji,
                count: r.count + 1,
                userIds: [...r.userIds, userId],
              )
            : r,
    ];
  }
  return [
    for (final r in reactions)
      if (r.emoji != emoji)
        r
      else if (r.count > 1)
        MessageReaction(
          emoji: emoji,
          count: r.count - 1,
          userIds: [for (final id in r.userIds) if (id != userId) id],
        ),
  ];
}
```

On the notifier (next to `editMsg`):

```dart
  /// Optimistically toggles the caller's [emoji] on [messageId], then
  /// reconciles with the server's aggregate (or rolls back on failure).
  Future<void> toggleReaction(int messageId, String emoji, int userId) async {
    ChatMessage? original;
    for (final m in state.messages) {
      if (m.id == messageId) original = m;
    }
    if (original == null || original.isDeleted) return;

    final wasMine = original.reactions
        .any((r) => r.emoji == emoji && r.userIds.contains(userId));
    _replace(original.copyWith(
        reactions: toggleReactionList(original.reactions, emoji, userId)));
    try {
      final reactions = wasMine
          ? await _repo.removeReaction(messageId, emoji)
          : await _repo.addReaction(messageId, emoji);
      _patchReactions(messageId, reactions);
    } catch (e) {
      _patchReactions(messageId, original.reactions);
      state = state.copyWith(error: () => e.toString());
    }
  }

  void _patchReactions(int messageId, List<MessageReaction> reactions) {
    state = state.copyWith(messages: [
      for (final m in state.messages)
        m.id == messageId ? m.copyWith(reactions: reactions) : m,
    ]);
  }
```

Add `import 'package:collection/collection.dart';` for `firstOrNull` if the file doesn't already have it (it's a Flutter SDK transitive dep), plus the `MessageReaction` import if not already pulled in via the model import; use the file's existing error-sentinel idiom for `copyWith(error: ...)` (check whether it takes `String?` directly or a `String? Function()` closure and match it — the sketch above assumes the closure sentinel seen at lines 90-111).

- [ ] **Step 4: Run tests to verify pass**

Run: `flutter test test/features/chat/chat_thread_provider_test.dart`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/providers/chat_thread_provider.dart test/features/chat/chat_thread_provider_test.dart
git commit -m "feat(chat): optimistic reaction toggle with server reconcile and rollback"
```

---

### Task M5: Mobile — action-sheet emoji row + reaction chips

**Files:**
- Modify: `lib/features/chat/screens/conversation_thread_screen.dart`
- Test: `test/features/chat/conversation_thread_screen_test.dart` (append)

**Interfaces:**
- Consumes (from M4): `notifier.toggleReaction(messageId, emoji, userId)`; (from M3): `message.reactions`, `MessageReaction.reactedBy`.

- [ ] **Step 1: Write failing widget tests**

Append to `test/features/chat/conversation_thread_screen_test.dart`, following the file's harness (StubAdapter with per-path handling so a reactions POST returns `json(200, {'reactions': [...]})`; auth override so `currentUserId` is known — follow how existing tests fake auth):

```dart
  testWidgets('long-press on another user\'s message opens the emoji row',
      (tester) async {
    // Thread with one message from user 3 (not the current user), no
    // moderator rights. Long-press the bubble:
    await tester.longPress(find.text('you around?'));
    await tester.pumpAndSettle();

    // The sheet now opens (pre-change it early-returned) with the quick set
    // visible and no Edit/Delete for someone else's message:
    expect(find.text('👍'), findsOneWidget);
    expect(find.text('🎉'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('tapping a quick emoji posts the reaction and renders a chip',
      (tester) async {
    await tester.longPress(find.text('you around?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();

    // Optimistic chip under the bubble (emoji + count):
    expect(find.text('👍 1'), findsOneWidget);
    // And the POST went out:
    expect(
      captured.any((r) =>
          r.method == 'POST' && r.path == '/api/mobile/messages/1/reactions'),
      isTrue,
    );
  });

  testWidgets('tapping an existing chip toggles it off', (tester) async {
    // Seed the thread page JSON so message 1 already has
    // {'emoji':'👍','count':1,'user_ids':[<currentUserId>]} and stub the
    // DELETE to return {'reactions': []}. Then:
    await tester.tap(find.text('👍 1'));
    await tester.pumpAndSettle();
    expect(find.text('👍 1'), findsNothing);
    expect(captured.any((r) => r.method == 'DELETE'), isTrue);
  });
```

(Assertion sketches — wire arrangement per the file's existing idioms. Keep every `expect` shown.)

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/chat/conversation_thread_screen_test.dart`
Expected: the three new tests FAIL (no sheet for others' messages; no chips).

- [ ] **Step 3: Implement**

In `conversation_thread_screen.dart`:

3a. Quick set constant (top level):

```dart
/// The fixed tapback set (spec phase 2); extendable to a full picker later.
const kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🎉'];
```

3b. Rework `_showMessageActions` — the sheet now opens for ANY non-deleted message; the own/moderator gate moves onto the Edit/Delete actions; the emoji row becomes the sheet's `title`:

```dart
  Future<void> _showMessageActions(ChatMessage message) async {
    final auth = ref.read(authProvider).value;
    final currentUserId = auth is AuthAuthenticated ? auth.user.id : null;
    final state = ref.read(chatThreadProvider(widget.conversationId));
    final isOwn = message.userId == currentUserId;
    final canModerate = state.conversation?.canModerate ?? false;
    if (message.isDeleted || currentUserId == null) return;

    final notifier =
        ref.read(chatThreadProvider(widget.conversationId).notifier);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final emoji in kQuickReactions)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  notifier.toggleReaction(message.id, emoji, currentUserId);
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: message.reactions.any((r) =>
                            r.emoji == emoji && r.reactedBy(currentUserId))
                        ? CupertinoColors.activeBlue
                            .resolveFrom(sheetContext)
                            .withValues(alpha: 0.25)
                        : null,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
          ],
        ),
        actions: [
          if (isOwn && message.attachments.isEmpty)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                _showEditDialog(message);
              },
              child: const Text('Edit'),
            ),
          if (isOwn || canModerate)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetContext);
                notifier.deleteMsg(message.id);
              },
              child: const Text('Delete'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
```

Note `CupertinoActionSheet.actions` may be empty for a non-owner non-moderator — that renders fine (emoji title + cancel only).

3c. In the thread screen's `itemBuilder`, `_MessageBubble` gains `currentUserId: currentUserId` (already computed in `build`). In `_MessageBubble`: add `required this.currentUserId` (`final int currentUserId;`), and render chips right after the bubble's `GestureDetector` (inside the outer Column, before `showSeen`):

```dart
        if (message.reactions.isNotEmpty && !message.isDeleted)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 4,
              children: [
                for (final reaction in message.reactions)
                  GestureDetector(
                    onTap: () => ref
                        .read(chatThreadProvider(message.conversationId)
                            .notifier)
                        .toggleReaction(
                            message.id, reaction.emoji, currentUserId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: reaction.reactedBy(currentUserId)
                            ? CupertinoColors.activeBlue
                                .resolveFrom(context)
                                .withValues(alpha: 0.25)
                            : CupertinoColors.tertiarySystemBackground
                                .resolveFrom(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${reaction.emoji} ${reaction.count}',
                        style: TextStyle(
                            fontSize: 13, color: context.primaryText),
                      ),
                    ),
                  ),
              ],
            ),
          ),
```

`_MessageBubble` is a `ConsumerWidget`, so `ref` is available for the provider read.

- [ ] **Step 4: Run tests to verify pass**

Run: `flutter test test/features/chat/conversation_thread_screen_test.dart`
Expected: PASS (all — pre-existing tests that long-press for Edit/Delete keep passing since own-message gating on those actions is unchanged).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/screens/conversation_thread_screen.dart test/features/chat/conversation_thread_screen_test.dart
git commit -m "feat(chat): quick-reaction emoji row and aggregated reaction chips"
```

---

### Task T6: Full verification, PRs, on-device

- [ ] **Step 1: Mobile:** `flutter analyze` (4 known baseline only) and `flutter test` (all green).
- [ ] **Step 2: Backend:** `docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/` (all green).
- [ ] **Step 3:** Final whole-branch reviews (both repos), fix wave if needed.
- [ ] **Step 4: On-device** (run-on-device skill, needs the TTS branch checked out + migrated locally): long-press someone's message → emoji row; react → chip appears; second device/web session or realtime check via a second API user posting a reaction → chip updates live; toggle off; verify Edit/Delete gating unchanged.
- [ ] **Step 5: PRs:** TTS → `staging` as DRAFT (auto-deploys on merge); mobile → `main`. Wait for Copilot on both, address comments before done.
