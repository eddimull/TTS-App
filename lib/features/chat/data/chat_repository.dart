import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/chat_contact.dart';
import 'models/chat_message.dart' show ChatMessage, MessageReaction;
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
  /// For bookings, [bandId] is required.
  Future<ThreadPage> topicThread({
    required String kind,
    required String idOrKey,
    int? bandId,
  }) async {
    final path = switch (kind) {
      'events' => ApiEndpoints.mobileEventConversation(idOrKey),
      'rehearsals' =>
        ApiEndpoints.mobileRehearsalConversation(int.parse(idOrKey)),
      'bookings' => ApiEndpoints.mobileBookingConversation(
        bandId ?? (throw ArgumentError('bandId required for bookings thread')),
        int.parse(idOrKey),
      ),
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
          MultipartFile.fromBytes(
            img.bytes,
            filename: img.filename,
            // Composer re-encodes picks to JPEG via image_picker (the server
            // rejects heic/heif), so the upload mime is always image/jpeg.
            contentType: DioMediaType('image', 'jpeg'),
          ),
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

  /// Full-resolution bytes of an attachment. The fullscreen viewer downloads
  /// once and shares the bytes between display, save, and share.
  Future<Uint8List> attachmentBytes(int messageId, int attachmentId) async {
    final res = await _dio.get<List<int>>(
      ApiEndpoints.mobileMessageAttachment(messageId, attachmentId),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }
}

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(apiClientProvider).dio),
);
