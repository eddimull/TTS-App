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
