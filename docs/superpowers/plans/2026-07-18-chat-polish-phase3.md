# Chat Polish Phase 3 — Delivered/Seen Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iMessage-style "Delivered" / "Seen 3:42 PM" under your last message in DMs, "Seen by N" (tap for names) in group chats, driven by a new delivered receipt alongside the existing read receipt.

**Architecture:** Backend adds `last_delivered_at` to `conversation_participants`, one bulk ack endpoint (`POST /api/mobile/conversations/delivered` — "my app has received everything up to now"), and a `conversation.delivered` stream event mirroring `conversation.read`. The ack only touches (and only broadcasts for) conversations that actually have newer messages, so routine app-opens don't spam the stream. Mobile fires the ack after every successful conversations-list fetch — because realtime message arrival already invalidates that provider, this single hook covers both spec triggers (app open AND message received). Status display is a pure derivation over `(message, participants)`.

**Tech Stack:** Laravel (TTS) + Flutter/Riverpod. No new packages.

**Spec:** `docs/superpowers/specs/2026-07-18-chat-polish-design.md` (Phase 3 — wire contract FROZEN except as noted: the ack endpoint is refined to only update/broadcast conversations with undelivered messages, which is an optimization within the spec's semantics).

## Global Constraints

- **Repos/branches (already created):** TTS `feat/chat-delivery-receipts` off staging 31d3963f (PR → staging, DRAFT); mobile `feat/chat-delivery-status` off main 08290e1 (PR → main).
- **Backend commands ALWAYS via `docker compose exec app ...`;** backend tasks implemented by the `laravel-mobile-api-dev` agent.
- **Frozen wire contract:**
  - `conversation_participants.last_delivered_at` nullable timestamp; participants JSON gains `"last_delivered_at": <ISO8601|null>`.
  - `POST /api/mobile/conversations/delivered` (no body) → 204. Sets `last_delivered_at = now()` on the caller's participant rows **for conversations that have at least one message newer than the current `last_delivered_at`** (others untouched). For each updated row, broadcasts `conversation.delivered` `{user_id, last_delivered_at}` on `private-conversation.{id}`, `toOthers()` — exactly mirroring `conversation.read`.
  - Timestamps ISO8601 on the wire, like `last_read_at`.
  - Display semantics (mobile, newest own message only): DM → "Seen <time>" when the other participant's `last_read_at >= message.created_at`, else "Delivered" when their `last_delivered_at >= message.created_at`, else nothing. Group → "Seen by N" (count of OTHER participants with `last_read_at >= created_at`, N > 0), tap shows those participants' names. Delivered is NOT shown in groups (spec).
- Read receipts already advance-only; the delivered ack is advance-only by construction (only rows with newer messages are touched, set to `now()`).
- Cupertino widgets; text colors via `context.secondaryText`/`context.tertiaryText`; pure time/status functions take explicit inputs (no live clock inside), tests pin all times; far-past years for any date-format-sensitive fixtures.
- Hand-written fromJson; no codegen; no version bumps.
- Mobile analyze baseline: 4 known items. Never `git add -A` in either repo.

---

### Task B1: Backend — last_delivered_at column + participants serialization

**Repo:** `/home/eddie/github/TTS`, branch `feat/chat-delivery-receipts` (checked out).

**Files:**
- Create: `database/migrations/2026_07_18_000002_add_last_delivered_at_to_conversation_participants.php`
- Modify: `app/Models/ConversationParticipant.php` (fillable + casts)
- Modify: `app/Http/Controllers/Api/Mobile/ConversationsController.php:303-309` (`threadPage()` participants map)
- Test: `tests/Feature/Api/Mobile/Chat/DeliveredReceiptTest.php` (new)

**Interfaces:**
- Produces (B2/mobile rely on): participants wire objects gain `last_delivered_at` (ISO8601 or null); `ConversationParticipant` has `last_delivered_at` datetime cast.

- [ ] **Step 1: Write failing tests**

Create `tests/Feature/Api/Mobile/Chat/DeliveredReceiptTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile\Chat;

use App\Models\ConversationParticipant;
use App\Services\Chat\ConversationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

class DeliveredReceiptTest extends TestCase
{
    use RefreshDatabase;
    use ChatTestHelpers;

    protected function setUp(): void
    {
        parent::setUp();
        Queue::fake();
    }

    public function test_thread_participants_include_last_delivered_at(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $dm->messages()->create(['user_id' => $owner->id, 'body' => 'hi']);

        ConversationParticipant::where('conversation_id', $dm->id)
            ->where('user_id', $member->id)
            ->update(['last_delivered_at' => '2026-01-02 03:04:05']);

        $response = $this->actingAs($owner)
            ->getJson("/api/mobile/conversations/{$dm->id}/messages")
            ->assertOk();

        $participants = collect($response->json('participants'));
        $other = $participants->firstWhere('user_id', $member->id);
        $this->assertNotNull($other['last_delivered_at']);
        $this->assertStringStartsWith('2026-01-02T03:04:05', $other['last_delivered_at']);
        $me = $participants->firstWhere('user_id', $owner->id);
        $this->assertNull($me['last_delivered_at']);
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/DeliveredReceiptTest.php`
Expected: FAIL — column doesn't exist / key missing from participants JSON.

- [ ] **Step 3: Implement**

Migration:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('conversation_participants', function (Blueprint $table) {
            $table->timestamp('last_delivered_at')->nullable()->after('last_read_at');
        });
    }

    public function down(): void
    {
        Schema::table('conversation_participants', function (Blueprint $table) {
            $table->dropColumn('last_delivered_at');
        });
    }
};
```

`ConversationParticipant`: add `'last_delivered_at'` to `$fillable`; casts becomes `['last_read_at' => 'datetime', 'last_delivered_at' => 'datetime']`.

`threadPage()` participants map gains, after `last_read_at`:

```php
        'last_delivered_at' => $p->last_delivered_at?->toIso8601String(),
```

Run `docker compose exec app php artisan migrate`.

- [ ] **Step 4: Verify green + suite**

Run: `docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/` — new test passes, all existing green.

- [ ] **Step 5: Commit**

```bash
git add database/migrations/2026_07_18_000002_add_last_delivered_at_to_conversation_participants.php app/Models/ConversationParticipant.php app/Http/Controllers/Api/Mobile/ConversationsController.php tests/Feature/Api/Mobile/Chat/DeliveredReceiptTest.php
git commit -m "feat(chat): last_delivered_at on conversation participants"
```

---

### Task B2: Backend — bulk delivered ack + conversation.delivered broadcast

**Files:**
- Modify: `app/Http/Controllers/Api/Mobile/ConversationsController.php` (new `delivered()` method)
- Modify: `routes/api.php` (chat block — NOTE: register BEFORE the `/conversations/{conversation}` wildcard routes so 'delivered' isn't captured as a route param)
- Modify: `app/Events/ConversationStreamEvent.php` (docblock only: document the new type)
- Test: `tests/Feature/Api/Mobile/Chat/DeliveredReceiptTest.php` (append)

**Interfaces:**
- Consumes (B1): `last_delivered_at` on `ConversationParticipant`.
- Produces (mobile relies on): `POST /api/mobile/conversations/delivered` → 204; `conversation.delivered` `{user_id, last_delivered_at}` broadcast per affected conversation.

- [ ] **Step 1: Write failing tests**

Append to `DeliveredReceiptTest.php` (add `use App\Events\ConversationStreamEvent;` and `use Illuminate\Support\Facades\Event;`):

```php
    public function test_bulk_ack_stamps_only_conversations_with_newer_messages(): void
    {
        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $service = app(ConversationService::class);
        $withNew = $service->dmBetween($owner, $member);
        $channel = $service->bandChannelFor($band); // no messages → untouched

        $withNew->messages()->create(['user_id' => $owner->id, 'body' => 'undelivered']);

        $this->actingAs($member)
            ->postJson('/api/mobile/conversations/delivered')
            ->assertStatus(204);

        $stamped = ConversationParticipant::where('conversation_id', $withNew->id)
            ->where('user_id', $member->id)->first();
        $this->assertNotNull($stamped->last_delivered_at);

        $untouched = ConversationParticipant::where('conversation_id', $channel->id)
            ->where('user_id', $member->id)->first();
        $this->assertNull($untouched?->last_delivered_at);

        // Owner's own rows are not the caller's — never stamped by member's ack.
        $ownerRow = ConversationParticipant::where('conversation_id', $withNew->id)
            ->where('user_id', $owner->id)->first();
        $this->assertNull($ownerRow?->last_delivered_at);
    }

    public function test_bulk_ack_broadcasts_delivered_per_affected_conversation(): void
    {
        Event::fake([ConversationStreamEvent::class]);

        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $dm->messages()->create(['user_id' => $owner->id, 'body' => 'undelivered']);

        $this->actingAs($member)->postJson('/api/mobile/conversations/delivered')->assertStatus(204);

        Event::assertDispatched(ConversationStreamEvent::class, function ($event) use ($dm, $member) {
            return $event->broadcastAs() === 'conversation.delivered'
                && $event->conversationId === $dm->id
                && $event->broadcastWith()['user_id'] === $member->id
                && is_string($event->broadcastWith()['last_delivered_at']);
        });
    }

    public function test_bulk_ack_is_noop_and_silent_when_nothing_new(): void
    {
        Event::fake([ConversationStreamEvent::class]);

        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        $dm->messages()->create(['user_id' => $owner->id, 'body' => 'old']);

        // First ack stamps; second ack (nothing newer) must not broadcast again.
        $this->actingAs($member)->postJson('/api/mobile/conversations/delivered')->assertStatus(204);
        $this->actingAs($member)->postJson('/api/mobile/conversations/delivered')->assertStatus(204);

        Event::assertDispatchedTimes(ConversationStreamEvent::class, 1);
    }

    public function test_own_messages_do_not_require_delivery(): void
    {
        Event::fake([ConversationStreamEvent::class]);

        [$owner, $band] = $this->makeOwnerWithBand();
        $member = $this->makeMember($band);
        $dm = app(ConversationService::class)->dmBetween($owner, $member);
        // Only the caller's OWN message exists — acking your own send is pointless churn.
        $dm->messages()->create(['user_id' => $member->id, 'body' => 'mine']);

        $this->actingAs($member)->postJson('/api/mobile/conversations/delivered')->assertStatus(204);

        Event::assertNotDispatched(ConversationStreamEvent::class);
    }
```

- [ ] **Step 2: Run to verify failure**

Expected: 404s (route absent); B1 test still green.

- [ ] **Step 3: Implement**

In `ConversationsController`, next to `read()`:

```php
    /**
     * POST /api/mobile/conversations/delivered — bulk delivery ack.
     * "My app has received everything up to now": stamps last_delivered_at
     * on the caller's participant rows, but only for conversations holding a
     * message from someone else newer than the current stamp — routine
     * app-opens with nothing new write nothing and broadcast nothing.
     */
    public function delivered(Request $request): \Illuminate\Http\Response
    {
        $user = $request->user();
        $now = now();

        $rows = ConversationParticipant::query()
            ->where('user_id', $user->id)
            ->whereExists(function ($query) use ($user) {
                $query->selectRaw('1')
                    ->from('messages')
                    ->whereColumn('messages.conversation_id', 'conversation_participants.conversation_id')
                    ->where('messages.user_id', '!=', $user->id)
                    ->whereNull('messages.deleted_at')
                    ->where(function ($q) {
                        $q->whereNull('conversation_participants.last_delivered_at')
                            ->orWhereColumn('messages.created_at', '>', 'conversation_participants.last_delivered_at');
                    });
            })
            ->get();

        foreach ($rows as $participant) {
            $participant->forceFill(['last_delivered_at' => $now])->save();
            broadcast(new ConversationStreamEvent($participant->conversation_id, 'conversation.delivered', [
                'user_id' => $user->id,
                'last_delivered_at' => $now->toIso8601String(),
            ]))->toOthers();
        }

        return response()->noContent();
    }
```

Route (in the chat block, ABOVE any `/conversations/{conversation}` routes):

```php
        Route::post('/conversations/delivered', [App\Http\Controllers\Api\Mobile\ConversationsController::class, 'delivered'])->name('mobile.conversations.delivered');
```

`ConversationStreamEvent` docblock: add `conversation.delivered {user_id, last_delivered_at}` to the wire-types list.

- [ ] **Step 4: Verify green + full chat suite**

`docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/` — all green.

- [ ] **Step 5: Commit**

```bash
git add app/Http/Controllers/Api/Mobile/ConversationsController.php routes/api.php app/Events/ConversationStreamEvent.php tests/Feature/Api/Mobile/Chat/DeliveredReceiptTest.php
git commit -m "feat(chat): bulk delivered ack with conversation.delivered streaming"
```

---

### Task M3: Mobile — participant field, ack call, realtime case

**Repo:** `/home/eddie/github/tts_bandmate`, branch `feat/chat-delivery-status`.

**Files:**
- Modify: `lib/features/chat/data/models/chat_participant.dart`
- Modify: `lib/core/network/api_endpoints.dart` (chat block)
- Modify: `lib/features/chat/data/chat_repository.dart`
- Modify: `lib/features/chat/providers/conversations_provider.dart` (post-fetch ack)
- Modify: `lib/features/chat/providers/chat_thread_provider.dart` ('conversation.delivered' case)
- Test: `test/features/chat/models_test.dart`, `test/features/chat/chat_repository_test.dart`, `test/features/chat/conversations_provider_test.dart`, `test/features/chat/chat_thread_provider_test.dart` (append each)

**Interfaces:**
- Produces (M4 relies on): `ChatParticipant.deliveredAt` (`DateTime?`, wire `last_delivered_at`) + `copyWith({DateTime? lastReadAt, DateTime? deliveredAt})`; `ChatRepository.markDelivered()`; thread state participants patched live by `conversation.delivered`.

- [ ] **Step 1: Write failing tests**

`models_test.dart`:

```dart
  test('ChatParticipant parses and copies last_delivered_at', () {
    final p = ChatParticipant.fromJson({
      'user_id': 3,
      'name': 'Sam',
      'last_read_at': '2020-07-12T14:00:00Z',
      'last_delivered_at': '2020-07-12T15:00:00Z',
    });
    expect(p.deliveredAt, DateTime.parse('2020-07-12T15:00:00Z'));
    expect(p.copyWith(deliveredAt: DateTime.parse('2020-07-13T00:00:00Z')).deliveredAt,
        DateTime.parse('2020-07-13T00:00:00Z'));
    expect(p.copyWith(lastReadAt: DateTime.parse('2020-07-13T00:00:00Z')).deliveredAt,
        p.deliveredAt); // untouched fields carry over
  });
```

`chat_repository_test.dart`:

```dart
  test('markDelivered posts the bulk ack', () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, {}));

    await repo.markDelivered();

    expect(captured.single.method, 'POST');
    expect(captured.single.path, '/api/mobile/conversations/delivered');
  });
```

`conversations_provider_test.dart` (follow the file's existing harness):

```dart
  test('successful list fetch fires the bulk delivered ack', () async {
    // Stub: GET conversations returns one conversation; capture all requests.
    // After awaiting chatConversationsProvider.future, assert a POST to
    // /api/mobile/conversations/delivered was captured.
  });

  test('failed list fetch does not ack', () async {
    // Stub GET → 500; await the provider's error; assert no delivered POST.
  });
```

(Assertion sketches — wire per the file's idioms; keep both assertions.)

`chat_thread_provider_test.dart`:

```dart
  test('realtime conversation.delivered patches the participant', () async {
    // Load thread (participants include user 3 with no deliveredAt), then:
    capturedHandler!('conversation.delivered', {
      'user_id': 3,
      'last_delivered_at': '2020-07-12T15:00:00Z',
    });
    final p = container
        .read(chatThreadProvider(5))
        .participants
        .firstWhere((p) => p.userId == 3);
    expect(p.deliveredAt, DateTime.parse('2020-07-12T15:00:00Z'));
  });
```

- [ ] **Step 2: Run to verify failure**

`flutter test test/features/chat/` — new tests fail on missing symbols/behavior.

- [ ] **Step 3: Implement**

`ChatParticipant`: add `this.deliveredAt` (`final DateTime? deliveredAt;`), parse `json['last_delivered_at']` with the same tryParse idiom as `lastReadAt`, and extend `copyWith`:

```dart
  ChatParticipant copyWith({DateTime? lastReadAt, DateTime? deliveredAt}) =>
      ChatParticipant(
        userId: userId,
        name: name,
        avatarUrl: avatarUrl,
        lastReadAt: lastReadAt ?? this.lastReadAt,
        deliveredAt: deliveredAt ?? this.deliveredAt,
      );
```

`api_endpoints.dart` (chat block):

```dart
  static const mobileConversationsDelivered =
      '/api/mobile/conversations/delivered';
```

`chat_repository.dart` (next to `markRead`):

```dart
  /// Bulk delivery ack: "this client has received everything up to now."
  Future<void> markDelivered() =>
      _dio.post<void>(ApiEndpoints.mobileConversationsDelivered);
```

`conversations_provider.dart` — ack after a successful fetch, fire-and-forget (an ack failure must never break the list):

```dart
final chatConversationsProvider = FutureProvider<List<Conversation>>((ref) async {
  final repo = ref.watch(chatRepositoryProvider);
  final conversations = await repo.listConversations();
  // Bulk delivered ack: this fetch IS "the app received what the server has".
  // Realtime message arrival invalidates this provider, so the refetch path
  // acks too — one hook covers both app-open and message-received triggers.
  // ignore: unawaited_futures
  repo.markDelivered().catchError((_) {});
  return conversations;
});
```

(Match the file's actual provider shape — if it differs from this sketch, keep its structure and add the two ack lines after the fetch.)

`chat_thread_provider.dart` — in `_onChannelEvent`, next to `conversation.read` (mirror its parse idiom):

```dart
      case 'conversation.delivered':
        final userId = (data['user_id'] as num?)?.toInt();
        final at = DateTime.tryParse(data['last_delivered_at'] as String? ?? '');
        if (userId == null || at == null) return;
        state = state.copyWith(participants: [
          for (final p in state.participants)
            p.userId == userId ? p.copyWith(deliveredAt: at) : p,
        ]);
```

- [ ] **Step 4: Verify green**

`flutter test test/features/chat/` all green; `flutter analyze` baseline only.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/data/models/chat_participant.dart lib/core/network/api_endpoints.dart lib/features/chat/data/chat_repository.dart lib/features/chat/providers/conversations_provider.dart lib/features/chat/providers/chat_thread_provider.dart test/features/chat/models_test.dart test/features/chat/chat_repository_test.dart test/features/chat/conversations_provider_test.dart test/features/chat/chat_thread_provider_test.dart
git commit -m "feat(chat): delivered receipts — participant field, bulk ack, realtime patch"
```

---

### Task M4: Mobile — status derivation + status line UI

**Files:**
- Modify: `lib/features/chat/providers/chat_thread_provider.dart` (derivation helpers next to `seenByOthersCount`)
- Modify: `lib/features/chat/screens/conversation_thread_screen.dart` (status line replaces the bare 'Seen' label)
- Test: `test/features/chat/chat_thread_provider_test.dart` + `test/features/chat/conversation_thread_screen_test.dart` (append)

**Interfaces:**
- Consumes (M3): `ChatParticipant.deliveredAt`; (existing): `seenByOthersCount`, `bubbleTimeLabel` from `../utils/message_time.dart`.
- Produces: `DmMessageStatus dmMessageStatus(ChatMessage, List<ChatParticipant>, int currentUserId)` and `List<String> seenByNames(ChatMessage, List<ChatParticipant>, int currentUserId)`.

- [ ] **Step 1: Write failing tests**

`chat_thread_provider_test.dart`:

```dart
  group('dmMessageStatus', () {
    final msg = ChatMessage.fromJson({
      'id': 1,
      'conversation_id': 5,
      'user_id': 2,
      'body': 'hi',
      'created_at': '2020-07-12T14:00:00Z',
    });
    ChatParticipant other({String? read, String? delivered}) =>
        ChatParticipant.fromJson({
          'user_id': 3,
          'name': 'Sam',
          'last_read_at': read,
          'last_delivered_at': delivered,
        });

    test('none when the other participant has neither receipt', () {
      expect(dmMessageStatus(msg, [other()], 2), DmMessageStatus.none);
    });

    test('delivered when delivered at/after created but not read', () {
      expect(
        dmMessageStatus(msg, [other(delivered: '2020-07-12T14:00:00Z')], 2),
        DmMessageStatus.delivered,
      );
    });

    test('seen wins over delivered', () {
      expect(
        dmMessageStatus(
            msg,
            [other(read: '2020-07-12T14:30:00Z', delivered: '2020-07-12T14:00:00Z')],
            2),
        DmMessageStatus.seen,
      );
    });

    test('receipts older than the message do not count', () {
      expect(
        dmMessageStatus(
            msg,
            [other(read: '2020-07-12T13:00:00Z', delivered: '2020-07-12T13:30:00Z')],
            2),
        DmMessageStatus.none,
      );
    });
  });

  test('seenByNames lists other readers only', () {
    final msg = ChatMessage.fromJson({
      'id': 1,
      'conversation_id': 5,
      'user_id': 2,
      'body': 'hi',
      'created_at': '2020-07-12T14:00:00Z',
    });
    final participants = [
      ChatParticipant.fromJson({'user_id': 2, 'name': 'Me', 'last_read_at': '2020-07-12T15:00:00Z'}),
      ChatParticipant.fromJson({'user_id': 3, 'name': 'Sam', 'last_read_at': '2020-07-12T15:00:00Z'}),
      ChatParticipant.fromJson({'user_id': 4, 'name': 'Kim', 'last_read_at': '2020-07-12T13:00:00Z'}),
    ];
    expect(seenByNames(msg, participants, 2), ['Sam']);
  });
```

`conversation_thread_screen_test.dart` (sketches — wire per the file's harness, keep every expect):

```dart
  testWidgets('DM shows Delivered then upgrades to Seen with time', (tester) async {
    // Thread page: dm, own last message created 2020-07-12T14:00:00Z, other
    // participant has last_delivered_at 14:30, no last_read_at.
    expect(find.text('Delivered'), findsOneWidget);

    // Realtime read receipt arrives:
    handler!('conversation.read', {'user_id': 3, 'last_read_at': '2020-07-12T15:00:00Z'});
    await tester.pump();
    expect(find.text('Delivered'), findsNothing);
    expect(find.textContaining('Seen'), findsOneWidget); // 'Seen <time>' — time is tz-dependent, assert prefix only
  });

  testWidgets('group shows Seen by N and tap lists names', (tester) async {
    // Band conversation, own last message, two other participants with
    // last_read_at >= created, one without.
    expect(find.text('Seen by 2'), findsOneWidget);
    await tester.tap(find.text('Seen by 2'));
    await tester.pumpAndSettle();
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Kim'), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify failure**

New tests fail on missing `DmMessageStatus`/`seenByNames`/UI.

- [ ] **Step 3: Implement**

In `chat_thread_provider.dart`, next to `seenByOthersCount`:

```dart
enum DmMessageStatus { none, delivered, seen }

/// DM status for [message] (assumed the caller's own): Seen beats Delivered;
/// a receipt only counts if it is at/after the message's creation.
DmMessageStatus dmMessageStatus(
  ChatMessage message,
  List<ChatParticipant> participants,
  int currentUserId,
) {
  var delivered = false;
  for (final p in participants) {
    if (p.userId == currentUserId) continue;
    if (p.lastReadAt != null && !p.lastReadAt!.isBefore(message.createdAt)) {
      return DmMessageStatus.seen;
    }
    if (p.deliveredAt != null && !p.deliveredAt!.isBefore(message.createdAt)) {
      delivered = true;
    }
  }
  return delivered ? DmMessageStatus.delivered : DmMessageStatus.none;
}

/// Names of the OTHER participants who have read [message].
List<String> seenByNames(
  ChatMessage message,
  List<ChatParticipant> participants,
  int currentUserId,
) =>
    [
      for (final p in participants)
        if (p.userId != currentUserId &&
            p.lastReadAt != null &&
            !p.lastReadAt!.isBefore(message.createdAt))
          p.name,
    ];
```

In `conversation_thread_screen.dart`: replace the `showSeen` bool param with a status widget. In the itemBuilder, for the last own message compute:

```dart
                        final isDm = state.conversation?.type == 'dm';
                        Widget? status;
                        if (isLast && message.userId == currentUserId) {
                          if (isDm) {
                            final other = state.participants
                                .where((p) => p.userId != currentUserId)
                                .toList();
                            switch (dmMessageStatus(
                                message, state.participants, currentUserId)) {
                              case DmMessageStatus.seen:
                                final at = other.isEmpty
                                    ? null
                                    : other.first.lastReadAt;
                                status = _StatusLabel(
                                  text: at == null
                                      ? 'Seen'
                                      : 'Seen ${bubbleTimeLabel(at, now: DateTime.now())}',
                                );
                              case DmMessageStatus.delivered:
                                status = const _StatusLabel(text: 'Delivered');
                              case DmMessageStatus.none:
                                status = null;
                            }
                          } else {
                            final names = seenByNames(
                                message, state.participants, currentUserId);
                            if (names.isNotEmpty) {
                              status = _StatusLabel(
                                text: 'Seen by ${names.length}',
                                onTap: () => _showSeenByNames(names),
                              );
                            }
                          }
                        }
```

Pass `status: status` into `_MessageBubble` (replacing `showSeen`); the bubble renders it where the old 'Seen' text was:

```dart
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: status,
          ),
```

`_StatusLabel` + names sheet:

```dart
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.text, this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Text(
          text,
          style: TextStyle(fontSize: 11, color: context.tertiaryText),
        ),
      );
}
```

```dart
  void _showSeenByNames(List<String> names) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Seen by'),
        actions: [
          for (final name in names)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(name),
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

Delete the now-unused `showSeen` param and its call-site wiring (the old `seenByOthersCount(...) > 0` condition — `seenByOthersCount` itself stays, group status uses names count; if it becomes fully unused after this change, keep it only if still referenced, otherwise remove it and its import sites, noting the removal).

- [ ] **Step 4: Verify green**

`flutter test test/features/chat/` all green (update any pre-existing test that asserted the bare 'Seen' label — note in report); `flutter analyze` baseline only.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/providers/chat_thread_provider.dart lib/features/chat/screens/conversation_thread_screen.dart test/features/chat/chat_thread_provider_test.dart test/features/chat/conversation_thread_screen_test.dart
git commit -m "feat(chat): delivered/seen status line for DMs and seen-by count for groups"
```

---

### Task T5: Full verification, PRs, on-device

- [ ] **Step 1:** Mobile `flutter analyze` + `flutter test` (all green); TTS `docker compose exec app php artisan test tests/Feature/Api/Mobile/Chat/`.
- [ ] **Step 2:** Final whole-branch reviews (both repos), one fix wave if needed.
- [ ] **Step 3: On-device** (local backend migrated on the TTS branch): send a DM message as the device user; ack delivered as the other user via API (`POST /conversations/delivered` with their token) → 'Delivered' appears (after thread refresh; realtime is off on local debug builds); mark read via API → 'Seen <time>'; group thread → 'Seen by N' + tap names sheet.
- [ ] **Step 4: PRs:** TTS → staging DRAFT; mobile → main; Copilot both, address comments.
