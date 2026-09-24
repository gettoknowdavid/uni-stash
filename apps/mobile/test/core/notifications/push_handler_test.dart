import 'package:flutter_test/flutter_test.dart';
import 'package:uni_stash_mobile/core/notifications/push_handler.dart';

void main() {
  test('parseChatPush extracts a full chat payload (7.10)', () {
    final target = parseChatPush(const {
      'chat_id': 'c1',
      'sender_name': 'Ada',
      'listing_title': 'Mini Fridge',
    });

    expect(target, isNotNull);
    expect(target!.chatId, 'c1');
    expect(target.counterpartName, 'Ada');
    expect(target.listingTitle, 'Mini Fridge');
    expect(target.extra, {
      'chatId': 'c1',
      'counterpartName': 'Ada',
      'listingTitle': 'Mini Fridge',
    });
  });

  test('parseChatPush ignores payloads without a usable chat_id (7.10)', () {
    expect(parseChatPush(const {'listing_id': 'l1'}), isNull);
    expect(parseChatPush(const {'chat_id': ''}), isNull);
    expect(parseChatPush(const {'chat_id': 42}), isNull);
  });

  test('parseChatPush falls back to neutral labels (7.10)', () {
    final target = parseChatPush(const {'chat_id': 'c9'});

    expect(target, isNotNull);
    expect(target!.counterpartName, 'Unknown');
    expect(target.listingTitle, '');
  });

  test('normalizePushData stringifies keys and recurses into nested maps', () {
    final normalized = normalizePushData(const {
      1: 'one',
      'info': {'chat_id': 'c5', 2: 'two'},
      'count': 3,
    });

    expect(normalized['1'], 'one');
    expect(normalized['count'], 3);
    expect(normalized['info'], isA<Map<String, dynamic>>());
    expect((normalized['info'] as Map<String, dynamic>)['chat_id'], 'c5');
    expect((normalized['info'] as Map<String, dynamic>)['2'], 'two');
  });

  test('parseChatPush unwraps Beams’ nested info object', () {
    // iOS getInitialMessage() / iOS foreground: `info` delivered as a map.
    final target = parseChatPush(const {
      'info': {
        'chat_id': 'c7',
        'sender_name': 'Bo',
        'listing_title': 'Desk',
      },
    });

    expect(target, isNotNull);
    expect(target!.chatId, 'c7');
    expect(target.counterpartName, 'Bo');
    expect(target.listingTitle, 'Desk');
  });

  test('parseChatPush unwraps an info value delivered as a JSON string', () {
    // Android FCM stringifies nested data values.
    final target = parseChatPush(const {
      'info': '{"chat_id":"c8","sender_name":"Cy"}',
    });

    expect(target, isNotNull);
    expect(target!.chatId, 'c8');
    expect(target.counterpartName, 'Cy');
  });

  test('parseChatPush does not recurse forever on malformed info', () {
    expect(parseChatPush(const {'info': 'not-json'}), isNull);
    expect(
      parseChatPush(const {
        'info': {'listing_id': 'l2'},
      }),
      isNull,
    );
    expect(parseChatPush(const {'info': 7}), isNull);
  });

  test('a payload with a top-level chat_id wins over info', () {
    final target = parseChatPush(const {
      'chat_id': 'c1',
      'info': {'chat_id': 'c2'},
    });

    expect(target!.chatId, 'c1');
  });
}
