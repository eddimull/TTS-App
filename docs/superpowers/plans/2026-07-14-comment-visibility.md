# Comment Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make comments discoverable: a pinned comment bar on the event/rehearsal/booking detail screens, and an unread-comment badge on dashboard event cards.

**Architecture:** Flutter side adds a `CommentBar` docked under each detail screen's scroll view (data from the existing `topicThreadProvider`) and an `unreadCommentCount` on `EventSummary` rendered as a badge on `EventCard`. Laravel side adds `unread_comment_count` to the mobile dashboard payload via a new batch `TopicUnreadService` reusing the conversations-list unread query pattern.

**Tech Stack:** Flutter/Cupertino + Riverpod v2 (repo `/home/eddie/github/tts_bandmate`), Laravel (repo `/home/eddie/github/TTS`).

**Spec:** `docs/superpowers/specs/2026-07-14-comment-visibility-design.md`

## Global Constraints

- Flutter repo: `/home/eddie/github/tts_bandmate`, work on branch `feat/comment-visibility` (already created off `origin/main`). PR base: `main`.
- Laravel repo: `/home/eddie/github/TTS`. Create branch `feat/dashboard-unread-comments` off `origin/staging`. PR base: `staging`.
- NEVER run `php`/`artisan`/`composer`/`phpunit` on the host — always `docker compose exec app …` from `/home/eddie/github/TTS`.
- Wire contract: dashboard event objects gain integer `unread_comment_count`; a missing field means 0 on the client. Field name is frozen — both repos must match exactly.
- Dark-mode text colors: use `context.primaryText` / `context.secondaryText` (from `package:tts_bandmate/core/theme/context_colors.dart`), never raw `CupertinoColors.secondaryLabel` in a `color:`.
- Flutter tests: `flutter test <path>` from the repo root. Full checks: `flutter analyze` + `flutter test`.
- Version bump (mobile repo): `pubspec.yaml` `version: 1.12.0+21` → `1.13.0+22` in the final task. If `main` has moved past 1.12.0+21 by merge time, bump minor+build relative to whatever `main` then has.
- Git commit trailer for every commit:

```
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FnL2YXi9EN1yBaKYVuMvKm
```

---

## Part A — Flutter (`/home/eddie/github/tts_bandmate`)

### Task 1: `CommentBar` + `CommentBarBody` widget

**Files:**
- Create: `lib/features/chat/widgets/comment_bar.dart`
- Test: `test/features/chat/comment_bar_test.dart`

**Interfaces:**
- Consumes: `topicThreadProvider` / `TopicRef` from `lib/features/chat/providers/topic_thread_provider.dart`; `ThreadPage` record (`conversation`, `messages`, …) from `lib/features/chat/data/chat_repository.dart`; `ChatMessage` from `lib/features/chat/data/models/chat_message.dart`.
- Produces: `CommentBarBody({required TopicRef topic, required Widget child})` and `CommentBar({required TopicRef topic})`. The file re-exports `TopicRef` and `topicThreadProvider` (Tasks 2–5 import this file).

- [ ] **Step 1: Write the failing test**

Create `test/features/chat/comment_bar_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/widgets/comment_bar.dart';

import '../../helpers/test_harness.dart';

void main() {
  Map<String, dynamic> threadBody({
    List<Map<String, dynamic>> messages = const [],
    int unread = 0,
  }) =>
      {
        'conversation': {
          'id': 5,
          'type': 'topic',
          'title': 'Gig at Blue Room',
          'unread_count': unread,
        },
        'messages': messages,
        'participants': [],
        'channel': 'private-conversation.5',
        'has_more': false,
      };

  Map<String, dynamic> message(int id, String name, String body) => {
        'id': id,
        'conversation_id': 5,
        'user_id': id,
        'user_name': name,
        'body': body,
        'created_at': '2026-07-12T14:0$id:00Z',
      };

  ProviderContainer containerWith(
      Future<ResponseBody> Function(RequestOptions) handler) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter(handler);
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Widget host(ProviderContainer container) => UncontrolledProviderScope(
        container: container,
        child: const CupertinoApp(
          home: CupertinoPageScaffold(
            child: CommentBarBody(
              topic: TopicRef(kind: 'events', idOrKey: 'abc123'),
              child: SizedBox.expand(),
            ),
          ),
        ),
      );

  /// All RichText content flattened — Icon renders through RichText too, so
  /// individual find.byType(RichText) matches are ambiguous.
  String allRichText(WidgetTester tester) => tester
      .widgetList<RichText>(find.byType(RichText))
      .map((r) => r.text.toPlainText())
      .join('\n');

  testWidgets('shows the latest comment and the unread badge', (tester) async {
    final container = containerWith((_) async => json(
        200,
        threadBody(messages: [
          message(1, 'Eddie', 'sound check at 6'),
          message(2, 'Pat', 'see you at 6'),
        ], unread: 2)));

    await tester.pumpWidget(host(container));
    await tester.pumpAndSettle();

    expect(allRichText(tester), contains('Pat: see you at 6'));
    expect(allRichText(tester), isNot(contains('Eddie: sound check')));
    expect(find.text('2'), findsOneWidget); // unread badge
  });

  testWidgets('empty thread shows Add a comment…', (tester) async {
    final container = containerWith((_) async => json(200, threadBody()));

    await tester.pumpWidget(host(container));
    await tester.pumpAndSettle();

    expect(find.text('Add a comment…'), findsOneWidget);
  });

  testWidgets('load failure shows quiet retry row; tap retries', (tester) async {
    var calls = 0;
    final container = containerWith((_) async {
      calls++;
      if (calls == 1) return json(500, {'message': 'boom'});
      return json(200, threadBody(messages: [message(1, 'Eddie', 'hi')]));
    });

    await tester.pumpWidget(host(container));
    await tester.pumpAndSettle();
    expect(find.text('Comments unavailable — tap to retry'), findsOneWidget);

    await tester.tap(find.text('Comments unavailable — tap to retry'));
    await tester.pumpAndSettle();
    expect(allRichText(tester), contains('Eddie: hi'));
  });

  testWidgets('renders a shell while loading (no layout jump)', (tester) async {
    final container = containerWith((_) async => json(200, threadBody()));

    await tester.pumpWidget(host(container));
    // First frame only — the stubbed response hasn't resolved yet.
    expect(find.text('Comments'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/comment_bar_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package ... comment_bar.dart` (file doesn't exist).

- [ ] **Step 3: Write the implementation**

Create `lib/features/chat/widgets/comment_bar.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/chat_message.dart';
import '../providers/topic_thread_provider.dart';

export '../providers/topic_thread_provider.dart' show TopicRef, topicThreadProvider;

/// Detail-screen body wrapper: hosts the scrollable content and docks a
/// [CommentBar] beneath it so the comments entry point stays visible
/// regardless of scroll position.
class CommentBarBody extends StatelessWidget {
  const CommentBarBody({super.key, required this.topic, required this.child});

  final TopicRef topic;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(child: child),
          CommentBar(topic: topic),
        ],
      );
}

/// Pinned comment bar: 💬 icon, one-line latest comment, unread badge, and a
/// chevron. Tapping opens the full thread screen. Always rendered — an empty
/// thread shows "Add a comment…" so the feature stays discoverable.
class CommentBar extends ConsumerWidget {
  const CommentBar({super.key, required this.topic});

  final TopicRef topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(topicThreadProvider(topic));

    final content = pageAsync.when(
      loading: () => _BarRow(
        child: Text('Comments',
            style: TextStyle(fontSize: 14, color: context.secondaryText)),
      ),
      // Comments are secondary content on a detail screen — a load failure
      // stays quiet and recoverable instead of blocking the page.
      error: (_, __) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.invalidate(topicThreadProvider(topic)),
        child: _BarRow(
          child: Text('Comments unavailable — tap to retry',
              style: TextStyle(fontSize: 14, color: context.secondaryText)),
        ),
      ),
      data: (page) {
        final latest = page.messages.isEmpty ? null : page.messages.last;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push(
            '/conversations/${page.conversation.id}',
            extra: {'title': page.conversation.title},
          ),
          child: _BarRow(
            unread: page.conversation.unreadCount,
            showChevron: true,
            child: latest == null
                ? Text('Add a comment…',
                    style:
                        TextStyle(fontSize: 14, color: context.secondaryText))
                : RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style:
                          TextStyle(fontSize: 14, color: context.primaryText),
                      children: [
                        TextSpan(
                          text: '${latest.userName}: ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: _previewText(latest)),
                      ],
                    ),
                  ),
          ),
        );
      },
    );

    return Container(
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).barBackgroundColor,
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(top: false, child: content),
    );
  }

  static String _previewText(ChatMessage m) {
    if (m.isDeleted) return 'Message deleted';
    if (m.body.isEmpty && m.attachments.isNotEmpty) return '📷 Photo';
    return m.body;
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow(
      {required this.child, this.unread = 0, this.showChevron = false});

  final Widget child;
  final int unread;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(CupertinoIcons.chat_bubble,
              size: 18, color: context.secondaryText),
          const SizedBox(width: 8),
          Expanded(child: child),
          if (unread > 0) _UnreadBadge(count: unread),
          if (showChevron) ...[
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_right,
                size: 14, color: context.secondaryText),
          ],
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed.resolveFrom(context),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: CupertinoColors.white,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/comment_bar_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/widgets/comment_bar.dart test/features/chat/comment_bar_test.dart
git commit -m "feat(chat): pinned CommentBar widget for detail screens"
```

---

### Task 2: Adopt CommentBar on the event detail screen

**Files:**
- Modify: `lib/features/events/screens/event_detail_screen.dart:18` (import), `:114` (ListView wrap), `:261` (remove CommentsSection)
- Test: existing `test/features/events/` suite

**Interfaces:**
- Consumes: `CommentBarBody`, `TopicRef` from `../../chat/widgets/comment_bar.dart` (Task 1).
- Produces: nothing new.

- [ ] **Step 1: Swap the import**

Line 18, replace:

```dart
import '../../chat/widgets/comments_section.dart';
```

with:

```dart
import '../../chat/widgets/comment_bar.dart';
```

- [ ] **Step 2: Wrap the ListView and drop the inline section**

In `_EventDetailView.build` (line 114), change:

```dart
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
```

to:

```dart
      child: CommentBarBody(
        topic: TopicRef(kind: 'events', idOrKey: event.key),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
```

Close the new parenthesis at the ListView's end (line ~265: `],\n      ),` becomes `],\n        ),\n      ),`) and re-indent the ListView children two spaces deeper. Delete the line (261):

```dart
          CommentsSection(kind: 'events', idOrKey: event.key),
```

(keep the trailing `const SizedBox(height: 32),`).

- [ ] **Step 3: Run the events tests**

Run: `flutter test test/features/events/`
Expected: PASS. (`event_detail_contact_navigation_test.dart` imports `comments_section.dart` for `TopicRef` — that still exists until Task 5, so it compiles.)

- [ ] **Step 4: Commit**

```bash
git add lib/features/events/screens/event_detail_screen.dart
git commit -m "feat(events): pinned comment bar on event detail"
```

---

### Task 3: Adopt CommentBar on the rehearsal detail screen

**Files:**
- Modify: `lib/features/rehearsals/screens/rehearsal_detail_screen.dart:13` (import), `:337-338` (SafeArea/ListView wrap), `:486` (remove CommentsSection)
- Test: existing `test/features/rehearsals/` suite

**Interfaces:**
- Consumes: `CommentBarBody`, `TopicRef` from `../../chat/widgets/comment_bar.dart`.

- [ ] **Step 1: Swap the import**

Line 13: `import '../../chat/widgets/comments_section.dart';` → `import '../../chat/widgets/comment_bar.dart';`

- [ ] **Step 2: Wrap the body**

Lines 337–338, change:

```dart
      child: SafeArea(
        child: ListView(
```

to:

```dart
      child: CommentBarBody(
        topic: TopicRef(kind: 'rehearsals', idOrKey: '${rehearsal.id}'),
        child: SafeArea(
          bottom: false, // CommentBar owns the bottom inset
          child: ListView(
```

Re-indent and close the extra parenthesis at the SafeArea's end. Delete line 486:

```dart
            CommentsSection(kind: 'rehearsals', idOrKey: '${rehearsal.id}'),
```

- [ ] **Step 3: Run the rehearsals tests**

Run: `flutter test test/features/rehearsals/`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/features/rehearsals/screens/rehearsal_detail_screen.dart
git commit -m "feat(rehearsals): pinned comment bar on rehearsal detail"
```

---

### Task 4: Adopt CommentBar on the booking detail screen

**Files:**
- Modify: `lib/features/bookings/screens/booking_detail_screen.dart:18` (import), `:407-409` (CustomScrollView wrap), `:540-544` (remove CommentsSection)
- Test: existing `test/features/bookings/` suite

**Interfaces:**
- Consumes: `CommentBarBody`, `TopicRef` from `../../chat/widgets/comment_bar.dart`.

- [ ] **Step 1: Swap the import**

Line 18: `import '../../chat/widgets/comments_section.dart';` → `import '../../chat/widgets/comment_bar.dart';`

- [ ] **Step 2: Wrap the scroll view**

Lines 407–409, change:

```dart
      child: CustomScrollView(
        slivers: [
          SliverSafeArea(
```

to:

```dart
      child: CommentBarBody(
        topic: TopicRef(
          kind: 'bookings',
          idOrKey: '${widget.bookingId}',
          bandId: widget.bandId,
        ),
        child: CustomScrollView(
          slivers: [
            SliverSafeArea(
              bottom: false, // CommentBar owns the bottom inset
```

Re-indent, close the extra parenthesis at the CustomScrollView's end. Delete lines 540–544:

```dart
                CommentsSection(
                  kind: 'bookings',
                  idOrKey: '${widget.bookingId}',
                  bandId: widget.bandId,
                ),
```

- [ ] **Step 3: Run the bookings tests**

Run: `flutter test test/features/bookings/`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/features/bookings/screens/booking_detail_screen.dart
git commit -m "feat(bookings): pinned comment bar on booking detail"
```

---

### Task 5: Delete `CommentsSection` and migrate `TopicRef` imports

**Files:**
- Delete: `lib/features/chat/widgets/comments_section.dart`, `test/features/chat/comments_section_test.dart`
- Modify (import swap only): `test/shared/providers/band_realtime_provider_test.dart:13`, `test/features/events/screens/event_detail_contact_navigation_test.dart:7`, `test/features/rehearsals/rehearsal_cancel_widget_test.dart:8`, `test/features/bookings/screens/booking_detail_contract_subtitle_test.dart:9`
- Modify: `test/features/chat/comment_bar_test.dart` (absorb the TopicRef equality test)

**Interfaces:**
- Consumes: nothing.
- Produces: `TopicRef`/`topicThreadProvider` are now imported from `package:tts_bandmate/features/chat/providers/topic_thread_provider.dart` (or via `comment_bar.dart`'s re-export).

- [ ] **Step 1: Swap imports in the four test files**

In each listed test file, replace:

```dart
import 'package:tts_bandmate/features/chat/widgets/comments_section.dart';
```

with:

```dart
import 'package:tts_bandmate/features/chat/providers/topic_thread_provider.dart';
```

- [ ] **Step 2: Move the TopicRef equality test**

Append to `test/features/chat/comment_bar_test.dart` (inside `main()`, after the widget tests):

```dart
  test('TopicRef is value-equal (family cache key)', () {
    expect(const TopicRef(kind: 'events', idOrKey: 'a'),
        const TopicRef(kind: 'events', idOrKey: 'a'));
    expect(
        const TopicRef(kind: 'events', idOrKey: 'a').hashCode,
        const TopicRef(kind: 'events', idOrKey: 'a').hashCode);
  });
```

- [ ] **Step 3: Delete the old widget and its test**

```bash
git rm lib/features/chat/widgets/comments_section.dart test/features/chat/comments_section_test.dart
```

- [ ] **Step 4: Verify nothing references it and the suite passes**

Run: `grep -rn "comments_section\|CommentsSection" lib test` → expected: no matches.
Run: `flutter analyze && flutter test`
Expected: no analyzer issues, all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(chat): remove CommentsSection, superseded by CommentBar"
```

---

### Task 6: `EventSummary.unreadCommentCount`

**Files:**
- Modify: `lib/features/events/data/models/event_summary.dart`
- Test: Create `test/features/events/data/event_summary_test.dart`

**Interfaces:**
- Produces: `EventSummary.unreadCommentCount` (`int`, default 0) — consumed by Task 7.

- [ ] **Step 1: Write the failing test**

Create `test/features/events/data/event_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

void main() {
  Map<String, dynamic> baseJson() => {
        'key': 'evt-1',
        'title': 'Summer Gala',
        'date': '2026-07-20',
      };

  test('parses unread_comment_count', () {
    final e = EventSummary.fromJson({...baseJson(), 'unread_comment_count': 3});
    expect(e.unreadCommentCount, 3);
  });

  test('defaults unread_comment_count to 0 on legacy payloads', () {
    final e = EventSummary.fromJson(baseJson());
    expect(e.unreadCommentCount, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/events/data/event_summary_test.dart`
Expected: FAIL — `The getter 'unreadCommentCount' isn't defined`.

- [ ] **Step 3: Implement**

In `lib/features/events/data/models/event_summary.dart`:

Add to the constructor parameters (after `this.band,`):

```dart
    this.unreadCommentCount = 0,
```

Add the field (after `final BandSummary? band;`):

```dart
  /// Unread comments in this event's topic thread. 0 on legacy payloads
  /// that don't send unread_comment_count.
  final int unreadCommentCount;
```

Add to `fromJson` (after `band: band,`):

```dart
      unreadCommentCount: (json['unread_comment_count'] as num?)?.toInt() ?? 0,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/events/data/event_summary_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/events/data/models/event_summary.dart test/features/events/data/event_summary_test.dart
git commit -m "feat(events): unreadCommentCount on EventSummary"
```

---

### Task 7: Unread badge on `EventCard`

**Files:**
- Modify: `lib/features/dashboard/widgets/event_card.dart` (top row, lines 56–74)
- Test: Create `test/features/dashboard/event_card_test.dart`

**Interfaces:**
- Consumes: `EventSummary.unreadCommentCount` (Task 6).

- [ ] **Step 1: Write the failing test**

Create `test/features/dashboard/event_card_test.dart`. Note: use `eventSource: 'rehearsal'` so `_EventTypeIcon` renders an `Icon` instead of `Image.asset` (no bundled assets in widget tests).

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/widgets/event_card.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

void main() {
  EventSummary event({int unread = 0}) => EventSummary(
        key: 'evt-1',
        title: 'Tuesday Rehearsal',
        date: '2026-07-20',
        eventSource: 'rehearsal',
        unreadCommentCount: unread,
      );

  testWidgets('shows 💬 badge with count when there are unread comments',
      (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(child: EventCard(event: event(unread: 3))),
    ));

    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.chat_bubble_fill), findsOneWidget);
  });

  testWidgets('hides the badge when there are no unread comments',
      (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(child: EventCard(event: event())),
    ));

    expect(find.byIcon(CupertinoIcons.chat_bubble_fill), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/dashboard/event_card_test.dart`
Expected: FAIL — first test can't find the badge icon.

- [ ] **Step 3: Implement**

In `lib/features/dashboard/widgets/event_card.dart`, in the title `Row` (after the `_RosterDot` entry at line ~72), add:

```dart
                        if (event.unreadCommentCount > 0)
                          _UnreadCommentBadge(count: event.unreadCommentCount),
```

Add at the bottom of the file (after `_RosterDot`):

```dart
/// Red pill badge: unread comments in the event's topic thread.
class _UnreadCommentBadge extends StatelessWidget {
  const _UnreadCommentBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed.resolveFrom(context),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.chat_bubble_fill,
              size: 10, color: CupertinoColors.white),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: CupertinoColors.white,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/dashboard/event_card_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/widgets/event_card.dart test/features/dashboard/event_card_test.dart
git commit -m "feat(dashboard): unread-comment badge on event cards"
```

---

### Task 8: Realtime — refresh the dashboard on `message` signals

**Files:**
- Modify: `lib/shared/providers/band_realtime_provider.dart:103-104`
- Modify: `test/shared/providers/band_realtime_provider_test.dart:310-322`

**Interfaces:**
- Consumes: `dashboardProvider` (already imported in `band_realtime_provider.dart:17`).

- [ ] **Step 1: Update the existing test first**

In `test/shared/providers/band_realtime_provider_test.dart` (line 310), extend the expectation:

```dart
  test('message signal invalidates chat + topic + dashboard providers',
      () async {
    final c = makeContainer();
    await activate(c);

    capturedHandler!('band.data-changed',
        {'model': 'message', 'id': 1, 'action': 'created'});
    await Future<void>.delayed(Duration.zero);

    expect(invalidated, containsAll(<ProviderOrFamily>[
      chatConversationsProvider,
      topicThreadProvider,
      dashboardProvider,
    ]));
  });
```

(`dashboardProvider` is already imported in that test file — it's asserted for other signals. Verify; add the import if not.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/providers/band_realtime_provider_test.dart`
Expected: FAIL — `invalidated` doesn't contain `dashboardProvider`.

- [ ] **Step 3: Implement**

In `lib/shared/providers/band_realtime_provider.dart` lines 103–104, change:

```dart
    case 'message':
      return [chatConversationsProvider, topicThreadProvider];
```

to:

```dart
    case 'message':
      // dashboardProvider: keeps EventCard unread-comment badges fresh.
      return [chatConversationsProvider, topicThreadProvider, dashboardProvider];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/providers/band_realtime_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/providers/band_realtime_provider.dart test/shared/providers/band_realtime_provider_test.dart
git commit -m "feat(realtime): refresh dashboard badges on message signals"
```

---

### Task 9: Mobile final verification + version bump

**Files:**
- Modify: `pubspec.yaml:4`

- [ ] **Step 1: Bump the version**

`pubspec.yaml` line 4: `version: 1.12.0+21` → `version: 1.13.0+22`

- [ ] **Step 2: Full analyze + test**

Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml
git commit -m "chore: bump version to 1.13.0+22"
```

---

## Part B — Laravel (`/home/eddie/github/TTS`)

### Task 10: Branch + `TopicUnreadService`

**Files:**
- Create: `app/Services/Chat/TopicUnreadService.php`
- Test: `tests/Feature/Services/Chat/TopicUnreadServiceTest.php`

**Interfaces:**
- Consumes: `App\Models\Conversation` (`TYPE_TOPIC`, `conversable_type`/`conversable_id` morph columns), `App\Models\ConversationParticipant` (`last_read_at`), `App\Models\Message` (soft-deletes), `App\Services\Chat\ConversationService::topicFor()` (test seeding).
- Produces: `TopicUnreadService::unreadCountsForConversables(User $user, array $pairs): array` — pairs are `[class-string, int]`; returns `["{type}:{id}" => count]`, omitting zero-count/no-conversation pairs. Consumed by Task 11.

- [ ] **Step 1: Create the branch**

```bash
git -C /home/eddie/github/TTS fetch origin staging
git -C /home/eddie/github/TTS checkout -b feat/dashboard-unread-comments origin/staging
```

- [ ] **Step 2: Write the failing test**

First read `tests/Feature/Api/Mobile/Chat/ConversationsIndexTest.php` to copy its exact band/user/message seeding helpers (factory names below assume the conventions in that file — align them if they differ). Create `tests/Feature/Services/Chat/TopicUnreadServiceTest.php`:

```php
<?php

namespace Tests\Feature\Services\Chat;

use App\Models\Bands;
use App\Models\Events;
use App\Models\Message;
use App\Models\User;
use App\Services\Chat\ConversationService;
use App\Services\Chat\TopicUnreadService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TopicUnreadServiceTest extends TestCase
{
    use RefreshDatabase;

    public function test_counts_unread_messages_per_conversable(): void
    {
        $band = Bands::factory()->create();
        $reader = User::factory()->create();
        $author = User::factory()->create();
        $event = Events::factory()->create(['band_id' => $band->id]);

        $conversation = app(ConversationService::class)->topicFor($event);
        Message::create([
            'conversation_id' => $conversation->id,
            'user_id' => $author->id,
            'body' => 'load in at 5?',
        ]);
        Message::create([
            'conversation_id' => $conversation->id,
            'user_id' => $author->id,
            'body' => 'anyone?',
        ]);

        $counts = app(TopicUnreadService::class)->unreadCountsForConversables(
            $reader,
            [[Events::class, $event->id]],
        );

        $this->assertSame(
            [Events::class . ':' . $event->id => 2],
            $counts,
        );
    }

    public function test_messages_before_last_read_marker_do_not_count(): void
    {
        $band = Bands::factory()->create();
        $reader = User::factory()->create();
        $author = User::factory()->create();
        $event = Events::factory()->create(['band_id' => $band->id]);

        $conversation = app(ConversationService::class)->topicFor($event);
        Message::create([
            'conversation_id' => $conversation->id,
            'user_id' => $author->id,
            'body' => 'old news',
            'created_at' => now()->subHour(),
        ]);
        $conversation->participants()->create([
            'user_id' => $reader->id,
            'last_read_at' => now()->subMinutes(30),
        ]);
        Message::create([
            'conversation_id' => $conversation->id,
            'user_id' => $author->id,
            'body' => 'fresh',
        ]);

        $counts = app(TopicUnreadService::class)->unreadCountsForConversables(
            $reader,
            [[Events::class, $event->id]],
        );

        $this->assertSame(
            [Events::class . ':' . $event->id => 1],
            $counts,
        );
    }

    public function test_own_messages_and_missing_conversations_are_zero(): void
    {
        $band = Bands::factory()->create();
        $reader = User::factory()->create();
        $event = Events::factory()->create(['band_id' => $band->id]);
        $noThreadEvent = Events::factory()->create(['band_id' => $band->id]);

        $conversation = app(ConversationService::class)->topicFor($event);
        Message::create([
            'conversation_id' => $conversation->id,
            'user_id' => $reader->id,
            'body' => 'my own note',
        ]);

        $counts = app(TopicUnreadService::class)->unreadCountsForConversables(
            $reader,
            [[Events::class, $event->id], [Events::class, $noThreadEvent->id]],
        );

        $this->assertSame([], $counts);
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd /home/eddie/github/TTS && docker compose exec app php artisan test --filter=TopicUnreadServiceTest`
Expected: FAIL — `Class "App\Services\Chat\TopicUnreadService" not found`.

- [ ] **Step 4: Implement**

Create `app/Services/Chat/TopicUnreadService.php`. The two-bucket unread computation mirrors `ConversationsController::prefetchSummaryData()` (with-marker vs no-marker):

```php
<?php

namespace App\Services\Chat;

use App\Models\Conversation;
use App\Models\ConversationParticipant;
use App\Models\Message;
use App\Models\User;

class TopicUnreadService
{
    /**
     * Batch unread counts for topic conversations.
     *
     * @param  array<int, array{0: class-string, 1: int}>  $pairs  conversable
     *         (morph type, id) pairs, e.g. [[Events::class, 12], [Rehearsal::class, 3]]
     * @return array<string, int> keyed "{type}:{id}"; zero-count and
     *         conversation-less pairs are omitted.
     */
    public function unreadCountsForConversables(User $user, array $pairs): array
    {
        if ($pairs === []) {
            return [];
        }

        $conversations = Conversation::query()
            ->where('type', Conversation::TYPE_TOPIC)
            ->where(function ($q) use ($pairs) {
                foreach ($pairs as [$type, $id]) {
                    $q->orWhere(fn ($sub) => $sub
                        ->where('conversable_type', $type)
                        ->where('conversable_id', $id));
                }
            })
            ->get(['id', 'conversable_type', 'conversable_id']);

        if ($conversations->isEmpty()) {
            return [];
        }

        $ids = $conversations->pluck('id');

        // Split by read marker, mirroring ConversationsController::prefetchSummaryData.
        $withMarker = ConversationParticipant::query()
            ->whereIn('conversation_id', $ids)
            ->where('user_id', $user->id)
            ->whereNotNull('last_read_at')
            ->pluck('conversation_id');
        $withoutMarker = $ids->diff($withMarker)->values();

        $notMine = fn ($q) => $q
            ->where('messages.user_id', '!=', $user->id)
            ->orWhereNull('messages.user_id');

        $unread = collect();
        if ($withMarker->isNotEmpty()) {
            $unread = Message::query()
                ->whereIn('messages.conversation_id', $withMarker)
                ->where($notMine)
                ->join('conversation_participants', function ($join) use ($user) {
                    $join->on('conversation_participants.conversation_id', '=', 'messages.conversation_id')
                        ->where('conversation_participants.user_id', '=', $user->id);
                })
                ->whereColumn('messages.created_at', '>', 'conversation_participants.last_read_at')
                ->selectRaw('messages.conversation_id as conversation_id, COUNT(*) as unread')
                ->groupBy('messages.conversation_id')
                ->pluck('unread', 'conversation_id');
        }
        if ($withoutMarker->isNotEmpty()) {
            $unread = $unread->union(
                Message::query()
                    ->whereIn('messages.conversation_id', $withoutMarker)
                    ->where($notMine)
                    ->selectRaw('messages.conversation_id as conversation_id, COUNT(*) as unread')
                    ->groupBy('messages.conversation_id')
                    ->pluck('unread', 'conversation_id'),
            );
        }

        $out = [];
        foreach ($conversations as $c) {
            $count = (int) ($unread[$c->id] ?? 0);
            if ($count > 0) {
                $out["{$c->conversable_type}:{$c->conversable_id}"] = $count;
            }
        }

        return $out;
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=TopicUnreadServiceTest`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add app/Services/Chat/TopicUnreadService.php tests/Feature/Services/Chat/TopicUnreadServiceTest.php
git commit -m "feat(chat): batch topic unread counts service"
```

---

### Task 11: `unread_comment_count` in the dashboard payload

**Files:**
- Modify: `app/Services/Mobile/DashboardFormatter.php` (`normalizeEvent()`, `formatEvents()`; add `conversablePairs()` + `conversableFor()`)
- Modify: `app/Http/Controllers/Api/Mobile/DashboardController.php` (`index()`, `loadOlder()`; inject `TopicUnreadService`)
- Test: Create `tests/Feature/Api/Mobile/DashboardUnreadCommentTest.php`; update `tests/Unit/Services/Mobile/DashboardFormatterTest.php` if its assertions enumerate payload keys

**Interfaces:**
- Consumes: `TopicUnreadService::unreadCountsForConversables()` (Task 10).
- Produces: dashboard payload events gain `'unread_comment_count' => int` (the frozen wire contract); `DashboardFormatter::conversablePairs($events): array` and `formatEvents($events, array $unreadByKey = [])`.

- [ ] **Step 1: Write the failing feature test**

First read `tests/Feature/Api/Mobile/DashboardTest.php` and copy the seeding used by `test_dashboard_returns_events_for_authenticated_user()` (band + member + event in the dashboard window, Sanctum auth). Create `tests/Feature/Api/Mobile/DashboardUnreadCommentTest.php` on that template:

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\Message;
use App\Models\User;
use App\Services\Chat\ConversationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class DashboardUnreadCommentTest extends TestCase
{
    use RefreshDatabase;

    // Seed a band, a member user ($this->user), and one upcoming event
    // ($this->event) exactly as DashboardTest does — copy its setUp/helpers.

    public function test_dashboard_events_include_unread_comment_count(): void
    {
        $author = User::factory()->create();
        $conversation = app(ConversationService::class)->topicFor($this->event);
        Message::create([
            'conversation_id' => $conversation->id,
            'user_id' => $author->id,
            'body' => 'load in at 5?',
        ]);

        $response = $this->actingAs($this->user)->getJson('/api/mobile/dashboard');

        $response->assertOk();
        $row = collect($response->json('events'))
            ->firstWhere('id', $this->event->id);
        $this->assertSame(1, $row['unread_comment_count']);
    }

    public function test_events_without_a_conversation_report_zero(): void
    {
        $response = $this->actingAs($this->user)->getJson('/api/mobile/dashboard');

        $response->assertOk();
        $row = collect($response->json('events'))
            ->firstWhere('id', $this->event->id);
        $this->assertSame(0, $row['unread_comment_count']);
    }

    public function test_read_threads_report_zero(): void
    {
        $author = User::factory()->create();
        $conversation = app(ConversationService::class)->topicFor($this->event);
        Message::create([
            'conversation_id' => $conversation->id,
            'user_id' => $author->id,
            'body' => 'load in at 5?',
        ]);
        $conversation->participants()->create([
            'user_id' => $this->user->id,
            'last_read_at' => now(),
        ]);

        $response = $this->actingAs($this->user)->getJson('/api/mobile/dashboard');

        $response->assertOk();
        $row = collect($response->json('events'))
            ->firstWhere('id', $this->event->id);
        $this->assertSame(0, $row['unread_comment_count']);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=DashboardUnreadCommentTest`
Expected: FAIL — `unread_comment_count` key missing.

- [ ] **Step 3: Implement the formatter changes**

In `app/Services/Mobile/DashboardFormatter.php`:

Add imports for `App\Models\Events` and `App\Models\Rehearsal`.

Add a private helper. **Important:** the rehearsal branch must read the same source field that `normalizeEvent()`'s existing rehearsal branch (lines ~89–97) emits as `id` — inspect that code and reuse its exact expression:

```php
    /**
     * The topic-conversation morph target for a dashboard row, or null when
     * the row can't have one (virtual rehearsal_schedule rows have no model).
     *
     * Mirrors ConversationService::canonicalTarget(): rehearsal-backed events
     * collapse to the Rehearsal; everything else keys on the Events row.
     *
     * @return array{0: class-string, 1: int}|null
     */
    private function conversableFor(array $e): ?array
    {
        $source = $e['event_source'] ?? null;
        if ($source === 'rehearsal_schedule') {
            return null;
        }
        if ($source === 'rehearsal') {
            $id = $e['eventable_id'] ?? null; // same field normalizeEvent emits as `id`

            return $id ? [Rehearsal::class, (int) $id] : null;
        }
        $id = $e['id'] ?? null;

        return $id ? [Events::class, (int) $id] : null;
    }

    /**
     * All conversable pairs for a dashboard page, for TopicUnreadService.
     *
     * @return array<int, array{0: class-string, 1: int}>
     */
    public function conversablePairs($events): array
    {
        $pairs = [];
        foreach ($events as $e) {
            $pair = $this->conversableFor((array) $e);
            if ($pair !== null) {
                $pairs[] = $pair;
            }
        }

        return array_values(array_unique($pairs, SORT_REGULAR));
    }
```

Thread the unread map through: `formatEvents($events)` gains a second parameter `array $unreadByKey = []` and passes it to each `normalizeEvent()` call; `normalizeEvent(array $e)` gains `array $unreadByKey = []` and appends to its returned array:

```php
            'unread_comment_count' => ($pair = $this->conversableFor($e)) !== null
                ? ($unreadByKey["{$pair[0]}:{$pair[1]}"] ?? 0)
                : 0,
```

- [ ] **Step 4: Implement the controller wiring**

In `app/Http/Controllers/Api/Mobile/DashboardController.php`, inject the service (constructor promotion alongside the existing formatter property, matching the file's style) and, in BOTH `index()` and `loadOlder()`, between fetching the events collection and formatting:

```php
        $unreadByKey = $this->topicUnread->unreadCountsForConversables(
            $request->user(),
            $this->formatter->conversablePairs($events),
        );
```

then change the `formatEvents($events)` calls to `formatEvents($events, $unreadByKey)`.

- [ ] **Step 5: Run the new + surrounding tests**

Run: `docker compose exec app php artisan test --filter=DashboardUnreadCommentTest`
Expected: PASS (3 tests).
Run: `docker compose exec app php artisan test --filter=DashboardTest && docker compose exec app php artisan test --filter=DashboardFormatterTest`
Expected: PASS. If `DashboardFormatterTest` asserts the exact payload key set, add `'unread_comment_count' => 0` to its expectations.

- [ ] **Step 6: Commit**

```bash
git add app/Services/Mobile/DashboardFormatter.php app/Http/Controllers/Api/Mobile/DashboardController.php tests/
git commit -m "feat(mobile): unread_comment_count on dashboard events"
```

---

### Task 12: Backend final verification

- [ ] **Step 1: Full backend test suite**

Run: `docker compose exec app php artisan test`
Expected: PASS. Known flakes (memory): `band_roles` unique-constraint and `CalendarFeedTest` can fail under parallel runs — re-run those files sequentially before treating failures as real.

- [ ] **Step 2: No commit** — this task only verifies.

---

## Integration notes (for the finishing skill, not tasks)

- Mobile PR: base `main`, repo `tts_bandmate`. Backend PR: base `staging`, repo `TTS` (auto-deploys on merge). Wait for and address Copilot's PR review on both.
- Safe rollout order: backend can merge first or last — the Flutter client defaults `unread_comment_count` to 0 when absent, and the backend field is additive.
- On-device verification (run-on-device skill): open an event with comments → bar shows latest comment + unread badge without scrolling; comment from web as another user → dashboard badge appears; open thread → badge clears.
