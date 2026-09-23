import 'package:flutter_test/flutter_test.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';

void main() {
  test('ChatThread deserializes the backend wire payload (7.1)', () {
    final json = <String, dynamic>{
      'id': '11111111-1111-1111-1111-111111111111',
      'listing_id': '22222222-2222-2222-2222-222222222222',
      'listing_title': 'Mini Fridge',
      'counterpart_id': '33333333-3333-3333-3333-333333333333',
      'counterpart_name': 'Ada',
      'counterpart_photo_url': null,
      'last_message_preview': 'See you at noon',
      'last_message_at': '2026-09-21T10:30:00Z',
      'unread_count': 3,
      'created_at': '2026-09-20T09:00:00Z',
    };

    final thread = ChatThread.fromJson(json);

    expect(thread.id, '11111111-1111-1111-1111-111111111111');
    expect(thread.listingTitle, 'Mini Fridge');
    expect(thread.counterpartName, 'Ada');
    expect(thread.counterpartPhotoUrl, isNull);
    expect(thread.lastMessagePreview, 'See you at noon');
    expect(thread.lastMessageAt, isNotNull);
    expect(thread.unreadCount, 3);
    expect(thread.createdAt.toUtc(), DateTime.utc(2026, 9, 20, 9));

    // Round-trips its own serialization.
    expect(ChatThread.fromJson(thread.toJson()), thread);
  });

  test('ChatMessage deserializes the backend wire payload (7.1)', () {
    final json = <String, dynamic>{
      'id': '44444444-4444-4444-4444-444444444444',
      'chat_id': '11111111-1111-1111-1111-111111111111',
      'sender_id': '33333333-3333-3333-3333-333333333333',
      'body': 'Is this still available?',
      'read_at': '2026-09-21T11:00:00Z',
      'created_at': '2026-09-21T10:59:00Z',
    };

    final message = ChatMessage.fromJson(json);

    expect(message.body, 'Is this still available?');
    expect(message.readAt, isNotNull);
    expect(message.createdAt.toUtc(), DateTime.utc(2026, 9, 21, 10, 59));
    expect(ChatMessage.fromJson(message.toJson()), message);
  });

  test('ChatMessage tolerates a null read_at for unsent receipts', () {
    final message = ChatMessage.fromJson(const {
      'id': '44444444-4444-4444-4444-444444444445',
      'chat_id': '11111111-1111-1111-1111-111111111111',
      'sender_id': '33333333-3333-3333-3333-333333333333',
      'body': 'hello',
      'read_at': null,
      'created_at': '2026-09-21T10:59:00Z',
    });

    expect(message.readAt, isNull);
  });
}
