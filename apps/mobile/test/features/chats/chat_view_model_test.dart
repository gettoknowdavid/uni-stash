import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/chats/data/chats_repository.dart';
import 'package:uni_stash_mobile/features/chats/data/realtime_client.dart';
import 'package:uni_stash_mobile/features/chats/models/chat_dto.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';
import 'package:uni_stash_mobile/features/chats/view_models/chat_view_model.dart';

class MockChatsRepository extends Mock implements ChatsRepository {}

/// Test double that records the realtime callbacks the view model
/// registers, so tests can simulate incoming Pusher events.
class FakeRealtimeClient extends Fake implements RealtimeClient {
  String? subscribedChatId;
  String? unsubscribedChatId;
  void Function(Map<String, dynamic> data)? onNewMessage;
  void Function(Map<String, dynamic> data)? onReadReceipt;

  @override
  void Function({required bool connected})? onConnectionChanged;

  @override
  bool get isConnected => false;

  @override
  Future<void> subscribeToChat(
    String chatId, {
    required void Function(Map<String, dynamic> data) onNewMessage,
    required void Function(Map<String, dynamic> data) onReadReceipt,
  }) async {
    subscribedChatId = chatId;
    this.onNewMessage = onNewMessage;
    this.onReadReceipt = onReadReceipt;
  }

  @override
  void unsubscribeFromChat(String chatId) {
    unsubscribedChatId = chatId;
  }
}

ChatMessage buildMessage({
  String id = 'm1',
  String senderId = 'u2',
  String body = 'hi',
  DateTime? readAt,
}) {
  return ChatMessage(
    id: id,
    senderId: senderId,
    chatId: 'c1',
    body: body,
    createdAt: DateTime(2026),
    readAt: readAt,
  );
}

void main() {
  late MockChatsRepository repo;
  late FakeRealtimeClient realtime;
  late ChatViewModel model;

  /// Stubbed `listMessages` responses, consumed in order; the last one
  /// repeats once exhausted.
  final pages = <Result<ListMessageResponse>>[];
  var listCalls = 0;

  void stubListMessages() {
    when(
      () => repo.listMessages(
        any(),
        cursor: any(named: 'cursor'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async {
      final index = listCalls < pages.length ? listCalls : pages.length - 1;
      listCalls++;
      return pages[index];
    });
  }

  Result<ListMessageResponse> page(
    List<ChatMessage> messages, {
    String? nextCursor,
  }) => Result.success(
    ListMessageResponse(messages: messages, nextCursor: nextCursor),
  );

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    repo = MockChatsRepository();
    realtime = FakeRealtimeClient();
    model = ChatViewModel(
      repo,
      realtime,
      chatId: 'c1',
      currentUserId: 'me',
    );
    pages.clear();
    listCalls = 0;
    // Opening a chat marks the counterpart's messages read server-side
    // (ties the thread badge to the chat page).
    when(
      () => repo.markRead('c1'),
    ).thenAnswer((_) async => const Result.success(null));
  });

  tearDown(() => model.dispose());

  Future<void> loadInitial(
    List<ChatMessage> newestFirst, {
    String? nextCursor,
  }) async {
    pages.add(page(newestFirst, nextCursor: nextCursor));
    stubListMessages();
    model.loadMessages();
    await pumpEventQueue();
    expect(model.error.value, isNull);
  }

  test('loadMessages reverses order and subscribes realtime', () async {
    await loadInitial([buildMessage(id: 'm2'), buildMessage()]);

    expect(model.messages.value.map((m) => m.id).toList(), ['m1', 'm2']);
    expect(model.isLoading.value, isFalse);
    expect(realtime.subscribedChatId, 'c1');
    expect(realtime.onNewMessage, isNotNull);
    expect(realtime.onReadReceipt, isNotNull);
    // Opening the chat clears the unread count server-side too.
    verify(() => repo.markRead('c1')).called(1);
  });

  test('loadMessages failure surfaces the error', () async {
    when(
      () => repo.listMessages(
        any(),
        cursor: any(named: 'cursor'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => const Result.failure('network down'));

    model.loadMessages();
    await pumpEventQueue();

    expect(model.error.value, 'network down');
    expect(model.messages.value, isEmpty);
  });

  test('sendMessage appends without realtime-refetch duplicates', () async {
    await loadInitial(
      [buildMessage(id: 'm2'), buildMessage()],
    );

    when(() => repo.sendMessage('c1', 'yo')).thenAnswer(
      (_) async => Result.success(
        buildMessage(id: 'm3', senderId: 'me', body: 'yo'),
      ),
    );

    await model.sendMessage('yo');
    expect(
      model.messages.value.map((m) => m.id).toList(),
      ['m1', 'm2', 'm3'],
    );
    expect(model.isSending.value, isFalse);

    // The backend event only carries chat_id — the view model refetches
    // the newest page, which already contains m3.
    pages.add(
      page([
        buildMessage(id: 'm3', senderId: 'me', body: 'yo'),
        buildMessage(id: 'm2'),
        buildMessage(),
      ]),
    );
    realtime.onNewMessage!(const {'type': 'message_new', 'chat_id': 'c1'});
    await pumpEventQueue();

    expect(model.messages.value.map((m) => m.id).toList(), ['m1', 'm2', 'm3']);
  });

  test(
    'message.new appends messages that arrived while the page was open',
    () async {
      await loadInitial([buildMessage(id: 'm2'), buildMessage()]);

      pages.add(
        page([
          buildMessage(id: 'm3'),
          buildMessage(id: 'm2'),
          buildMessage(),
        ]),
      );
      realtime.onNewMessage!(const {'type': 'message_new', 'chat_id': 'c1'});
      await pumpEventQueue();

      expect(model.messages.value.map((m) => m.id).toList(), [
        'm1',
        'm2',
        'm3',
      ]);
    },
  );

  test('sendMessage failure surfaces the error', () async {
    await loadInitial([buildMessage()]);
    when(
      () => repo.sendMessage('c1', 'yo'),
    ).thenAnswer((_) async => const Result.failure('blocked'));

    await model.sendMessage('yo');

    expect(model.error.value, 'blocked');
    expect(model.messages.value.length, 1);
    expect(model.isSending.value, isFalse);
  });

  test('loadMore prepends older pages without duplicates', () async {
    await loadInitial([
      buildMessage(id: 'm4'),
      buildMessage(id: 'm3'),
    ], nextCursor: 'cur1');
    expect(model.messages.value.map((m) => m.id).toList(), ['m3', 'm4']);

    // Older window overlaps m3 — it must be deduplicated.
    pages.add(
      page([
        buildMessage(id: 'm3'),
        buildMessage(id: 'm2'),
        buildMessage(),
      ]),
    );

    await model.loadMore();
    await pumpEventQueue();

    expect(
      model.messages.value.map((m) => m.id).toList(),
      ['m1', 'm2', 'm3', 'm4'],
    );
    // The stub's second call must have carried the cursor.
    verify(
      () => repo.listMessages(
        'c1',
        cursor: 'cur1',
        limit: any(named: 'limit'),
      ),
    ).called(1);
  });

  test('read receipt marks my messages up to last_read_message_id', () async {
    // Newest-first on the wire: m3 (mine), m2, m1 (mine), m0 — so the
    // displayed order after the reverse is m0, m1, m2, m3.
    await loadInitial([
      buildMessage(id: 'm3', senderId: 'me'),
      buildMessage(id: 'm2'),
      buildMessage(senderId: 'me'),
      buildMessage(id: 'm0'),
    ]);

    realtime.onReadReceipt!(const {
      'type': 'message_read',
      'chat_id': 'c1',
      'last_read_message_id': 'm1',
    });
    await pumpEventQueue();

    final byId = {for (final m in model.messages.value) m.id: m};
    expect(byId['m1']!.readAt, isNotNull);
    expect(byId['m3']!.readAt, isNull, reason: 'newer than the receipt');
    expect(
      byId['m0']!.readAt,
      isNull,
      reason: "counterpart's messages untouched",
    );
  });

  test(
    'read receipt with an unknown id marks all of my messages read',
    () async {
      await loadInitial([
        buildMessage(id: 'm3', senderId: 'me'),
        buildMessage(id: 'm2'),
        buildMessage(senderId: 'me'),
      ]);

      realtime.onReadReceipt!(const {
        'type': 'message_read',
        'chat_id': 'c1',
        'last_read_message_id': 'evicted-id',
      });
      await pumpEventQueue();

      final mine = model.messages.value.where((m) => m.senderId == 'me');
      expect(mine.every((m) => m.readAt != null), isTrue);
    },
  );

  test('dispose unsubscribes from realtime', () async {
    await loadInitial([buildMessage()]);

    model.dispose();

    expect(realtime.unsubscribedChatId, 'c1');
    expect(realtime.onConnectionChanged, isNull);
  });
}
