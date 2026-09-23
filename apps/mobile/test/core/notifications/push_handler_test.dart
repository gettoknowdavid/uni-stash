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
}
