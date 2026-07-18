# Chat Polish Phase 1 — Media Viewer + Timestamps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap a chat picture to view it fullscreen with pinch-zoom, save it to the photo library or share it; add date separators and tap-to-reveal timestamps to the thread.

**Architecture:** All mobile-only (no backend changes). Pure time-label functions in a new `utils/` file feed separator rows and revealed labels in `ConversationThreadScreen`. A new `AttachmentViewerScreen` fetches original bytes through a new `ChatRepository.attachmentBytes` method (one download shared by display/save/share); the `gal` and `share_plus` plugin calls are injected as function seams so widget tests can fake them.

**Tech Stack:** Flutter/Cupertino, Riverpod v2, Dio, intl (already a dep), `share_plus` (already a dep), `gal` (new dep), `path_provider` (already a dep).

**Spec:** `docs/superpowers/specs/2026-07-18-chat-polish-design.md` (Phase 1 section).

## Global Constraints

- Branch: `feat/chat-polish` (already created off `origin/main`). PR targets `main`.
- Cupertino widgets only; secondary text via `context.secondaryText` / `context.tertiaryText` from `package:tts_bandmate/core/theme/context_colors.dart` — never raw `CupertinoColors.secondaryLabel`/`tertiaryLabel` in a `color:`.
- Hand-written models/parsing, no codegen.
- No time-bomb tests: pure functions take `now` explicitly; widget tests assert on tz-safe strings (`'edited'`, year substrings), never on a specific clock time.
- Commands: `flutter test <file>` per task, `flutter analyze` + `flutter test` at the end.
- Do not bump `pubspec.yaml` version (release-please owns versions).

---

### Task 1: Time-label utilities

**Files:**
- Create: `lib/features/chat/utils/message_time.dart`
- Test: `test/features/chat/message_time_test.dart`

**Interfaces:**
- Consumes: nothing (pure Dart + `intl`).
- Produces (used by Task 2):
  - `bool needsDateSeparator(DateTime? previous, DateTime current)`
  - `String dateSeparatorLabel(DateTime time, {required DateTime now})`
  - `String bubbleTimeLabel(DateTime time, {required DateTime now})`

- [ ] **Step 1: Write the failing tests**

Create `test/features/chat/message_time_test.dart`. All DateTimes are constructed local (no ISO-Z parsing) so results don't depend on the machine timezone; `now` is always passed explicitly (no live clock).

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/utils/message_time.dart';

void main() {
  final now = DateTime(2026, 7, 18, 20, 0); // Sat Jul 18 2026, 8:00 PM local

  group('needsDateSeparator', () {
    test('first message always gets a separator', () {
      expect(needsDateSeparator(null, DateTime(2026, 7, 18, 9, 0)), isTrue);
    });

    test('same day within an hour: no separator', () {
      expect(
        needsDateSeparator(
            DateTime(2026, 7, 18, 9, 0), DateTime(2026, 7, 18, 9, 59)),
        isFalse,
      );
    });

    test('same day but more than an hour apart: separator', () {
      expect(
        needsDateSeparator(
            DateTime(2026, 7, 18, 9, 0), DateTime(2026, 7, 18, 10, 1)),
        isTrue,
      );
    });

    test('day boundary: separator even when minutes apart', () {
      expect(
        needsDateSeparator(
            DateTime(2026, 7, 17, 23, 55), DateTime(2026, 7, 18, 0, 5)),
        isTrue,
      );
    });
  });

  group('dateSeparatorLabel', () {
    test('same day as now: Today + time', () {
      expect(dateSeparatorLabel(DateTime(2026, 7, 18, 15, 42), now: now),
          'Today 3:42 PM');
    });

    test('previous day: Yesterday + time', () {
      expect(dateSeparatorLabel(DateTime(2026, 7, 17, 9, 10), now: now),
          'Yesterday 9:10 AM');
    });

    test('within the last week: weekday + time', () {
      // Jul 14 2026 is a Tuesday, 4 days before `now`.
      expect(dateSeparatorLabel(DateTime(2026, 7, 14, 18, 30), now: now),
          'Tuesday 6:30 PM');
    });

    test('older than a week: full date + time', () {
      expect(dateSeparatorLabel(DateTime(2026, 6, 3, 15, 42), now: now),
          'Jun 3, 2026 3:42 PM');
    });

    test('exactly 7 days ago is full date, not weekday (avoids ambiguity)',
        () {
      expect(dateSeparatorLabel(DateTime(2026, 7, 11, 8, 0), now: now),
          'Jul 11, 2026 8:00 AM');
    });
  });

  group('bubbleTimeLabel', () {
    test('same day: time only', () {
      expect(
          bubbleTimeLabel(DateTime(2026, 7, 18, 15, 42), now: now), '3:42 PM');
    });

    test('other day: date + time', () {
      expect(bubbleTimeLabel(DateTime(2026, 6, 3, 15, 42), now: now),
          'Jun 3, 2026 3:42 PM');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/chat/message_time_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package ... message_time.dart` (file doesn't exist).

- [ ] **Step 3: Write the implementation**

Create `lib/features/chat/utils/message_time.dart`:

```dart
import 'package:intl/intl.dart';

/// Pure time-label helpers for the chat thread. Everything converts to local
/// time internally; callers pass `now` explicitly so tests can pin the clock.

/// Whether a date-separator row belongs above the message at [current], given
/// the (older) [previous] message's time. The first message of the loaded
/// window ([previous] == null) always gets one; otherwise a calendar-day
/// change or a gap of more than an hour does.
bool needsDateSeparator(DateTime? previous, DateTime current) {
  if (previous == null) return true;
  final p = previous.toLocal();
  final c = current.toLocal();
  final sameDay = p.year == c.year && p.month == c.month && p.day == c.day;
  return !sameDay || c.difference(p) > const Duration(hours: 1);
}

/// "Today 3:42 PM" / "Yesterday 9:10 AM" / "Tuesday 6:30 PM" (last 7 days) /
/// "Jun 3, 2026 3:42 PM" (older).
String dateSeparatorLabel(DateTime time, {required DateTime now}) {
  final t = time.toLocal();
  final n = now.toLocal();
  final clock = DateFormat.jm().format(t);
  final daysAgo = DateTime(n.year, n.month, n.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
  if (daysAgo <= 0) return 'Today $clock';
  if (daysAgo == 1) return 'Yesterday $clock';
  if (daysAgo < 7) return '${DateFormat.EEEE().format(t)} $clock';
  return '${DateFormat.yMMMd().format(t)} $clock';
}

/// Tap-to-reveal label under a bubble: time only for today's messages, full
/// date + time otherwise.
String bubbleTimeLabel(DateTime time, {required DateTime now}) {
  final t = time.toLocal();
  final n = now.toLocal();
  final sameDay = t.year == n.year && t.month == n.month && t.day == n.day;
  final clock = DateFormat.jm().format(t);
  return sameDay ? clock : '${DateFormat.yMMMd().format(t)} $clock';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/chat/message_time_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/utils/message_time.dart test/features/chat/message_time_test.dart
git commit -m "feat(chat): pure time-label helpers for separators and revealed timestamps"
```

---

### Task 2: Date separators + tap-to-reveal in the thread screen

**Files:**
- Modify: `lib/features/chat/screens/conversation_thread_screen.dart`
- Test: `test/features/chat/conversation_thread_screen_test.dart` (append tests)

**Interfaces:**
- Consumes (from Task 1): `needsDateSeparator`, `dateSeparatorLabel`, `bubbleTimeLabel` from `../utils/message_time.dart`.
- Produces: `_MessageBubble` gains `required bool showTime` and `required VoidCallback onTap` parameters (Task 5 modifies the same widget's attachment rendering — parameter list must match this task's result).

- [ ] **Step 1: Write the failing widget tests**

Append to `test/features/chat/conversation_thread_screen_test.dart` (inside `main()`, reusing the file's existing `StubAdapter`/`json` harness imports):

```dart
  testWidgets('inserts date separators between messages on different days',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async => json(200, {
            'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
            'messages': [
              {
                'id': 1,
                'conversation_id': 5,
                'user_id': 3,
                'user_name': 'Sam',
                'body': 'from june',
                'created_at': '2026-06-03T14:00:00Z',
              },
              {
                'id': 2,
                'conversation_id': 5,
                'user_id': 3,
                'user_name': 'Sam',
                'body': 'from july',
                'created_at': '2026-07-02T14:00:00Z',
              },
            ],
            'participants': [
              {'user_id': 3, 'name': 'Sam', 'last_read_at': null},
            ],
            'channel': 'private-conversation.5',
            'has_more': false,
          }));

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatMarkReadDebounceProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((_, __) => null),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(conversationId: 5, title: 'Sam'),
      ),
    ));
    await tester.pumpAndSettle();

    // Both messages are >7 days old relative to any real test-run clock, so
    // both separators use the tz-safe full-date form containing the year:
    // one above the first message, one at the June→July day change.
    expect(find.textContaining('2026'), findsNWidgets(2));
  });

  testWidgets('tapping a bubble reveals its timestamp (with edited marker)',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async => json(200, {
            'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
            'messages': [
              {
                'id': 1,
                'conversation_id': 5,
                'user_id': 3,
                'user_name': 'Sam',
                'body': 'fixed a typo here',
                'created_at': '2026-07-12T14:00:00Z',
                'edited_at': '2026-07-12T14:05:00Z',
              },
            ],
            'participants': [
              {'user_id': 3, 'name': 'Sam', 'last_read_at': null},
            ],
            'channel': 'private-conversation.5',
            'has_more': false,
          }));

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatMarkReadDebounceProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((_, __) => null),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(conversationId: 5, title: 'Sam'),
      ),
    ));
    await tester.pumpAndSettle();

    // Hidden until tapped (the old always-on 'edited' label is gone).
    expect(find.textContaining('edited'), findsNothing);

    await tester.tap(find.text('fixed a typo here'));
    await tester.pump();
    expect(find.textContaining('· edited'), findsOneWidget);

    // Tapping again hides it.
    await tester.tap(find.text('fixed a typo here'));
    await tester.pump();
    expect(find.textContaining('edited'), findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/chat/conversation_thread_screen_test.dart`
Expected: the two new tests FAIL (`findsNWidgets(2)` finds 0; `· edited` never appears — today 'edited' is always visible, so the first `findsNothing` also fails). Pre-existing tests still pass, except any that asserted the always-visible `edited` label — update those in Step 3 if present.

- [ ] **Step 3: Implement separators + tap-to-reveal**

In `lib/features/chat/screens/conversation_thread_screen.dart`:

3a. Add the import:

```dart
import '../utils/message_time.dart';
```

3b. Add reveal state to `_ConversationThreadScreenState` (next to `_pendingImages`):

```dart
  final Set<int> _revealedTimeIds = {};
```

3c. In the `ListView.builder` `itemBuilder`, replace the current `return _MessageBubble(...)` block with:

```dart
                        final idx = state.messages.length - 1 - i;
                        final message = state.messages[idx];
                        final previous =
                            idx > 0 ? state.messages[idx - 1] : null;
                        final isLast = idx == state.messages.length - 1;
                        final bubble = _MessageBubble(
                          message: message,
                          isOwn: message.userId == currentUserId,
                          showSeen: isLast &&
                              message.userId == currentUserId &&
                              seenByOthersCount(message, state.participants,
                                      currentUserId) >
                                  0,
                          isDm: state.conversation?.type == 'dm',
                          showTime: _revealedTimeIds.contains(message.id),
                          onTap: () => setState(() {
                            if (!_revealedTimeIds.remove(message.id)) {
                              _revealedTimeIds.add(message.id);
                            }
                          }),
                          onLongPress: () => _showMessageActions(message),
                        );
                        if (!needsDateSeparator(
                            previous?.createdAt, message.createdAt)) {
                          return bubble;
                        }
                        // stretch so the bubble Column keeps the full row
                        // width its own start/end alignment relies on.
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DateSeparator(
                              label: dateSeparatorLabel(message.createdAt,
                                  now: DateTime.now()),
                            ),
                            bubble,
                          ],
                        );
```

3d. Add the separator widget (top level, next to `_MessageBubble`):

```dart
class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: context.secondaryText),
          ),
        ),
      );
}
```

3e. In `_MessageBubble`: add the two new fields/params:

```dart
  const _MessageBubble({
    required this.message,
    required this.isOwn,
    required this.showSeen,
    required this.isDm,
    required this.showTime,
    required this.onTap,
    required this.onLongPress,
  });
```

```dart
  final bool showTime;
  final VoidCallback onTap;
```

3f. Wire the tap on the bubble's `GestureDetector` (deleted messages may still reveal their time):

```dart
        GestureDetector(
          onTap: onTap,
          onLongPress: message.isDeleted ? null : onLongPress,
```

3g. Replace the always-visible `edited` block (the `if (message.editedAt != null && !message.isDeleted)` Padding) with the revealed time line:

```dart
                if (showTime)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      message.editedAt != null && !message.isDeleted
                          ? '${bubbleTimeLabel(message.createdAt, now: DateTime.now())} · edited'
                          : bubbleTimeLabel(message.createdAt,
                              now: DateTime.now()),
                      style: TextStyle(
                        fontSize: 11,
                        color: isOwn
                            ? CupertinoColors.white.withValues(alpha: 0.7)
                            : context.tertiaryText,
                      ),
                    ),
                  ),
```

- [ ] **Step 4: Run the file's tests**

Run: `flutter test test/features/chat/conversation_thread_screen_test.dart`
Expected: PASS (all, including pre-existing).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/screens/conversation_thread_screen.dart test/features/chat/conversation_thread_screen_test.dart
git commit -m "feat(chat): date separators and tap-to-reveal timestamps in thread"
```

---

### Task 3: ChatRepository.attachmentBytes

**Files:**
- Modify: `lib/features/chat/data/chat_repository.dart`
- Test: `test/features/chat/chat_repository_test.dart` (append test)

**Interfaces:**
- Produces (used by Task 4): `Future<Uint8List> attachmentBytes(int messageId, int attachmentId)` on `ChatRepository`.

- [ ] **Step 1: Write the failing test**

Append to `test/features/chat/chat_repository_test.dart` (add `import 'dart:typed_data';` at the top):

```dart
  test('attachmentBytes requests binary and returns the raw bytes', () async {
    final captured = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        captured.add(options);
        return ResponseBody.fromBytes(Uint8List.fromList([1, 2, 3]), 200);
      });
    final repo = ChatRepository(dio);

    final bytes = await repo.attachmentBytes(9, 4);

    expect(bytes, [1, 2, 3]);
    expect(captured.single.path, '/api/mobile/messages/9/attachments/4');
    expect(captured.single.responseType, ResponseType.bytes);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_repository_test.dart`
Expected: FAIL — `The method 'attachmentBytes' isn't defined for the class 'ChatRepository'`.

- [ ] **Step 3: Implement**

In `lib/features/chat/data/chat_repository.dart`, add `import 'dart:typed_data';` and, next to the existing `attachmentUrl` method:

```dart
  /// Full-resolution bytes of an attachment. The fullscreen viewer downloads
  /// once and shares the bytes between display, save, and share.
  Future<Uint8List> attachmentBytes(int messageId, int attachmentId) async {
    final res = await _dio.get<List<int>>(
      ApiEndpoints.mobileMessageAttachment(messageId, attachmentId),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/chat_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/data/chat_repository.dart test/features/chat/chat_repository_test.dart
git commit -m "feat(chat): repository fetch for full-resolution attachment bytes"
```

---

### Task 4: AttachmentViewerScreen (fullscreen, zoom, save, share)

**Files:**
- Create: `lib/features/chat/screens/attachment_viewer_screen.dart`
- Modify: `pubspec.yaml` (add `gal`)
- Modify: `ios/Runner/Info.plist` (add `NSPhotoLibraryAddUsageDescription`)
- Modify: `android/app/src/main/AndroidManifest.xml` (legacy storage permission for API ≤29)
- Test: `test/features/chat/attachment_viewer_screen_test.dart`

**Interfaces:**
- Consumes (from Task 3): `ChatRepository.attachmentBytes(int messageId, int attachmentId)` via `chatRepositoryProvider`; `ChatAttachment` from `../data/models/chat_message.dart`.
- Produces (used by Task 5): `AttachmentViewerScreen({required int messageId, required List<ChatAttachment> attachments, int initialIndex = 0, SaveImage saveImage = _saveWithGal, ShareImage shareImage = _shareViaSheet})` — the seams default to the real plugin implementations, so production callers pass only the first three.

- [ ] **Step 1: Add the `gal` dependency and platform config**

In `pubspec.yaml` under `dependencies:` (alphabetical, near `image_picker`):

```yaml
  gal: ^2.3.0
```

Run: `flutter pub get`
Expected: resolves without errors.

In `ios/Runner/Info.plist`, directly after the existing `NSPhotoLibraryUsageDescription` entry:

```xml
	<key>NSPhotoLibraryAddUsageDescription</key>
	<string>Bandmate saves chat photos you choose to your photo library.</string>
```

In `android/app/src/main/AndroidManifest.xml`, before the `<application>` element (gal needs this only on Android 10/API 29 and below):

```xml
    <uses-permission
        android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="29" />
```

(If a `WRITE_EXTERNAL_STORAGE` permission already exists, keep the existing one and skip this.)

- [ ] **Step 2: Write the failing widget tests**

Create `test/features/chat/attachment_viewer_screen_test.dart`:

```dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_message.dart';
import 'package:tts_bandmate/features/chat/screens/attachment_viewer_screen.dart';

import '../../helpers/test_harness.dart';

/// Smallest well-formed image: 1x1 transparent PNG. Image.memory must get
/// decodable bytes or the page shows its error state instead.
final kTransparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  Widget wrap(ProviderContainer container, Widget child) =>
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(home: child),
      );

  testWidgets('loads the image and save button reports success',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter =
          StubAdapter((_) async => ResponseBody.fromBytes(kTransparentPng, 200));
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);

    final saved = <String>[];
    await tester.pumpWidget(wrap(
      container,
      AttachmentViewerScreen(
        messageId: 9,
        attachments: const [ChatAttachment(id: 4, width: 1, height: 1)],
        saveImage: (bytes, name) async => saved.add(name),
        shareImage: (bytes, name) async {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.square_arrow_down));
    await tester.pump();
    expect(saved, ['bandmate_9_4']);
    expect(find.text('Saved'), findsOneWidget);

    // Confirmation auto-dismisses.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('failed fetch shows retry, and retry recovers', (tester) async {
    var calls = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async {
        calls++;
        if (calls == 1) return json(500, {'message': 'boom'});
        return ResponseBody.fromBytes(kTransparentPng, 200);
      });
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap(
      container,
      AttachmentViewerScreen(
        messageId: 9,
        attachments: const [ChatAttachment(id: 4, width: 1, height: 1)],
        saveImage: (bytes, name) async {},
        shareImage: (bytes, name) async {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('save failure surfaces an alert', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter =
          StubAdapter((_) async => ResponseBody.fromBytes(kTransparentPng, 200));
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap(
      container,
      AttachmentViewerScreen(
        messageId: 9,
        attachments: const [ChatAttachment(id: 4, width: 1, height: 1)],
        saveImage: (bytes, name) async => throw Exception('denied'),
        shareImage: (bytes, name) async {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.square_arrow_down));
    await tester.pumpAndSettle();
    expect(find.text('Could not save photo'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/chat/attachment_viewer_screen_test.dart`
Expected: FAIL — screen file doesn't exist yet.

- [ ] **Step 4: Implement the screen**

Create `lib/features/chat/screens/attachment_viewer_screen.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/chat_repository.dart';
import '../data/models/chat_message.dart';

/// Plugin seams: gal/share_plus/path_provider have no test bindings, so the
/// widget takes these as functions and tests inject fakes.
typedef SaveImage = Future<void> Function(Uint8List bytes, String name);
typedef ShareImage = Future<void> Function(Uint8List bytes, String name);

Future<void> _saveWithGal(Uint8List bytes, String name) =>
    Gal.putImageBytes(bytes, name: name);

Future<void> _shareViaSheet(Uint8List bytes, String name) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name.jpg');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(file.path, mimeType: 'image/jpeg')]);
}

/// Fullscreen pager over one message's image attachments with pinch-zoom,
/// save-to-photos, and system share. Downloads each attachment's original
/// bytes once and reuses them for display, save, and share.
class AttachmentViewerScreen extends ConsumerStatefulWidget {
  const AttachmentViewerScreen({
    super.key,
    required this.messageId,
    required this.attachments,
    this.initialIndex = 0,
    this.saveImage = _saveWithGal,
    this.shareImage = _shareViaSheet,
  });

  final int messageId;
  final List<ChatAttachment> attachments;
  final int initialIndex;
  final SaveImage saveImage;
  final ShareImage shareImage;

  @override
  ConsumerState<AttachmentViewerScreen> createState() =>
      _AttachmentViewerScreenState();
}

class _AttachmentViewerScreenState
    extends ConsumerState<AttachmentViewerScreen> {
  final Map<int, Uint8List> _bytes = {}; // attachmentId → downloaded bytes
  final Set<int> _failed = {};
  final Set<int> _inFlight = {};
  late int _page = widget.initialIndex;
  // A state field, NOT built inline in build(): recreating the controller on
  // each rebuild would re-attach at initialPage and snap the pager back after
  // every setState (page change, saved-toast, load completion).
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  bool _showSavedConfirmation = false;
  Timer? _savedTimer;

  @override
  void initState() {
    super.initState();
    _load(widget.attachments[widget.initialIndex].id);
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load(int attachmentId) async {
    if (_bytes.containsKey(attachmentId) || _inFlight.contains(attachmentId)) {
      return;
    }
    _inFlight.add(attachmentId);
    setState(() => _failed.remove(attachmentId));
    try {
      final bytes = await ref
          .read(chatRepositoryProvider)
          .attachmentBytes(widget.messageId, attachmentId);
      if (!mounted) return;
      setState(() => _bytes[attachmentId] = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed.add(attachmentId));
    } finally {
      _inFlight.remove(attachmentId);
    }
  }

  Uint8List? get _currentBytes => _bytes[widget.attachments[_page].id];

  String get _currentName =>
      'bandmate_${widget.messageId}_${widget.attachments[_page].id}';

  Future<void> _save() async {
    final bytes = _currentBytes;
    if (bytes == null) return;
    try {
      await widget.saveImage(bytes, _currentName);
      if (!mounted) return;
      setState(() => _showSavedConfirmation = true);
      _savedTimer?.cancel();
      _savedTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showSavedConfirmation = false);
      });
    } on GalException catch (e) {
      if (!mounted) return;
      _showError(
        'Could not save photo',
        e.type == GalExceptionType.accessDenied
            ? 'Allow photo library access for Bandmate in Settings and try again.'
            : 'Something went wrong saving this photo.',
      );
    } catch (_) {
      if (!mounted) return;
      _showError('Could not save photo',
          'Something went wrong saving this photo.');
    }
  }

  Future<void> _share() async {
    final bytes = _currentBytes;
    if (bytes == null) return;
    try {
      await widget.shareImage(bytes, _currentName);
    } catch (_) {
      if (!mounted) return;
      _showError('Could not share photo',
          'Something went wrong sharing this photo.');
    }
  }

  void _showError(String title, String body) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBytes = _currentBytes != null;
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black.withValues(alpha: 0.6),
        middle: Text(
          widget.attachments.length > 1
              ? '${_page + 1} of ${widget.attachments.length}'
              : '',
          style: const TextStyle(color: CupertinoColors.white),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: hasBytes ? _save : null,
              child: const Icon(CupertinoIcons.square_arrow_down,
                  color: CupertinoColors.white),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: hasBytes ? _share : null,
              child: const Icon(CupertinoIcons.share,
                  color: CupertinoColors.white),
            ),
          ],
        ),
      ),
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.attachments.length,
            onPageChanged: (page) {
              setState(() => _page = page);
              _load(widget.attachments[page].id);
            },
            itemBuilder: (_, index) {
              final attachment = widget.attachments[index];
              final bytes = _bytes[attachment.id];
              if (bytes != null) {
                return InteractiveViewer(
                  maxScale: 5,
                  child: Center(child: Image.memory(bytes)),
                );
              }
              if (_failed.contains(attachment.id)) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.photo,
                          size: 40, color: CupertinoColors.systemGrey),
                      CupertinoButton(
                        onPressed: () => _load(attachment.id),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              // First frame for a not-yet-requested page (swipe landed here
              // before onPageChanged fired): kick the fetch off post-frame.
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _load(attachment.id));
              return const Center(child: CupertinoActivityIndicator());
            },
          ),
          if (_showSavedConfirmation)
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: CupertinoColors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Saved',
                    style: TextStyle(color: CupertinoColors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

Note: this screen deliberately uses raw `CupertinoColors.white`/`black` — it's a fixed black lightbox in both themes, not themed chrome, so the `context.*Text` rule doesn't apply here.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/chat/attachment_viewer_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml lib/features/chat/screens/attachment_viewer_screen.dart test/features/chat/attachment_viewer_screen_test.dart
git commit -m "feat(chat): fullscreen attachment viewer with save and share"
```

---

### Task 5: Tap a thumbnail to open the viewer

**Files:**
- Modify: `lib/features/chat/screens/conversation_thread_screen.dart` (`_MessageBubble` attachment loop)
- Test: `test/features/chat/conversation_thread_screen_test.dart` (append test)

**Interfaces:**
- Consumes (from Task 4): `AttachmentViewerScreen(messageId:, attachments:, initialIndex:)` from `attachment_viewer_screen.dart`.
- Consumes (from Task 2): `_MessageBubble`'s parameter list including `showTime`/`onTap`.

- [ ] **Step 1: Write the failing widget test**

Append to `test/features/chat/conversation_thread_screen_test.dart`. Add imports at the top of the file:

```dart
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'package:tts_bandmate/features/chat/screens/attachment_viewer_screen.dart';
import 'package:tts_bandmate/shared/widgets/auth_thumbnail.dart';
```

```dart
  testWidgets('tapping an attachment opens the fullscreen viewer',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        if (options.path.contains('/attachments/')) {
          // Viewer fetch: any bytes will do — the screen itself is what the
          // test asserts on, not a decoded image.
          return ResponseBody.fromBytes(Uint8List.fromList([0]), 200);
        }
        return json(200, {
          'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
          'messages': [
            {
              'id': 1,
              'conversation_id': 5,
              'user_id': 3,
              'user_name': 'Sam',
              'body': '',
              'created_at': '2026-07-12T14:00:00Z',
              'attachments': [
                {'id': 7, 'width': 100, 'height': 80},
              ],
            },
          ],
          'participants': [
            {'user_id': 3, 'name': 'Sam', 'last_read_at': null},
          ],
          'channel': 'private-conversation.5',
          'has_more': false,
        });
      });

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatMarkReadDebounceProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((_, __) => null),
      secureStorageProvider.overrideWithValue(FakeSecureStorage()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(conversationId: 5, title: 'Sam'),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(AuthThumbnail));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AttachmentViewerScreen), findsOneWidget);
  });
```

(`Uint8List` needs `import 'dart:typed_data';` — add it if Task 3's test didn't already. This test uses discrete `pump`s, not `pumpAndSettle`, because `CachedNetworkImage`/`Image.memory` decode failures with garbage bytes keep scheduling frames.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/conversation_thread_screen_test.dart`
Expected: the new test FAILS — `find.byType(AttachmentViewerScreen)` finds nothing (thumbnail tap currently toggles the timestamp instead).

- [ ] **Step 3: Implement the tap wiring**

In `lib/features/chat/screens/conversation_thread_screen.dart`:

3a. Add the import:

```dart
import 'attachment_viewer_screen.dart';
```

3b. In `_MessageBubble.build`, replace the attachment loop (`for (final attachment in message.attachments) ...`) with an indexed loop whose thumbnail is tappable:

```dart
                for (final (index, attachment)
                    in message.attachments.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => AttachmentViewerScreen(
                            messageId: message.id,
                            attachments: message.attachments,
                            initialIndex: index,
                          ),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 200,
                          height: attachment.width > 0
                              ? 200 * attachment.height / attachment.width
                              : 200,
                          child: AuthThumbnail(
                            url: repo.attachmentUrl(message.id, attachment.id),
                          ),
                        ),
                      ),
                    ),
                  ),
```

- [ ] **Step 4: Run the file's tests**

Run: `flutter test test/features/chat/conversation_thread_screen_test.dart`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/screens/conversation_thread_screen.dart test/features/chat/conversation_thread_screen_test.dart
git commit -m "feat(chat): open fullscreen viewer from attachment thumbnails"
```

---

### Task 6: Full verification

**Files:** none new.

- [ ] **Step 1: Static analysis**

Run: `flutter analyze`
Expected: `No issues found!` — fix anything reported before proceeding.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all tests pass (including every pre-existing suite).

- [ ] **Step 3: Commit any fixes**

```bash
git add -A && git commit -m "chore(chat): analyzer/test fixes for phase 1" # only if Step 1/2 required changes
```

- [ ] **Step 4: On-device verification (manual gate)**

Use the `run-on-device` skill: run the app against the local backend, open a chat with a photo, then verify:
1. Tap photo → fullscreen; pinch-zoom works; swipe between multiple attachments.
2. Save → "Saved" toast; photo appears in the device gallery.
3. Share → system sheet opens with the image.
4. Date separators render; tapping a bubble toggles its timestamp; an edited message shows "… · edited".

Then push and open a PR to `main`; wait for Copilot review and address comments before calling Phase 1 done.
