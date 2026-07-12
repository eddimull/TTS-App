# Comments & Chat — Flutter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the mobile client for the unified conversation system: comments on events/rehearsals/bookings, 1:1 DMs, band group channel, unread badges, typing indicators, read receipts, image attachments, realtime, and push routing.

**Architecture:** New `lib/features/chat/` vertical slice (models → repository → providers → screens) following the rehearsal-planner pattern for per-conversation live channels and the band-realtime pattern for list invalidation. A reusable thread screen serves DMs, the band channel, and topic (comment) threads. Comments sections embed in the three detail screens and deep-link into the thread screen.

**Tech Stack:** Flutter/Cupertino, Riverpod v2 (`Notifier`/`FutureProvider`), Dio (multipart), pusher_channels_flutter via the shared `PusherConnection`, image_picker (already a dependency — its `imageQuality`/`maxWidth` params handle client-side compression; **no new packages**), firebase_messaging + flutter_local_notifications (existing).

## Global Constraints

- Branch: `feat/comments-chat` (already created). Spec: `docs/superpowers/specs/2026-07-12-comments-chat-design.md`.
- Repo: `/home/eddie/github/tts_bandmate`. All paths below are relative to it.
- Backend API contract (assumed live; build against it exactly):
  - `GET /api/mobile/conversations` → `{"conversations": [Conversation…]}`
  - `POST /api/mobile/conversations/dm` body `{"user_id": int}` → `{"conversation": Conversation}`
  - `GET /api/mobile/chat/contacts` → `{"contacts": [{"id", "name", "avatar_url", "context", "is_sub"}…]}`
  - `GET /api/mobile/events/{key}/conversation` | `GET /api/mobile/rehearsals/{id}/conversation` | `GET /api/mobile/bookings/{id}/conversation` → ThreadPage JSON (below)
  - `GET /api/mobile/conversations/{id}/messages?before={messageId}` → ThreadPage JSON
  - `POST /api/mobile/conversations/{id}/messages` multipart `body` (string, optional) + `images[]` (files, optional, ≤4) → `{"message": Message}`
  - `PATCH /api/mobile/messages/{id}` body `{"body": string}` → `{"message": Message}`
  - `DELETE /api/mobile/messages/{id}` → 204
  - `POST /api/mobile/conversations/{id}/read` body `{"last_read_message_id": int}` → 204
  - `POST /api/mobile/conversations/{id}/typing` → 204
  - `GET /api/mobile/messages/{id}/attachments/{attachmentId}` → image bytes (Bearer auth)
  - ThreadPage JSON: `{"conversation": Conversation, "messages": [Message…] (oldest→newest), "participants": [{"user_id","name","avatar_url","last_read_at"}…], "channel": "private-conversation.{id}", "has_more": bool}`
  - Conversation JSON: `{"id", "type" ("dm"|"band"|"topic"), "band_id", "title", "last_message_preview", "last_message_at", "unread_count", "can_moderate"}`
  - Message JSON: `{"id", "conversation_id", "user_id", "user_name", "user_avatar_url", "body", "attachments": [{"id","width","height"}…], "edited_at", "is_deleted", "created_at"}`
  - Live channel `private-conversation.{id}` events: `message.created` `{"message": Message}`, `message.updated` `{"message": Message}`, `message.deleted` `{"message_id": int}`, `conversation.read` `{"user_id": int, "last_read_at": iso8601}`, `conversation.typing` `{"user_id": int, "name": string}`
  - Thin signals: `band.data-changed` with `model: "message"` on `private-band.{id}`; `user.data-changed` with `model: "message"` on `private-App.Models.User.{id}`
  - Push data: `{"type": "chat_message", "conversationId": "<int>", "title", "body"}`
- Dark mode: text colors via `context.primaryText` / `context.secondaryText` / `context.tertiaryText` / `context.placeholderText` from `package:tts_bandmate/core/theme/context_colors.dart` — never raw `CupertinoColors.secondaryLabel` in a `color:`.
- Commits: end every commit message with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Verify each task with the exact `flutter test`/`flutter analyze` commands given; expected results are stated per step.
- Riverpod note: `ProviderOrFamily` must be imported from `package:flutter_riverpod/misc.dart` where referenced (see `lib/shared/providers/band_realtime_provider.dart:8`).

---

### Task 1: Chat data models + endpoint constants

**Files:**
- Create: `lib/features/chat/data/models/conversation.dart`
- Create: `lib/features/chat/data/models/chat_message.dart`
- Create: `lib/features/chat/data/models/chat_participant.dart`
- Create: `lib/features/chat/data/models/chat_contact.dart`
- Modify: `lib/core/network/api_endpoints.dart` (append inside the `ApiEndpoints` class, before the closing `}` at line 245)
- Test: `test/features/chat/models_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `Conversation{int id, String type, int? bandId, String title, String? lastMessagePreview, DateTime? lastMessageAt, int unreadCount, bool canModerate}`, `ChatMessage{int id, int conversationId, int userId, String userName, String? userAvatarUrl, String body, List<ChatAttachment> attachments, DateTime? editedAt, bool isDeleted, DateTime createdAt, String status}` with `copyWith`, `ChatAttachment{int id, int width, int height}`, `ChatParticipant{int userId, String name, String? avatarUrl, DateTime? lastReadAt}` with `copyWith(lastReadAt:)`, `ChatContact{int id, String name, String? avatarUrl, String context, bool isSub}`, and `ApiEndpoints.mobileConversations`, `.mobileConversationsDm`, `.mobileChatContacts`, `.mobileConversationMessages(int)`, `.mobileMessage(int)`, `.mobileConversationRead(int)`, `.mobileConversationTyping(int)`, `.mobileEventConversation(String)`, `.mobileRehearsalConversation(int)`, `.mobileBookingConversation(int)`, `.mobileMessageAttachment(int,int)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_message.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_participant.dart';
import 'package:tts_bandmate/features/chat/data/models/conversation.dart';

void main() {
  test('Conversation parses full payload and defaults', () {
    final c = Conversation.fromJson({
      'id': 5,
      'type': 'band',
      'band_id': 7,
      'title': 'Three Thirty Seven',
      'last_message_preview': 'See you at 8',
      'last_message_at': '2026-07-12T14:00:00Z',
      'unread_count': 3,
      'can_moderate': true,
    });
    expect(c.id, 5);
    expect(c.type, 'band');
    expect(c.bandId, 7);
    expect(c.title, 'Three Thirty Seven');
    expect(c.lastMessagePreview, 'See you at 8');
    expect(c.unreadCount, 3);
    expect(c.canModerate, isTrue);

    final dm = Conversation.fromJson({'id': 6, 'type': 'dm', 'title': 'Sam'});
    expect(dm.bandId, isNull);
    expect(dm.unreadCount, 0);
    expect(dm.canModerate, isFalse);
    expect(dm.lastMessageAt, isNull);
  });

  test('ChatMessage parses attachments, edited/deleted flags', () {
    final m = ChatMessage.fromJson({
      'id': 10,
      'conversation_id': 5,
      'user_id': 2,
      'user_name': 'Eddie',
      'user_avatar_url': null,
      'body': 'hello',
      'attachments': [
        {'id': 1, 'width': 800, 'height': 600},
      ],
      'edited_at': null,
      'is_deleted': false,
      'created_at': '2026-07-12T14:00:00Z',
    });
    expect(m.id, 10);
    expect(m.attachments.single.width, 800);
    expect(m.isDeleted, isFalse);
    expect(m.editedAt, isNull);
    expect(m.status, 'complete');
    final edited = m.copyWith(body: 'hi', editedAt: DateTime.utc(2026, 7, 12, 15));
    expect(edited.body, 'hi');
    expect(edited.id, 10);
  });

  test('ChatParticipant parses and copies lastReadAt', () {
    final p = ChatParticipant.fromJson(
        {'user_id': 3, 'name': 'Sam', 'avatar_url': null, 'last_read_at': null});
    expect(p.lastReadAt, isNull);
    final read = p.copyWith(lastReadAt: DateTime.utc(2026, 7, 12));
    expect(read.lastReadAt, DateTime.utc(2026, 7, 12));
    expect(read.name, 'Sam');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/models_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package …/conversation.dart` (files don't exist).

- [ ] **Step 3: Write the models**

```dart
// lib/features/chat/data/models/conversation.dart
class Conversation {
  const Conversation({
    required this.id,
    required this.type,
    required this.title,
    this.bandId,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.canModerate = false,
  });

  final int id;
  final String type; // 'dm' | 'band' | 'topic'
  final String title;
  final int? bandId;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool canModerate;

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: (json['id'] as num).toInt(),
        type: json['type'] as String? ?? 'topic',
        title: json['title'] as String? ?? '',
        bandId: (json['band_id'] as num?)?.toInt(),
        lastMessagePreview: json['last_message_preview'] as String?,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.tryParse(json['last_message_at'] as String)
            : null,
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        canModerate: json['can_moderate'] as bool? ?? false,
      );
}
```

```dart
// lib/features/chat/data/models/chat_message.dart
class ChatAttachment {
  const ChatAttachment({required this.id, required this.width, required this.height});
  final int id;
  final int width;
  final int height;

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        id: (json['id'] as num).toInt(),
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.userId,
    required this.userName,
    required this.body,
    required this.createdAt,
    this.userAvatarUrl,
    this.attachments = const [],
    this.editedAt,
    this.isDeleted = false,
    this.status = 'complete', // 'sending' | 'complete' | 'failed' (client-side)
  });

  final int id;
  final int conversationId;
  final int userId;
  final String userName;
  final String? userAvatarUrl;
  final String body;
  final List<ChatAttachment> attachments;
  final DateTime? editedAt;
  final bool isDeleted;
  final DateTime createdAt;
  final String status;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: (json['id'] as num).toInt(),
        conversationId: (json['conversation_id'] as num).toInt(),
        userId: (json['user_id'] as num).toInt(),
        userName: json['user_name'] as String? ?? '',
        userAvatarUrl: json['user_avatar_url'] as String?,
        body: json['body'] as String? ?? '',
        attachments: (json['attachments'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ChatAttachment.fromJson)
            .toList(),
        editedAt: json['edited_at'] != null
            ? DateTime.tryParse(json['edited_at'] as String)
            : null,
        isDeleted: json['is_deleted'] as bool? ?? false,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  ChatMessage copyWith({
    int? id,
    String? body,
    List<ChatAttachment>? attachments,
    DateTime? editedAt,
    bool? isDeleted,
    String? status,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        conversationId: conversationId,
        userId: userId,
        userName: userName,
        userAvatarUrl: userAvatarUrl,
        body: body ?? this.body,
        attachments: attachments ?? this.attachments,
        editedAt: editedAt ?? this.editedAt,
        isDeleted: isDeleted ?? this.isDeleted,
        createdAt: createdAt,
        status: status ?? this.status,
      );
}
```

```dart
// lib/features/chat/data/models/chat_participant.dart
class ChatParticipant {
  const ChatParticipant({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.lastReadAt,
  });

  final int userId;
  final String name;
  final String? avatarUrl;
  final DateTime? lastReadAt;

  factory ChatParticipant.fromJson(Map<String, dynamic> json) => ChatParticipant(
        userId: (json['user_id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
        lastReadAt: json['last_read_at'] != null
            ? DateTime.tryParse(json['last_read_at'] as String)
            : null,
      );

  ChatParticipant copyWith({DateTime? lastReadAt}) => ChatParticipant(
        userId: userId,
        name: name,
        avatarUrl: avatarUrl,
        lastReadAt: lastReadAt ?? this.lastReadAt,
      );
}
```

```dart
// lib/features/chat/data/models/chat_contact.dart
class ChatContact {
  const ChatContact({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.context = '',
    this.isSub = false,
  });

  final int id;
  final String name;
  final String? avatarUrl;

  /// Human label for where you know them from, e.g. a band name.
  final String context;
  final bool isSub;

  factory ChatContact.fromJson(Map<String, dynamic> json) => ChatContact(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
        context: json['context'] as String? ?? '',
        isSub: json['is_sub'] as bool? ?? false,
      );
}
```

Append to `lib/core/network/api_endpoints.dart` immediately before the class's closing `}`:

```dart
  // Chat & comments
  static const String mobileConversations = '/api/mobile/conversations';
  static const String mobileConversationsDm = '/api/mobile/conversations/dm';
  static const String mobileChatContacts = '/api/mobile/chat/contacts';
  static String mobileConversationMessages(int conversationId) =>
      '/api/mobile/conversations/$conversationId/messages';
  static String mobileMessage(int messageId) => '/api/mobile/messages/$messageId';
  static String mobileConversationRead(int conversationId) =>
      '/api/mobile/conversations/$conversationId/read';
  static String mobileConversationTyping(int conversationId) =>
      '/api/mobile/conversations/$conversationId/typing';
  static String mobileEventConversation(String key) =>
      '/api/mobile/events/$key/conversation';
  static String mobileRehearsalConversation(int rehearsalId) =>
      '/api/mobile/rehearsals/$rehearsalId/conversation';
  static String mobileBookingConversation(int bookingId) =>
      '/api/mobile/bookings/$bookingId/conversation';
  static String mobileMessageAttachment(int messageId, int attachmentId) =>
      '/api/mobile/messages/$messageId/attachments/$attachmentId';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/models_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/data/models/ lib/core/network/api_endpoints.dart test/features/chat/models_test.dart
git commit -m "feat(chat): conversation/message/participant/contact models + endpoints

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: ChatRepository

**Files:**
- Create: `lib/features/chat/data/chat_repository.dart`
- Test: `test/features/chat/chat_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 models + endpoints; `apiClientProvider` (`lib/core/network/api_client.dart`, exposes `.dio`).
- Produces:
  - `typedef ThreadPage = ({Conversation conversation, List<ChatMessage> messages, List<ChatParticipant> participants, String channel, bool hasMore});`
  - `class ChatImageUpload { final List<int> bytes; final String filename; }`
  - `class ChatRepository` with: `Future<List<Conversation>> listConversations()`, `Future<Conversation> openDm(int userId)`, `Future<List<ChatContact>> contacts()`, `Future<ThreadPage> topicThread({required String kind, required String idOrKey})` (kind: `'events'|'rehearsals'|'bookings'`), `Future<ThreadPage> messages(int conversationId, {int? beforeId})`, `Future<ChatMessage> sendMessage(int conversationId, {String? body, List<ChatImageUpload> images = const []})`, `Future<ChatMessage> editMessage(int messageId, String body)`, `Future<void> deleteMessage(int messageId)`, `Future<void> markRead(int conversationId, int lastReadMessageId)`, `Future<void> sendTyping(int conversationId)`, `String attachmentUrl(int messageId, int attachmentId)` (absolute URL: dio baseUrl + path).
  - `final chatRepositoryProvider = Provider<ChatRepository>(…)`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/chat_repository_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';

import '../../helpers/test_harness.dart';

void main() {
  Dio dioReturning(Map<String, dynamic> body) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async => json(200, body));
    return dio;
  }

  final threadJson = {
    'conversation': {'id': 5, 'type': 'topic', 'title': 'Gig at Blue Room'},
    'messages': [
      {
        'id': 1,
        'conversation_id': 5,
        'user_id': 2,
        'user_name': 'Eddie',
        'body': 'sound check at 6',
        'created_at': '2026-07-12T14:00:00Z',
      },
    ],
    'participants': [
      {'user_id': 2, 'name': 'Eddie', 'last_read_at': '2026-07-12T14:00:00Z'},
    ],
    'channel': 'private-conversation.5',
    'has_more': false,
  };

  test('listConversations parses list', () async {
    final repo = ChatRepository(dioReturning({
      'conversations': [
        {'id': 5, 'type': 'band', 'title': 'The Band', 'unread_count': 2},
      ],
    }));
    final list = await repo.listConversations();
    expect(list.single.id, 5);
    expect(list.single.unreadCount, 2);
  });

  test('openDm parses conversation', () async {
    final repo = ChatRepository(dioReturning({
      'conversation': {'id': 9, 'type': 'dm', 'title': 'Sam'},
    }));
    final c = await repo.openDm(3);
    expect(c.id, 9);
    expect(c.type, 'dm');
  });

  test('topicThread and messages parse a ThreadPage', () async {
    final repo = ChatRepository(dioReturning(threadJson));
    final page = await repo.topicThread(kind: 'events', idOrKey: 'abc123');
    expect(page.conversation.id, 5);
    expect(page.messages.single.body, 'sound check at 6');
    expect(page.participants.single.userId, 2);
    expect(page.channel, 'private-conversation.5');
    expect(page.hasMore, isFalse);

    final page2 = await repo.messages(5, beforeId: 100);
    expect(page2.conversation.id, 5);
  });

  test('sendMessage and editMessage parse the message envelope', () async {
    final repo = ChatRepository(dioReturning({
      'message': {
        'id': 2,
        'conversation_id': 5,
        'user_id': 2,
        'user_name': 'Eddie',
        'body': 'hi',
        'created_at': '2026-07-12T15:00:00Z',
      },
    }));
    final sent = await repo.sendMessage(5, body: 'hi');
    expect(sent.id, 2);
    final edited = await repo.editMessage(2, 'hi!');
    expect(edited.id, 2);
  });

  test('attachmentUrl is absolute', () {
    final repo = ChatRepository(Dio(BaseOptions(baseUrl: 'http://test.local')));
    expect(repo.attachmentUrl(2, 7),
        'http://test.local/api/mobile/messages/2/attachments/7');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_repository_test.dart`
Expected: FAIL — `Couldn't resolve the package …/chat_repository.dart`.

- [ ] **Step 3: Write the repository**

```dart
// lib/features/chat/data/chat_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/chat_contact.dart';
import 'models/chat_message.dart';
import 'models/chat_participant.dart';
import 'models/conversation.dart';

/// One page of a conversation thread, as returned by the thread endpoints.
typedef ThreadPage = ({
  Conversation conversation,
  List<ChatMessage> messages,
  List<ChatParticipant> participants,
  String channel,
  bool hasMore,
});

/// An image ready for multipart upload (already picked + downscaled by the
/// composer via image_picker's imageQuality/maxWidth).
class ChatImageUpload {
  const ChatImageUpload({required this.bytes, required this.filename});
  final List<int> bytes;
  final String filename;
}

class ChatRepository {
  ChatRepository(this._dio);
  final Dio _dio;

  ThreadPage _parseThread(Map<String, dynamic> data) => (
        conversation:
            Conversation.fromJson(data['conversation'] as Map<String, dynamic>),
        messages: (data['messages'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList(),
        participants: (data['participants'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ChatParticipant.fromJson)
            .toList(),
        channel: data['channel'] as String? ?? '',
        hasMore: data['has_more'] as bool? ?? false,
      );

  Future<List<Conversation>> listConversations() async {
    final res =
        await _dio.get<Map<String, dynamic>>(ApiEndpoints.mobileConversations);
    return (res.data?['conversations'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Conversation.fromJson)
        .toList();
  }

  Future<Conversation> openDm(int userId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileConversationsDm,
      data: {'user_id': userId},
    );
    return Conversation.fromJson(res.data!['conversation'] as Map<String, dynamic>);
  }

  Future<List<ChatContact>> contacts() async {
    final res =
        await _dio.get<Map<String, dynamic>>(ApiEndpoints.mobileChatContacts);
    return (res.data?['contacts'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ChatContact.fromJson)
        .toList();
  }

  /// Resolve-or-create the comment thread for an event ('events', key),
  /// rehearsal ('rehearsals', id) or booking ('bookings', id).
  Future<ThreadPage> topicThread(
      {required String kind, required String idOrKey}) async {
    final path = switch (kind) {
      'events' => ApiEndpoints.mobileEventConversation(idOrKey),
      'rehearsals' =>
        ApiEndpoints.mobileRehearsalConversation(int.parse(idOrKey)),
      'bookings' => ApiEndpoints.mobileBookingConversation(int.parse(idOrKey)),
      _ => throw ArgumentError('Unknown topic kind: $kind'),
    };
    final res = await _dio.get<Map<String, dynamic>>(path);
    return _parseThread(res.data!);
  }

  Future<ThreadPage> messages(int conversationId, {int? beforeId}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileConversationMessages(conversationId),
      queryParameters: {if (beforeId != null) 'before': beforeId},
    );
    return _parseThread(res.data!);
  }

  Future<ChatMessage> sendMessage(
    int conversationId, {
    String? body,
    List<ChatImageUpload> images = const [],
  }) async {
    final form = FormData.fromMap({
      if (body != null && body.isNotEmpty) 'body': body,
      'images[]': [
        for (final img in images)
          MultipartFile.fromBytes(img.bytes, filename: img.filename),
      ],
    });
    final res = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileConversationMessages(conversationId),
      data: form,
    );
    return ChatMessage.fromJson(res.data!['message'] as Map<String, dynamic>);
  }

  Future<ChatMessage> editMessage(int messageId, String body) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileMessage(messageId),
      data: {'body': body},
    );
    return ChatMessage.fromJson(res.data!['message'] as Map<String, dynamic>);
  }

  Future<void> deleteMessage(int messageId) =>
      _dio.delete<void>(ApiEndpoints.mobileMessage(messageId));

  Future<void> markRead(int conversationId, int lastReadMessageId) =>
      _dio.post<void>(
        ApiEndpoints.mobileConversationRead(conversationId),
        data: {'last_read_message_id': lastReadMessageId},
      );

  Future<void> sendTyping(int conversationId) =>
      _dio.post<void>(ApiEndpoints.mobileConversationTyping(conversationId));

  /// Absolute URL for an authenticated attachment image (for AuthThumbnail).
  String attachmentUrl(int messageId, int attachmentId) =>
      _dio.options.baseUrl +
      ApiEndpoints.mobileMessageAttachment(messageId, attachmentId);
}

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(apiClientProvider).dio),
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/chat_repository_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/data/chat_repository.dart test/features/chat/chat_repository_test.dart
git commit -m "feat(chat): ChatRepository over the conversations API

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Conversation-list + unread providers

**Files:**
- Create: `lib/features/chat/providers/conversations_provider.dart`
- Test: `test/features/chat/conversations_provider_test.dart`

**Interfaces:**
- Consumes: `chatRepositoryProvider`, `Conversation` (Tasks 1–2).
- Produces: `final chatConversationsProvider = FutureProvider<List<Conversation>>`, `final chatUnreadTotalProvider = Provider<int>` (0 while loading/error). Both are invalidation targets for realtime (Task 8).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/conversations_provider_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';

import '../../helpers/test_harness.dart';

void main() {
  ProviderContainer withConversations(List<Map<String, dynamic>> conversations) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter =
          StubAdapter((_) async => json(200, {'conversations': conversations}));
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('chatConversationsProvider loads the list', () async {
    final c = withConversations([
      {'id': 1, 'type': 'dm', 'title': 'Sam', 'unread_count': 2},
      {'id': 2, 'type': 'band', 'title': 'The Band', 'unread_count': 1},
    ]);
    final list = await c.read(chatConversationsProvider.future);
    expect(list.length, 2);
  });

  test('chatUnreadTotalProvider sums unread counts', () async {
    final c = withConversations([
      {'id': 1, 'type': 'dm', 'title': 'Sam', 'unread_count': 2},
      {'id': 2, 'type': 'band', 'title': 'The Band', 'unread_count': 1},
    ]);
    await c.read(chatConversationsProvider.future);
    expect(c.read(chatUnreadTotalProvider), 3);
  });

  test('chatUnreadTotalProvider is 0 while unloaded', () {
    final c = withConversations([]);
    expect(c.read(chatUnreadTotalProvider), 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/conversations_provider_test.dart`
Expected: FAIL — package resolution error for `conversations_provider.dart`.

- [ ] **Step 3: Write the providers**

```dart
// lib/features/chat/providers/conversations_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_repository.dart';
import '../data/models/conversation.dart';

/// DM + band-channel list for the Messages screen. Invalidated by realtime
/// 'message' signals (band + user channels) and on thread reads.
final chatConversationsProvider = FutureProvider<List<Conversation>>(
  (ref) => ref.watch(chatRepositoryProvider).listConversations(),
);

/// Total unread across all conversations; 0 while loading or on error.
/// Drives the badge on the More-tab Messages tile.
final chatUnreadTotalProvider = Provider<int>((ref) {
  final list = ref.watch(chatConversationsProvider).valueOrNull;
  if (list == null) return 0;
  return list.fold(0, (sum, c) => sum + c.unreadCount);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/conversations_provider_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/providers/conversations_provider.dart test/features/chat/conversations_provider_test.dart
git commit -m "feat(chat): conversation list + unread total providers

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Messages screen, new-DM contacts screen, routes, More tile

**Files:**
- Create: `lib/features/chat/screens/messages_screen.dart`
- Create: `lib/features/chat/screens/new_message_screen.dart`
- Modify: `lib/core/config/router.dart` (add three `GoRoute`s after the `/stats` route, ~line 458; add imports)
- Modify: `lib/features/more/screens/more_screen.dart` (add Messages tile after the Switch Band row, before Finances)
- Test: `test/features/chat/messages_screen_test.dart`

**Interfaces:**
- Consumes: `chatConversationsProvider`, `chatUnreadTotalProvider`, `chatRepositoryProvider.openDm/contacts` (Tasks 2–3).
- Produces: routes `/messages` (list), `/messages/new` (contact picker), `/conversations/:id` (thread — screen itself lands in Task 6; register the route THERE, not here). `MessagesScreen`, `NewMessageScreen` widgets.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/chat/messages_screen_test.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/models/conversation.dart';
import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';
import 'package:tts_bandmate/features/chat/screens/messages_screen.dart';

void main() {
  testWidgets('shows conversations with unread badge', (tester) async {
    final container = ProviderContainer(overrides: [
      chatConversationsProvider.overrideWith((ref) async => [
            Conversation(
                id: 1,
                type: 'dm',
                title: 'Sam',
                lastMessagePreview: 'see you at 8',
                unreadCount: 2),
            const Conversation(id: 2, type: 'band', title: 'The Band'),
          ]),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(home: MessagesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('see you at 8'), findsOneWidget);
    expect(find.text('The Band'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // unread badge
  });

  testWidgets('shows empty state when no conversations', (tester) async {
    final container = ProviderContainer(overrides: [
      chatConversationsProvider.overrideWith((ref) async => []),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(home: MessagesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No messages yet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/messages_screen_test.dart`
Expected: FAIL — package resolution error for `messages_screen.dart`.

- [ ] **Step 3: Write the Messages screen**

```dart
// lib/features/chat/screens/messages_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/models/conversation.dart';
import '../providers/conversations_provider.dart';

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(chatConversationsProvider);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Messages'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => context.push('/messages/new'),
          child: const Icon(CupertinoIcons.square_pencil),
        ),
      ),
      child: SafeArea(
        child: listAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => ErrorView(
            message: ErrorView.friendlyMessage(e),
            onRetry: () => ref.invalidate(chatConversationsProvider),
          ),
          data: (conversations) {
            if (conversations.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.chat_bubble_2,
                        size: 44, color: context.tertiaryText),
                    const SizedBox(height: 8),
                    Text('No messages yet',
                        style: TextStyle(color: context.secondaryText)),
                  ],
                ),
              );
            }
            return ListView.builder(
              itemCount: conversations.length,
              itemBuilder: (_, i) => _ConversationRow(
                conversation: conversations[i],
                onTap: () => context.push(
                  '/conversations/${conversations[i].id}',
                  extra: {'title': conversations[i].title},
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.conversation, required this.onTap});
  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.unreadCount > 0;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              conversation.type == 'dm'
                  ? CupertinoIcons.person_crop_circle
                  : CupertinoIcons.person_3_fill,
              size: 34,
              color: context.secondaryText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                      color: context.primaryText,
                    ),
                  ),
                  if (conversation.lastMessagePreview != null)
                    Text(
                      conversation.lastMessagePreview!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: context.secondaryText),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (conversation.lastMessageAt != null)
                  Text(
                    timeago.format(conversation.lastMessageAt!),
                    style: TextStyle(fontSize: 12, color: context.tertiaryText),
                  ),
                if (hasUnread)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${conversation.unreadCount}',
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

```dart
// lib/features/chat/screens/new_message_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_contact.dart';

/// Contacts you can DM (fetched fresh each open; small list).
final chatContactsProvider = FutureProvider.autoDispose<List<ChatContact>>(
  (ref) => ref.watch(chatRepositoryProvider).contacts(),
);

class NewMessageScreen extends ConsumerStatefulWidget {
  const NewMessageScreen({super.key});

  @override
  ConsumerState<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends ConsumerState<NewMessageScreen> {
  bool _opening = false;

  Future<void> _openDm(ChatContact contact) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final conversation =
          await ref.read(chatRepositoryProvider).openDm(contact.id);
      if (!mounted) return;
      context.pushReplacement(
        '/conversations/${conversation.id}',
        extra: {'title': conversation.title},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Could not start conversation'),
          content: Text(ErrorView.friendlyMessage(e)),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(chatContactsProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('New Message')),
      child: SafeArea(
        child: contactsAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => ErrorView(
            message: ErrorView.friendlyMessage(e),
            onRetry: () => ref.invalidate(chatContactsProvider),
          ),
          data: (contacts) => ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (_, i) {
              final contact = contacts[i];
              return CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _opening ? null : () => _openDm(contact),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.person_crop_circle,
                          size: 30, color: context.secondaryText),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(contact.name,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: context.primaryText)),
                            if (contact.context.isNotEmpty)
                              Text(
                                contact.isSub
                                    ? '${contact.context} · Sub'
                                    : contact.context,
                                style: TextStyle(
                                    fontSize: 13, color: context.secondaryText),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Register the two routes**

In `lib/core/config/router.dart` add imports (with the other feature imports):

```dart
import '../../features/chat/screens/messages_screen.dart';
import '../../features/chat/screens/new_message_screen.dart';
```

After the `/stats` `GoRoute` (the block ending `builder: (_, __) => const UserStatsScreen(),` ~line 458) add:

```dart
      // Messages — no bottom nav, pushed from More screen
      GoRoute(
        path: '/messages',
        builder: (_, __) => const MessagesScreen(),
      ),
      GoRoute(
        path: '/messages/new',
        builder: (_, __) => const NewMessageScreen(),
      ),
```

(The `/conversations/:id` route is registered in Task 6 with the thread screen.)

- [ ] **Step 5: Add the More-tab tile with unread badge**

In `lib/features/more/screens/more_screen.dart` add imports:

```dart
import '../../chat/providers/conversations_provider.dart';
```

In `build`, after `final isOwner = …;` add:

```dart
    final unread = ref.watch(chatUnreadTotalProvider);
```

Insert as the first `NavRow` after the Switch Band block (before the Finances row):

```dart
          NavRow(
            title: 'Messages',
            subtitle: unread > 0 ? '$unread unread' : null,
            leading: Icon(
              CupertinoIcons.chat_bubble_2,
              size: 22,
              color: unread > 0
                  ? CupertinoColors.activeBlue.resolveFrom(context)
                  : context.secondaryText,
            ),
            onTap: () => context.push('/messages'),
          ),
```

- [ ] **Step 6: Run tests + analyzer**

Run: `flutter test test/features/chat/messages_screen_test.dart && flutter analyze`
Expected: PASS (2 tests); analyze: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/screens/ lib/core/config/router.dart lib/features/more/screens/more_screen.dart test/features/chat/messages_screen_test.dart
git commit -m "feat(chat): Messages + New Message screens, routes, More tile with unread badge

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Thread provider (live channel, send/edit/delete/read/typing)

**Files:**
- Create: `lib/features/chat/providers/chat_thread_provider.dart`
- Test: `test/features/chat/chat_thread_provider_test.dart`

**Interfaces:**
- Consumes: `ChatRepository` + models, `pusherConnectionProvider`, `chatConversationsProvider` (invalidated after `markRead` so unread badges refresh), `authProvider` (`AuthAuthenticated.user.id` for own-message logic).
- Produces:
  - `typedef ChatChannelBinder = void Function(String channel, void Function(String eventName, Map<String, dynamic> data) onEvent);`
  - `final chatChannelBinderProvider = Provider<ChatChannelBinder>` (test seam, mirrors `plannerStreamBinderProvider`)
  - `final chatTypingTtlProvider = Provider<Duration>` (default 5s; zero in tests)
  - `class ChatThreadState { List<ChatMessage> messages; List<ChatParticipant> participants; Conversation? conversation; bool isLoading; bool isLoadingMore; bool hasMore; bool isSending; String? error; Map<int, String> typingUsers; }` with `copyWith`
  - `class ChatThreadNotifier extends Notifier<ChatThreadState>` with `Future<void> load()`, `Future<void> loadMore()`, `Future<void> send({String? text, List<ChatImageUpload> images})`, `Future<void> editMsg(int messageId, String body)`, `Future<void> deleteMsg(int messageId)`, `Future<void> markRead()`, `void notifyTyping()`
  - `final chatThreadProvider = NotifierProvider.family<ChatThreadNotifier, ChatThreadState, int>` (family key = conversation id)
  - Pure helper `int seenByOthersCount(ChatMessage message, List<ChatParticipant> participants, int currentUserId)`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/chat_thread_provider_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_message.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_participant.dart';
import 'package:tts_bandmate/features/chat/providers/chat_thread_provider.dart';

import '../../helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final threadJson = {
    'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
    'messages': [
      {
        'id': 1,
        'conversation_id': 5,
        'user_id': 2,
        'user_name': 'Eddie',
        'body': 'hey',
        'created_at': '2026-07-12T14:00:00Z',
      },
    ],
    'participants': [
      {'user_id': 2, 'name': 'Eddie', 'last_read_at': '2026-07-12T14:00:00Z'},
      {'user_id': 3, 'name': 'Sam', 'last_read_at': null},
    ],
    'channel': 'private-conversation.5',
    'has_more': false,
  };

  late List<String> boundChannels;
  late void Function(String, Map<String, dynamic>)? capturedHandler;

  ProviderContainer makeContainer() {
    boundChannels = [];
    capturedHandler = null;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async => json(200, threadJson));
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatTypingTtlProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) {
        boundChannels.add(channel);
        capturedHandler = onEvent;
      }),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('load fetches the page and binds the live channel', () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();
    final state = c.read(chatThreadProvider(5));
    expect(state.messages.single.body, 'hey');
    expect(state.participants.length, 2);
    expect(boundChannels, ['private-conversation.5']);
  });

  test('message.created appends; message.deleted tombstones', () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();

    capturedHandler!('message.created', {
      'message': {
        'id': 2,
        'conversation_id': 5,
        'user_id': 3,
        'user_name': 'Sam',
        'body': 'yo',
        'created_at': '2026-07-12T14:01:00Z',
      },
    });
    expect(c.read(chatThreadProvider(5)).messages.length, 2);

    capturedHandler!('message.deleted', {'message_id': 2});
    final state = c.read(chatThreadProvider(5));
    expect(state.messages.length, 2);
    expect(state.messages.last.isDeleted, isTrue);
  });

  test('duplicate message.created (own send echo) is ignored', () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();
    final echo = {
      'message': {
        'id': 1,
        'conversation_id': 5,
        'user_id': 2,
        'user_name': 'Eddie',
        'body': 'hey',
        'created_at': '2026-07-12T14:00:00Z',
      },
    };
    capturedHandler!('message.created', echo);
    expect(c.read(chatThreadProvider(5)).messages.length, 1);
  });

  test('conversation.read updates participant lastReadAt', () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();
    capturedHandler!('conversation.read',
        {'user_id': 3, 'last_read_at': '2026-07-12T14:05:00Z'});
    final sam = c
        .read(chatThreadProvider(5))
        .participants
        .firstWhere((p) => p.userId == 3);
    expect(sam.lastReadAt, isNotNull);
  });

  test('conversation.typing adds then expires a typing user', () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();
    capturedHandler!('conversation.typing', {'user_id': 3, 'name': 'Sam'});
    expect(c.read(chatThreadProvider(5)).typingUsers, {3: 'Sam'});
    // TTL is zero in tests: a timer tick clears it.
    await Future<void>.delayed(Duration.zero);
    expect(c.read(chatThreadProvider(5)).typingUsers, isEmpty);
  });

  test('seenByOthersCount counts other participants who read past the message',
      () {
    final msg = ChatMessage(
      id: 1,
      conversationId: 5,
      userId: 2,
      userName: 'Eddie',
      body: 'hey',
      createdAt: DateTime.utc(2026, 7, 12, 14),
    );
    final participants = [
      ChatParticipant(
          userId: 2, name: 'Eddie', lastReadAt: DateTime.utc(2026, 7, 12, 15)),
      ChatParticipant(
          userId: 3, name: 'Sam', lastReadAt: DateTime.utc(2026, 7, 12, 14, 30)),
      const ChatParticipant(userId: 4, name: 'Lee'),
    ];
    expect(seenByOthersCount(msg, participants, 2), 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_thread_provider_test.dart`
Expected: FAIL — package resolution error for `chat_thread_provider.dart`.

- [ ] **Step 3: Write the provider**

```dart
// lib/features/chat/providers/chat_thread_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pusher_connection.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_message.dart';
import '../data/models/chat_participant.dart';
import '../data/models/conversation.dart';
import 'conversations_provider.dart';

typedef ChatChannelBinder = void Function(
  String channel,
  void Function(String eventName, Map<String, dynamic> data) onEvent,
);

/// Production binder: subscribes to the per-conversation private channel via
/// the shared PusherConnection (same pattern as plannerStreamBinderProvider).
final chatChannelBinderProvider = Provider<ChatChannelBinder>((ref) {
  return (channel, onEvent) async {
    final unsubscribe = await ref
        .read(pusherConnectionProvider)
        .subscribe(channel, (eventName, data) => onEvent(eventName, data));
    if (unsubscribe != null) {
      ref.onDispose(() {
        unsubscribe().catchError((Object e) {
          debugPrint('chatThread: unsubscribe failed: $e');
        });
      });
    }
  };
});

/// How long a peer's typing indicator stays visible after their last typing
/// event. Overridden to zero in tests.
final chatTypingTtlProvider =
    Provider<Duration>((_) => const Duration(seconds: 5));

/// Other participants (excluding [currentUserId]) whose lastReadAt is at or
/// past the message's createdAt — i.e. they've seen it.
int seenByOthersCount(
  ChatMessage message,
  List<ChatParticipant> participants,
  int currentUserId,
) =>
    participants
        .where((p) =>
            p.userId != currentUserId &&
            p.lastReadAt != null &&
            !p.lastReadAt!.isBefore(message.createdAt))
        .length;

class ChatThreadState {
  const ChatThreadState({
    this.messages = const [],
    this.participants = const [],
    this.conversation,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.isSending = false,
    this.error,
    this.typingUsers = const {},
  });

  final List<ChatMessage> messages; // oldest → newest
  final List<ChatParticipant> participants;
  final Conversation? conversation;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isSending;
  final String? error;
  final Map<int, String> typingUsers; // userId → name

  ChatThreadState copyWith({
    List<ChatMessage>? messages,
    List<ChatParticipant>? participants,
    Conversation? conversation,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    bool? isSending,
    String? Function()? error,
    Map<int, String>? typingUsers,
  }) =>
      ChatThreadState(
        messages: messages ?? this.messages,
        participants: participants ?? this.participants,
        conversation: conversation ?? this.conversation,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        isSending: isSending ?? this.isSending,
        error: error != null ? error() : this.error,
        typingUsers: typingUsers ?? this.typingUsers,
      );
}

class ChatThreadNotifier extends Notifier<ChatThreadState> {
  ChatThreadNotifier(this._conversationId);
  final int _conversationId;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  int? get _currentUserId {
    final auth = ref.read(authProvider).value;
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  final Map<int, Timer> _typingTimers = {};
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _bound = false;

  @override
  ChatThreadState build() {
    ref.onDispose(() {
      for (final t in _typingTimers.values) {
        t.cancel();
      }
    });
    return const ChatThreadState();
  }

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final page = await _repo.messages(_conversationId);
      state = state.copyWith(
        messages: page.messages,
        participants: page.participants,
        conversation: page.conversation,
        hasMore: page.hasMore,
        isLoading: false,
      );
      _bind(page.channel);
      await markRead();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: () => e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.messages(_conversationId,
          beforeId: state.messages.first.id);
      state = state.copyWith(
        messages: [...page.messages, ...state.messages],
        hasMore: page.hasMore,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: () => e.toString());
    }
  }

  Future<void> send({String? text, List<ChatImageUpload> images = const []}) async {
    final body = text?.trim() ?? '';
    if (body.isEmpty && images.isEmpty) return;
    state = state.copyWith(isSending: true, error: () => null);
    try {
      final message =
          await _repo.sendMessage(_conversationId, body: body, images: images);
      _appendIfNew(message);
      state = state.copyWith(isSending: false);
      await markRead();
    } catch (e) {
      state = state.copyWith(isSending: false, error: () => e.toString());
    }
  }

  Future<void> editMsg(int messageId, String body) async {
    try {
      final updated = await _repo.editMessage(messageId, body);
      _replace(updated);
    } catch (e) {
      state = state.copyWith(error: () => e.toString());
    }
  }

  Future<void> deleteMsg(int messageId) async {
    try {
      await _repo.deleteMessage(messageId);
      _tombstone(messageId);
    } catch (e) {
      state = state.copyWith(error: () => e.toString());
    }
  }

  /// Marks the newest message read and refreshes the conversation list so
  /// unread badges drop. Best-effort.
  Future<void> markRead() async {
    final last = state.messages.isNotEmpty ? state.messages.last : null;
    if (last == null) return;
    try {
      await _repo.markRead(_conversationId, last.id);
      ref.invalidate(chatConversationsProvider);
    } catch (e) {
      debugPrint('chatThread: markRead failed: $e');
    }
  }

  /// Called by the composer on text changes. Throttled to one POST per 3s.
  void notifyTyping() {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) < const Duration(seconds: 3)) return;
    _lastTypingSent = now;
    _repo.sendTyping(_conversationId).catchError((Object e) {
      debugPrint('chatThread: typing failed: $e');
    });
  }

  void _bind(String channel) {
    if (_bound || channel.isEmpty) return;
    _bound = true;
    ref.read(chatChannelBinderProvider)(channel, _onChannelEvent);
  }

  void _onChannelEvent(String eventName, Map<String, dynamic> data) {
    switch (eventName) {
      case 'message.created':
        final raw = data['message'];
        if (raw is! Map<String, dynamic>) return;
        _appendIfNew(ChatMessage.fromJson(raw));
        // Someone else wrote while we're looking at the thread: mark it read.
        markRead();
      case 'message.updated':
        final raw = data['message'];
        if (raw is! Map<String, dynamic>) return;
        _replace(ChatMessage.fromJson(raw));
      case 'message.deleted':
        final id = (data['message_id'] as num?)?.toInt();
        if (id != null) _tombstone(id);
      case 'conversation.read':
        final userId = (data['user_id'] as num?)?.toInt();
        final at = DateTime.tryParse(data['last_read_at'] as String? ?? '');
        if (userId == null || at == null) return;
        state = state.copyWith(participants: [
          for (final p in state.participants)
            p.userId == userId ? p.copyWith(lastReadAt: at) : p,
        ]);
      case 'conversation.typing':
        final userId = (data['user_id'] as num?)?.toInt();
        final name = data['name'] as String? ?? '';
        if (userId == null || userId == _currentUserId) return;
        state = state
            .copyWith(typingUsers: {...state.typingUsers, userId: name});
        _typingTimers[userId]?.cancel();
        _typingTimers[userId] = Timer(ref.read(chatTypingTtlProvider), () {
          final next = {...state.typingUsers}..remove(userId);
          state = state.copyWith(typingUsers: next);
        });
    }
  }

  void _appendIfNew(ChatMessage message) {
    if (state.messages.any((m) => m.id == message.id)) return;
    state = state.copyWith(messages: [...state.messages, message]);
  }

  void _replace(ChatMessage message) {
    state = state.copyWith(messages: [
      for (final m in state.messages) m.id == message.id ? message : m,
    ]);
  }

  void _tombstone(int messageId) {
    state = state.copyWith(messages: [
      for (final m in state.messages)
        m.id == messageId ? m.copyWith(isDeleted: true, body: '') : m,
    ]);
  }
}

final chatThreadProvider =
    NotifierProvider.family<ChatThreadNotifier, ChatThreadState, int>(
  ChatThreadNotifier.new,
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/chat_thread_provider_test.dart`
Expected: PASS (6 tests). If `markRead` inside `load()` breaks a test because the stub returns the thread JSON for the read POST too, that's fine — the stub returns 200 and the JSON parse isn't performed for `markRead` (void). If `authProvider` initialization throws in the container, override it is NOT needed: `_currentUserId` is only read in the typing branch and `ref.read(authProvider)` with no auth returns loading state (`value` null) — `_currentUserId` is null and the typing event from user 3 still passes the `userId == _currentUserId` guard.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/providers/chat_thread_provider.dart test/features/chat/chat_thread_provider_test.dart
git commit -m "feat(chat): thread notifier with live channel, receipts, typing

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Thread screen (bubbles, composer, images, receipts, context menu)

**Files:**
- Create: `lib/features/chat/screens/conversation_thread_screen.dart`
- Modify: `lib/core/config/router.dart` (add `/conversations/:id` route + import)
- Test: `test/features/chat/conversation_thread_screen_test.dart`

**Interfaces:**
- Consumes: `chatThreadProvider`, `ChatThreadState`, `seenByOthersCount`, `chatRepositoryProvider.attachmentUrl`, `AuthThumbnail` (`lib/shared/widgets/auth_thumbnail.dart`), `authProvider` for current user id, `image_picker`.
- Produces: `ConversationThreadScreen({required int conversationId, String? title})`; route `/conversations/:id` reading `extra?['title']`.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/chat/conversation_thread_screen_test.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/providers/chat_thread_provider.dart';
import 'package:tts_bandmate/features/chat/screens/conversation_thread_screen.dart';
import 'package:dio/dio.dart';

import '../../helpers/test_harness.dart';

void main() {
  testWidgets('renders messages, typing indicator, and deleted tombstone',
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
                'body': 'you around?',
                'created_at': '2026-07-12T14:00:00Z',
              },
              {
                'id': 2,
                'conversation_id': 5,
                'user_id': 3,
                'user_name': 'Sam',
                'body': '',
                'is_deleted': true,
                'created_at': '2026-07-12T14:01:00Z',
              },
            ],
            'participants': [
              {'user_id': 3, 'name': 'Sam', 'last_read_at': null},
            ],
            'channel': 'private-conversation.5',
            'has_more': false,
          }));

    void Function(String, Map<String, dynamic>)? handler;
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatChannelBinderProvider
          .overrideWithValue((channel, onEvent) => handler = onEvent),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(conversationId: 5, title: 'Sam'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('you around?'), findsOneWidget);
    expect(find.text('Message deleted'), findsOneWidget);

    handler!('conversation.typing', {'user_id': 3, 'name': 'Sam'});
    await tester.pump();
    expect(find.text('Sam is typing…'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/conversation_thread_screen_test.dart`
Expected: FAIL — package resolution error for `conversation_thread_screen.dart`.

- [ ] **Step 3: Write the screen**

```dart
// lib/features/chat/screens/conversation_thread_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/widgets/auth_thumbnail.dart';
import '../../../shared/widgets/error_view.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_message.dart';
import '../providers/chat_thread_provider.dart';

class ConversationThreadScreen extends ConsumerStatefulWidget {
  const ConversationThreadScreen({
    super.key,
    required this.conversationId,
    this.title,
  });

  final int conversationId;
  final String? title;

  @override
  ConsumerState<ConversationThreadScreen> createState() =>
      _ConversationThreadScreenState();
}

class _ConversationThreadScreenState
    extends ConsumerState<ConversationThreadScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<XFile> _pendingImages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatThreadProvider(widget.conversationId).notifier).load();
    });
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 40) {
      ref.read(chatThreadProvider(widget.conversationId).notifier).loadMore();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickImages() async {
    // image_picker downscales/compresses on-device; no extra package needed.
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 80,
      maxWidth: 2048,
      limit: 4,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _pendingImages
        ..clear()
        ..addAll(picked.take(4));
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingImages.isEmpty) return;
    final uploads = <ChatImageUpload>[
      for (final x in _pendingImages)
        ChatImageUpload(bytes: await x.readAsBytes(), filename: x.name),
    ];
    _controller.clear();
    setState(() => _pendingImages.clear());
    await ref
        .read(chatThreadProvider(widget.conversationId).notifier)
        .send(text: text, images: uploads);
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final auth = ref.read(authProvider).value;
    final currentUserId =
        auth is AuthAuthenticated ? auth.user.id : null;
    final state = ref.read(chatThreadProvider(widget.conversationId));
    final isOwn = message.userId == currentUserId;
    final canModerate = state.conversation?.canModerate ?? false;
    if (message.isDeleted || (!isOwn && !canModerate)) return;

    final notifier =
        ref.read(chatThreadProvider(widget.conversationId).notifier);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          if (isOwn && message.attachments.isEmpty)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                _showEditDialog(message);
              },
              child: const Text('Edit'),
            ),
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

  Future<void> _showEditDialog(ChatMessage message) async {
    final editController = TextEditingController(text: message.body);
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Edit message'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(controller: editController, maxLines: null),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final text = editController.text.trim();
              Navigator.pop(dialogContext);
              if (text.isNotEmpty && text != message.body) {
                ref
                    .read(chatThreadProvider(widget.conversationId).notifier)
                    .editMsg(message.id, text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatThreadProvider(widget.conversationId), (previous, next) {
      final grew = previous == null ||
          next.messages.length != previous.messages.length;
      if (grew) _scrollToBottom();
    });

    final state = ref.watch(chatThreadProvider(widget.conversationId));
    final auth = ref.watch(authProvider).value;
    final currentUserId = auth is AuthAuthenticated ? auth.user.id : -1;
    final title = widget.title ?? state.conversation?.title ?? 'Conversation';

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(title)),
      child: SafeArea(
        child: Column(
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  ErrorView.friendlyMessage(state.error!),
                  style: TextStyle(
                      color: CupertinoColors.systemRed.resolveFrom(context)),
                ),
              ),
            Expanded(
              child: state.isLoading && state.messages.isEmpty
                  ? const Center(child: CupertinoActivityIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount:
                          state.messages.length + (state.isLoadingMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (state.isLoadingMore && i == 0) {
                          return const Padding(
                            padding: EdgeInsets.all(8),
                            child: Center(child: CupertinoActivityIndicator()),
                          );
                        }
                        final idx = state.isLoadingMore ? i - 1 : i;
                        final message = state.messages[idx];
                        final isLast = idx == state.messages.length - 1;
                        return _MessageBubble(
                          message: message,
                          isOwn: message.userId == currentUserId,
                          showSeen: isLast &&
                              message.userId == currentUserId &&
                              seenByOthersCount(message, state.participants,
                                      currentUserId) >
                                  0,
                          isDm: state.conversation?.type == 'dm',
                          onLongPress: () => _showMessageActions(message),
                        );
                      },
                    ),
            ),
            if (state.typingUsers.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    state.typingUsers.length == 1
                        ? '${state.typingUsers.values.first} is typing…'
                        : 'Several people are typing…',
                    style: TextStyle(fontSize: 13, color: context.secondaryText),
                  ),
                ),
              ),
            if (_pendingImages.isNotEmpty)
              SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final img in _pendingImages)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: FutureBuilder(
                                  future: img.readAsBytes(),
                                  builder: (_, snap) => snap.hasData
                                      ? Image.memory(snap.data!,
                                          fit: BoxFit.cover)
                                      : const CupertinoActivityIndicator(),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _pendingImages.remove(img)),
                                child: const Icon(
                                    CupertinoIcons.xmark_circle_fill,
                                    size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            _Composer(
              controller: _controller,
              isBusy: state.isSending,
              onSend: _send,
              onPickImages: _pickImages,
              onChanged: (_) => ref
                  .read(chatThreadProvider(widget.conversationId).notifier)
                  .notifyTyping(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.isOwn,
    required this.showSeen,
    required this.isDm,
    required this.onLongPress,
  });

  final ChatMessage message;
  final bool isOwn;
  final bool showSeen;
  final bool isDm;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(chatRepositoryProvider);
    return Column(
      crossAxisAlignment:
          isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isOwn && !isDm)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              message.userName,
              style: TextStyle(fontSize: 12, color: context.secondaryText),
            ),
          ),
        GestureDetector(
          onLongPress: message.isDeleted ? null : onLongPress,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8),
            decoration: BoxDecoration(
              color: message.isDeleted
                  ? CupertinoColors.secondarySystemBackground
                      .resolveFrom(context)
                  : isOwn
                      ? CupertinoColors.activeBlue.resolveFrom(context)
                      : CupertinoColors.tertiarySystemBackground
                          .resolveFrom(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final attachment in message.attachments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
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
                if (message.isDeleted)
                  Text(
                    'Message deleted',
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: context.tertiaryText,
                    ),
                  )
                else if (message.body.isNotEmpty)
                  Text(
                    message.body,
                    style: TextStyle(
                      fontSize: 15,
                      color: isOwn ? CupertinoColors.white : context.primaryText,
                    ),
                  ),
                if (message.editedAt != null && !message.isDeleted)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'edited',
                      style: TextStyle(
                        fontSize: 11,
                        color: isOwn
                            ? CupertinoColors.white.withValues(alpha: 0.7)
                            : context.tertiaryText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (showSeen)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              'Seen',
              style: TextStyle(fontSize: 11, color: context.tertiaryText),
            ),
          ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isBusy,
    required this.onSend,
    required this.onPickImages,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool isBusy;
  final VoidCallback onSend;
  final VoidCallback onPickImages;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: isBusy ? null : onPickImages,
            child: Icon(
              CupertinoIcons.photo,
              size: 24,
              color: context.secondaryText,
            ),
          ),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: 'Message…',
              maxLines: null,
              onChanged: onChanged,
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
                : Icon(
                    CupertinoIcons.arrow_up_circle_fill,
                    size: 28,
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                  ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Register the route**

In `lib/core/config/router.dart` add the import:

```dart
import '../../features/chat/screens/conversation_thread_screen.dart';
```

After the `/messages/new` route added in Task 4, add:

```dart
      GoRoute(
        path: '/conversations/:id',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ConversationThreadScreen(
            conversationId: int.parse(state.pathParameters['id']!),
            title: extra?['title'] as String?,
          );
        },
      ),
```

- [ ] **Step 5: Run tests + analyzer**

Run: `flutter test test/features/chat/conversation_thread_screen_test.dart && flutter analyze`
Expected: PASS (1 test); `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/screens/conversation_thread_screen.dart lib/core/config/router.dart test/features/chat/conversation_thread_screen_test.dart
git commit -m "feat(chat): conversation thread screen with images, receipts, edit/delete

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Comments sections on event / rehearsal / booking detail screens

**Files:**
- Create: `lib/features/chat/widgets/comments_section.dart`
- Modify: `lib/features/events/screens/event_detail_screen.dart` (append section to the `ListView` children, after the Roster block ending `_RosterSection(event: event),` `],` — directly before the final `const SizedBox(height: 32),`)
- Modify: `lib/features/rehearsals/screens/rehearsal_detail_screen.dart` (append to the body's scroll children, as the last section before any trailing bottom padding)
- Modify: `lib/features/bookings/screens/booking_detail_screen.dart` (append after the History `_SectionHeader` block inside the `SliverList` children, ~line 531)
- Test: `test/features/chat/comments_section_test.dart`

**Interfaces:**
- Consumes: `chatRepositoryProvider.topicThread`, `Conversation`/`ChatMessage` models, thread route from Task 6.
- Produces: `class TopicRef { final String kind; final String idOrKey; }` (value-equal, family key), `final topicThreadProvider = FutureProvider.family<ThreadPage, TopicRef>`, widget `CommentsSection({required String kind, required String idOrKey})`. `topicThreadProvider` is an invalidation target in Task 8.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/comments_section_test.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/widgets/comments_section.dart';

import '../../helpers/test_harness.dart';

void main() {
  Dio dioReturning(Map<String, dynamic> body) =>
      Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = StubAdapter((_) async => json(200, body));

  testWidgets('shows recent comments and the view-all row', (tester) async {
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dioReturning({
        'conversation': {
          'id': 5,
          'type': 'topic',
          'title': 'Gig at Blue Room',
          'unread_count': 2,
        },
        'messages': [
          {
            'id': 1,
            'conversation_id': 5,
            'user_id': 2,
            'user_name': 'Eddie',
            'body': 'sound check at 6',
            'created_at': '2026-07-12T14:00:00Z',
          },
        ],
        'participants': [],
        'channel': 'private-conversation.5',
        'has_more': false,
      }))),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: CupertinoPageScaffold(
          child: ListView(
            children: [CommentsSection(kind: 'events', idOrKey: 'abc123')],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('sound check at 6'), findsOneWidget);
    expect(find.textContaining('View all'), findsOneWidget);
    expect(find.textContaining('2 unread'), findsOneWidget);
  });

  test('TopicRef is value-equal (family cache key)', () {
    expect(const TopicRef(kind: 'events', idOrKey: 'a'),
        const TopicRef(kind: 'events', idOrKey: 'a'));
    expect(
        const TopicRef(kind: 'events', idOrKey: 'a').hashCode,
        const TopicRef(kind: 'events', idOrKey: 'a').hashCode);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/comments_section_test.dart`
Expected: FAIL — package resolution error for `comments_section.dart`.

- [ ] **Step 3: Write the widget**

```dart
// lib/features/chat/widgets/comments_section.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/chat_repository.dart';

/// Family key for a topic (comment) thread. kind: 'events'|'rehearsals'|'bookings'.
class TopicRef {
  const TopicRef({required this.kind, required this.idOrKey});
  final String kind;
  final String idOrKey;

  @override
  bool operator ==(Object other) =>
      other is TopicRef && other.kind == kind && other.idOrKey == idOrKey;

  @override
  int get hashCode => Object.hash(kind, idOrKey);
}

/// Resolves (creating if needed) the comment thread for a topic and returns
/// its first page. Invalidated by realtime 'message' signals.
final topicThreadProvider = FutureProvider.family<ThreadPage, TopicRef>(
  (ref, topic) => ref
      .watch(chatRepositoryProvider)
      .topicThread(kind: topic.kind, idOrKey: topic.idOrKey),
);

/// Embeddable "Comments" section for detail screens: header, the 3 most
/// recent comments, and an unread-aware "View all" row that opens the full
/// thread screen.
class CommentsSection extends ConsumerWidget {
  const CommentsSection({super.key, required this.kind, required this.idOrKey});

  final String kind;
  final String idOrKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topic = TopicRef(kind: kind, idOrKey: idOrKey);
    final pageAsync = ref.watch(topicThreadProvider(topic));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Comments',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        pageAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CupertinoActivityIndicator()),
          ),
          // Comments are secondary content on a detail screen — a load
          // failure shows a quiet retry row, not a full-screen error.
          error: (_, __) => CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => ref.invalidate(topicThreadProvider(topic)),
            child: Text(
              'Couldn\'t load comments — tap to retry',
              style: TextStyle(fontSize: 13, color: context.secondaryText),
            ),
          ),
          data: (page) {
            final recent = page.messages.length <= 3
                ? page.messages
                : page.messages.sublist(page.messages.length - 3);
            final unread = page.conversation.unreadCount;
            final total = page.messages.length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (recent.isEmpty)
                  Text(
                    'No comments yet.',
                    style: TextStyle(fontSize: 13, color: context.secondaryText),
                  ),
                for (final message in recent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(fontSize: 14, color: context.primaryText),
                        children: [
                          TextSpan(
                            text: '${message.userName}: ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: message.isDeleted
                                ? 'Message deleted'
                                : (message.body.isEmpty && message.attachments.isNotEmpty
                                    ? '📷 Photo'
                                    : message.body),
                          ),
                        ],
                      ),
                    ),
                  ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => context.push(
                    '/conversations/${page.conversation.id}',
                    extra: {'title': page.conversation.title},
                  ),
                  child: Text(
                    unread > 0
                        ? 'View all ($total) · $unread unread'
                        : (total == 0 ? 'Add a comment' : 'View all ($total)'),
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Embed in the three detail screens**

`lib/features/events/screens/event_detail_screen.dart` — add import `import '../../chat/widgets/comments_section.dart';`. In `_EventDetailView`'s `ListView` children, directly before the final `const SizedBox(height: 32),` (after the Roster block), insert:

```dart
          CommentsSection(kind: 'events', idOrKey: event.key),
```

`lib/features/rehearsals/screens/rehearsal_detail_screen.dart` — add the same import. In `_RehearsalDetailViewState.build`, append to the body's scroll children as the final section (locate the main `ListView`/`Column` children list; anchor with `grep -n "children:" lib/features/rehearsals/screens/rehearsal_detail_screen.dart` and add after the last existing section, before any trailing `SizedBox`):

```dart
          CommentsSection(kind: 'rehearsals', idOrKey: '${_rehearsal.id}'),
```

`lib/features/bookings/screens/booking_detail_screen.dart` — add the same import. Inside the `SliverList` children, after the History section block (the widgets following `const _SectionHeader(label: 'History'),` ~line 531), insert:

```dart
                CommentsSection(kind: 'bookings', idOrKey: '$bookingId'),
```

(Use the screen's existing booking-id variable; in this file the screen receives `bookingId` as a constructor field.)

- [ ] **Step 5: Run tests + analyzer**

Run: `flutter test test/features/chat/comments_section_test.dart && flutter analyze`
Expected: PASS (2 tests); `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/widgets/comments_section.dart lib/features/events/screens/event_detail_screen.dart lib/features/rehearsals/screens/rehearsal_detail_screen.dart lib/features/bookings/screens/booking_detail_screen.dart test/features/chat/comments_section_test.dart
git commit -m "feat(chat): comments sections on event, rehearsal, booking detail

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Realtime — band 'message' case + user-channel provider

**Files:**
- Modify: `lib/shared/providers/band_realtime_provider.dart` (new switch case + `_allRegisteredModels` entry + imports)
- Create: `lib/shared/providers/user_realtime_provider.dart`
- Modify: `lib/shared/widgets/app_scaffold.dart` (keep the new provider alive next to `bandRealtimeProvider`, line 94)
- Test: extend `test/shared/providers/band_realtime_provider_test.dart`; create `test/shared/providers/user_realtime_provider_test.dart`

**Interfaces:**
- Consumes: `chatConversationsProvider`, `topicThreadProvider` (Tasks 3, 7), `authProvider` (`AuthAuthenticated.user.id`), `pusherConnectionProvider`, existing test seams (`bandRealtimeDebounceProvider`, `providerInvalidatorProvider`).
- Produces: `case 'message'` in `invalidationTargetsFor` returning `[chatConversationsProvider, topicThreadProvider]`; `'message'` in `_allRegisteredModels`; `const String userDataChangedEvent = 'user.data-changed'`, `final userChannelBinderProvider = Provider<BandChannelBinder>`, `final userRealtimeProvider = NotifierProvider<UserRealtimeNotifier, int?>` (state = subscribed user id).

- [ ] **Step 1: Write the failing tests**

Append to `test/shared/providers/band_realtime_provider_test.dart` (inside `main()`, after the existing tests; also add the import `import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';` and `import 'package:tts_bandmate/features/chat/widgets/comments_section.dart';` at the top):

```dart
  test('message signal invalidates chat conversation + topic providers', () async {
    final c = makeContainer();
    await activate(c);

    capturedHandler!('band.data-changed',
        {'model': 'message', 'id': 1, 'action': 'created'});
    await Future<void>.delayed(Duration.zero);

    expect(invalidated, containsAll(<ProviderOrFamily>[
      chatConversationsProvider,
      topicThreadProvider,
    ]));
  });
```

```dart
// test/shared/providers/user_realtime_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/pusher_connection.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';
import 'package:tts_bandmate/shared/providers/band_realtime_provider.dart';
import 'package:tts_bandmate/shared/providers/user_realtime_provider.dart';

class FakeAuth extends AuthNotifier {
  FakeAuth(this._state);
  final AuthState _state;

  @override
  Future<AuthState> build() async => _state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> subscribedChannels;
  late PusherJsonHandler? capturedHandler;
  late List<ProviderOrFamily> invalidated;

  ProviderContainer makeContainer(AuthState authState) {
    subscribedChannels = [];
    capturedHandler = null;
    invalidated = [];
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => FakeAuth(authState)),
      bandRealtimeDebounceProvider.overrideWithValue(Duration.zero),
      providerInvalidatorProvider.overrideWithValue((p) => invalidated.add(p)),
      userChannelBinderProvider.overrideWithValue((channel, onEvent) async {
        subscribedChannels.add(channel);
        capturedHandler = onEvent;
        return () async {};
      }),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  AuthState authedAs(int userId) => AuthAuthenticated(
        user: AuthUser(id: userId, name: 'Eddie', email: 'e@x.com'),
        bands: const [],
      );

  Future<void> activate(ProviderContainer c) async {
    c.read(userRealtimeProvider);
    await c.read(authProvider.future);
    await Future<void>.delayed(Duration.zero);
  }

  test('subscribes to the authed user channel', () async {
    final c = makeContainer(authedAs(42));
    await activate(c);
    expect(subscribedChannels, ['private-App.Models.User.42']);
    expect(c.read(userRealtimeProvider), 42);
  });

  test('does not subscribe when unauthenticated', () async {
    final c = makeContainer(const AuthUnauthenticated());
    await activate(c);
    expect(subscribedChannels, isEmpty);
  });

  test('message signal invalidates the conversation list', () async {
    final c = makeContainer(authedAs(42));
    await activate(c);
    capturedHandler!('user.data-changed',
        {'model': 'message', 'id': 9, 'action': 'created'});
    await Future<void>.delayed(Duration.zero);
    expect(invalidated, contains(chatConversationsProvider));
  });
}
```

Note: check `AuthUser`'s constructor (`lib/features/auth/data/models/auth_user.dart`) and `AuthUnauthenticated`'s constructor before running; adjust required params (e.g. `avatarUrl`) to match the real signatures.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/shared/providers/`
Expected: band test FAILS on the new expectation (no `case 'message'` yet → nothing invalidated); user test FAILS to compile (`user_realtime_provider.dart` missing).

- [ ] **Step 3: Modify band_realtime_provider.dart**

Add imports:

```dart
import '../../features/chat/providers/conversations_provider.dart';
import '../../features/chat/widgets/comments_section.dart';
```

Add to the `invalidationTargetsFor` switch (before `default:`):

```dart
    case 'message':
      return [chatConversationsProvider, topicThreadProvider];
```

Add `'message',` to `_allRegisteredModels`.

- [ ] **Step 4: Write user_realtime_provider.dart**

```dart
// lib/shared/providers/user_realtime_provider.dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/pusher_connection.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/chat/providers/conversations_provider.dart';
import 'band_realtime_provider.dart'
    show BandChannelBinder, bandRealtimeDebounceProvider, providerInvalidatorProvider;

/// Wire event name — must match the backend's user-channel broadcast.
const String userDataChangedEvent = 'user.data-changed';

/// Production binder for the per-user private channel. Same shape as the band
/// binder so tests can override it identically.
final userChannelBinderProvider = Provider<BandChannelBinder>((ref) {
  return (channel, onEvent) =>
      ref.read(pusherConnectionProvider).subscribe(channel, onEvent);
});

/// Subscribes to the authed user's private channel and turns thin
/// `user.data-changed` signals (currently only DM 'message' signals) into
/// Riverpod invalidations. State is the subscribed user id.
///
/// Kept alive by AppScaffold, next to bandRealtimeProvider. Deliberately
/// simpler than the band notifier: no resume blanket (the band notifier's
/// resume already refreshes; DM staleness self-heals on thread open), no
/// cache clearers (no chat disk cache in v1).
class UserRealtimeNotifier extends Notifier<int?> {
  Future<void> Function()? _unsubscribe;
  Timer? _flushTimer;
  bool _pending = false;
  int _generation = 0;
  bool _disposed = false;

  @override
  int? build() {
    ref.onDispose(_teardown);
    ref.listen(authProvider, (previous, next) {
      final auth = next.value;
      _resubscribe(auth is AuthAuthenticated ? auth.user.id : null);
    }, fireImmediately: true);
    return null;
  }

  Future<void> _resubscribe(int? userId) async {
    final gen = ++_generation;
    final old = _unsubscribe;
    _unsubscribe = null;
    try {
      await old?.call();
    } catch (e) {
      debugPrint('userRealtime: unsubscribe failed: $e');
    }
    if (_disposed || gen != _generation) return;

    state = null;
    if (userId == null) return;

    final binder = ref.read(userChannelBinderProvider);
    final Future<void> Function()? unsubscribe;
    try {
      unsubscribe = await binder('private-App.Models.User.$userId', _onSignal);
    } catch (e) {
      debugPrint('userRealtime: subscribe for user $userId failed: $e');
      return;
    }
    if (_disposed || gen != _generation) {
      try {
        await unsubscribe?.call();
      } catch (e) {
        debugPrint('userRealtime: stale unsubscribe failed: $e');
      }
      return;
    }

    _unsubscribe = unsubscribe;
    if (_unsubscribe != null) state = userId;
  }

  void _onSignal(String eventName, Map<String, dynamic> data) {
    if (eventName != userDataChangedEvent) return;
    if (data['model'] != 'message') return;
    _pending = true;
    _flushTimer ??= Timer(ref.read(bandRealtimeDebounceProvider), _flush);
  }

  void _flush() {
    _flushTimer = null;
    if (!_pending) return;
    _pending = false;
    ref.read(providerInvalidatorProvider)(chatConversationsProvider);
  }

  void _teardown() {
    _disposed = true;
    _generation++;
    _flushTimer?.cancel();
    final unsubscribe = _unsubscribe;
    _unsubscribe = null;
    try {
      unsubscribe?.call().catchError((Object e) {
        debugPrint('userRealtime: teardown unsubscribe failed: $e');
      });
    } catch (e) {
      debugPrint('userRealtime: teardown unsubscribe failed: $e');
    }
  }
}

final userRealtimeProvider = NotifierProvider<UserRealtimeNotifier, int?>(
  UserRealtimeNotifier.new,
);
```

- [ ] **Step 5: Keep it alive in AppScaffold**

In `lib/shared/widgets/app_scaffold.dart` add import `import '../providers/user_realtime_provider.dart';` and below `ref.watch(bandRealtimeProvider);` (line 94) add:

```dart
    // Keeps the per-user (DM) realtime subscription alive for the whole shell.
    ref.watch(userRealtimeProvider);
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/shared/providers/ && flutter analyze`
Expected: ALL PASS (existing band tests + 1 new band test + 3 user tests); `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/shared/providers/ lib/shared/widgets/app_scaffold.dart test/shared/providers/
git commit -m "feat(realtime): message signals on band + per-user channels refresh chat

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Push — chat_message type, routing, foreground suppression

**Files:**
- Modify: `lib/features/notifications/data/push_payload.dart` (new enum value + `conversationId` field)
- Modify: `lib/features/notifications/data/push_route.dart` (chat route)
- Modify: `lib/features/notifications/services/push_service.dart` (suppress when thread open)
- Modify: `lib/features/notifications/providers/notifications_provider.dart` (wire `currentLocation`)
- Test: extend `test/features/... ` — locate the existing push tests with `ls test/features/notifications/` and add cases to the push_route/push_payload test files there (create `test/features/notifications/chat_push_test.dart` if no suitable file exists).

**Interfaces:**
- Consumes: `routerProvider` (for current location), Task 6's `/conversations/:id` route.
- Produces: `PushType.chatMessage` (wire string `chat_message`), `PushPayload.conversationId`, `routeForPushData` case returning `/conversations/{conversationId}`, `PushService.currentLocation` (nullable `String? Function()` callback).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/notifications/chat_push_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/push_payload.dart';
import 'package:tts_bandmate/features/notifications/data/push_route.dart';

void main() {
  test('chat_message routes to the conversation thread', () {
    expect(
      routeForPushData({'type': 'chat_message', 'conversationId': '5'}),
      '/conversations/5',
    );
  });

  test('chat_message without conversationId routes nowhere', () {
    expect(routeForPushData({'type': 'chat_message'}), isNull);
  });

  test('payload parses chat type + conversationId with stable dedupe id', () {
    final p = PushPayload.fromData(
        {'type': 'chat_message', 'conversationId': '5', 'body': 'yo'});
    expect(p.type, PushType.chatMessage);
    expect(p.conversationId, '5');
    expect(p.notificationId,
        PushPayload.fromData({'type': 'chat_message', 'conversationId': '5'})
            .notificationId);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/notifications/chat_push_test.dart`
Expected: FAIL — `PushType.chatMessage` / `conversationId` undefined.

- [ ] **Step 3: Implement**

`push_payload.dart` — change the enum line to:

```dart
enum PushType { reminder8h, departure, rehearsalCancelled, rehearsalRestored, chatMessage, unknown }
```

Add to `_typeFromString` before `default:`:

```dart
    case 'chat_message':
      return PushType.chatMessage;
```

Add field `final String? conversationId;` to `PushPayload` (constructor param `this.conversationId,`), parse it in `fromData` with `conversationId: str('conversationId'),`, and in the `notificationId` getter change the entity line to:

```dart
    final entity = eventKey.isNotEmpty
        ? eventKey
        : (conversationId ?? rehearsalId ?? '');
```

`push_route.dart` — replace the function body with:

```dart
String? routeForPushData(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  if (type == 'chat_message') {
    final conversationId = int.tryParse(data['conversationId']?.toString() ?? '');
    if (conversationId == null) return null;
    return '/conversations/$conversationId';
  }
  if (type != 'rehearsal_cancelled' && type != 'rehearsal_restored') {
    return null;
  }
  final rehearsalId = int.tryParse(data['rehearsalId']?.toString() ?? '');
  if (rehearsalId == null) return null;
  return '/rehearsals/$rehearsalId';
}
```

`push_service.dart` — add a public field on `PushService` (near `onDeparturePush`):

```dart
  /// Returns the app's current route path, or null when unknown. Set by the
  /// provider layer; used to suppress a chat notification when its thread is
  /// already on screen.
  String? Function()? currentLocation;
```

In `_show`, after the `if (message.notification != null) return;` line and payload construction, add (immediately after `final payload = PushPayload.fromData(message.data);`):

```dart
    if (payload.type == PushType.chatMessage &&
        payload.conversationId != null &&
        currentLocation?.call() == '/conversations/${payload.conversationId}') {
      return; // thread is open — the live channel already shows the message
    }
```

`notifications_provider.dart` — in `PushRegistrar.registerCurrentToken()`, after `push.listenTaps((route) => _ref.read(routerProvider).go(route));` add:

```dart
    push.currentLocation = () => _ref
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
```

- [ ] **Step 4: Run tests + analyzer**

Run: `flutter test test/features/notifications/ && flutter analyze`
Expected: ALL PASS (existing notification tests unaffected — `chat_message` is additive); `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/ test/features/notifications/chat_push_test.dart
git commit -m "feat(push): chat_message type routes to thread, suppressed when open

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Full-suite sweep

**Files:**
- None new; fixes only if the sweep surfaces issues.

**Interfaces:**
- Consumes: everything above.
- Produces: a green branch ready for on-device verification + PR.

- [ ] **Step 1: Full analyzer + test run**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and ALL tests pass (pre-existing suites must stay green — especially `test/shared/providers/band_realtime_provider_test.dart` and the event/rehearsal/booking screen tests, which now compile against the modified detail screens).

- [ ] **Step 2: Fix anything the sweep surfaced, re-run until green**

Run: `flutter analyze && flutter test`
Expected: clean.

- [ ] **Step 3: Commit (only if fixes were needed)**

```bash
git add -A
git commit -m "test(chat): full-suite fixes after comments & chat integration

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Hand off**

Do NOT push or open a PR yet — the backend plan (separate document, TTS repo) must land on staging first, and on-device verification (run-on-device skill) should follow. Report completion.

---

## Self-review notes (already applied)

- **Spec coverage:** models/tables → Tasks 1–2 (client side); conversation list + unread badges → Tasks 3–4; DMs + contacts → Tasks 2, 4; thread with typing/receipts/edit/delete/images → Tasks 5–6; comments on events/rehearsals/bookings → Task 7; realtime rails 1–3 → Tasks 5 (open-thread channel), 8 (band + user thin signals); push → Task 9. Deferred items (mentions, groups, video, web) intentionally absent.
- **Sub gating** is server-side (policy + entitlement); the client renders whatever the API returns — no client-side role checks, matching the spec.
- **Type consistency check:** `ChatImageUpload` produced in Task 2, consumed in Tasks 5–6; `seenByOthersCount` defined Task 5, consumed Task 6; `TopicRef`/`topicThreadProvider` defined Task 7, consumed Task 8; `BandChannelBinder` reused from band_realtime_provider in Task 8 via `show` import; route `/conversations/:id` registered Task 6, consumed Tasks 4 (row tap), 7 (view-all), 9 (push route) — consistent.
- **Known soft spots called out to implementers:** exact insertion anchors in `rehearsal_detail_screen.dart`/`booking_detail_screen.dart` bodies (grep anchors given); `AuthUser`/`AuthUnauthenticated` constructor signatures in Task 8's test (verify before running); if `flutter analyze` flags the unused `userDataChangedEvent`-style constants or import ordering, fix per analyzer output.
