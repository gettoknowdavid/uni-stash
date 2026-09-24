import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/notifications/in_app_chat_notifier.dart';
import 'package:uni_stash_mobile/core/notifications/push_handler.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/chats/data/chats_repository.dart';
import 'package:uni_stash_mobile/features/chats/data/realtime_client.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';
import 'package:uni_stash_mobile/features/chats/open_chat.dart';
import 'package:uni_stash_mobile/features/chats/view_models/chat_realtime_coordinator.dart';
import 'package:uni_stash_mobile/features/chats/view_models/chat_threads_view_model.dart';

class MockChatsRepository extends Mock implements ChatsRepository {}

class FakeSubscription implements RealtimeSubscription {
  FakeSubscription(this.onCancel);

  final void Function() onCancel;
  bool canceled = false;

  @override
  bool get isCanceled => canceled;

  @override
  void cancel() {
    if (canceled) return;
    canceled = true;
    onCancel();
  }
}

/// Records the user-channel subscription so tests can fire events into the
/// coordinator the way the RealtimeClient would.
class FakeRealtimeClient extends Fake implements RealtimeClient {
  String? userChannelUserId;
  void Function(Map<String, dynamic> data)? onUserMessage;
  bool canceled = false;
  bool ensureLiveCalled = false;

  @override
  Future<RealtimeSubscription> subscribeToUserChannel(
    String userId, {
    required void Function(Map<String, dynamic> data) onNewMessage,
  }) async {
    userChannelUserId = userId;
    onUserMessage = onNewMessage;
    return FakeSubscription(() => canceled = true);
  }

  @override
  void ensureLive() => ensureLiveCalled = true;
}

/// Notifier double: skips the (widget-bound) ShadToaster and just records.
class RecordingNotifier extends InAppChatNotifier {
  final List<ShownToast> shown = <ShownToast>[];

  @override
  bool show({
    required String chatId,
    required String title,
    required VoidCallback onOpen,
    String? body,
  }) {
    shown.add(
      ShownToast(chatId: chatId, title: title, body: body, onOpen: onOpen),
    );
    return true;
  }
}

/// One recorded [InAppChatNotifier.show] call.
class ShownToast {
  const ShownToast({
    required this.chatId,
    required this.title,
    required this.body,
    required this.onOpen,
  });

  final String chatId;
  final String title;
  final String? body;
  final VoidCallback onOpen;
}

ChatThread buildThread({
  String id = 'c1',
  String name = 'Ada',
  String? preview = 'Hi',
}) {
  return ChatThread(
    id: id,
    listingId: 'l1',
    listingTitle: 'Mini Fridge',
    counterpartId: 'u9',
    counterpartName: name,
    unreadCount: 1,
    createdAt: DateTime(2026),
    lastMessagePreview: preview,
  );
}

void main() {
  late MockChatsRepository repo;
  late ChatThreadsViewModel threads;
  late FakeRealtimeClient realtime;
  late RecordingNotifier notifier;
  late ChatRealtimeCoordinator coordinator;

  setUp(() {
    repo = MockChatsRepository();
    when(() => repo.listThreads()).thenAnswer(
      (_) async => Result.success([
        buildThread(),
        buildThread(id: 'c2', name: 'Bo'),
      ]),
    );
    threads = ChatThreadsViewModel(repo);
    realtime = FakeRealtimeClient();
    notifier = RecordingNotifier();
    coordinator = ChatRealtimeCoordinator(
      realtimeClient: realtime,
      threads: threads,
      notifier: notifier,
      currentUserId: 'me',
      logger: Logger(level: Level.off),
    );
  });

  tearDown(() {
    coordinator.stop();
    threads.dispose();
    foregroundChatPushHandler = null;
    OpenChat.id = null;
  });

  Future<void> pump() => pumpEventQueue();

  test('start subscribes the user channel and installs the push hook',
      () async {
    coordinator.start();
    await pump();

    expect(coordinator.isStarted, isTrue);
    expect(realtime.userChannelUserId, 'me');
    expect(foregroundChatPushHandler, isNotNull);

    coordinator.stop();
    await pump();
    expect(realtime.canceled, isTrue);
    expect(foregroundChatPushHandler, isNull);
  });

  test('start without a user id stays inert', () {
    final noUser = ChatRealtimeCoordinator(
      realtimeClient: realtime,
      threads: threads,
      notifier: notifier,
      currentUserId: '',
      logger: Logger(level: Level.off),
    );
    noUser.start();
    expect(noUser.isStarted, isFalse);
    expect(realtime.userChannelUserId, isNull);
    expect(foregroundChatPushHandler, isNull);
  });

  test('message.new for a chat that is NOT open refreshes threads and '
      'shows a tappable in-app notification', () async {
    coordinator.start();
    await pump();

    realtime.onUserMessage!(
      const {'type': 'message_new', 'chat_id': 'c2', 'sender_id': 'u9'},
    );
    await pump();

    verify(() => repo.listThreads()).called(greaterThanOrEqualTo(1));
    expect(notifier.shown, hasLength(1));
    final toast = notifier.shown.single;
    expect(toast.chatId, 'c2');
    expect(toast.title, 'New message from Bo');
    expect(toast.body, 'Hi');
    expect(toast.onOpen, isNotNull);
  });

  test('message.new for the OPEN chat stays silent (list updates in place)',
      () async {
    OpenChat.open('c1');
    coordinator.start();
    await pump();

    realtime.onUserMessage!(
      const {'type': 'message_new', 'chat_id': 'c1', 'sender_id': 'u9'},
    );
    await pump();

    expect(notifier.shown, isEmpty);
    // Badge is cleared locally once the refresh lands.
    expect(
      threads.threads.value.firstWhere((t) => t.id == 'c1').unreadCount,
      0,
    );
  });

  test('foreground push shows the same notification — except for the open '
      'chat', () async {
    coordinator.start();
    await pump();

    handleForegroundPush(const {'chat_id': 'c2', 'sender_name': 'Bo'});
    await pump();
    expect(notifier.shown, hasLength(1));
    expect(notifier.shown.single.chatId, 'c2');

    OpenChat.open('c1');
    handleForegroundPush(const {'chat_id': 'c1', 'sender_name': 'Ada'});
    await pump();
    expect(notifier.shown, hasLength(1), reason: 'open chat stays silent');
  });

  test('resume asks the realtime client to re-check liveness', () {
    coordinator.start();
    coordinator.onAppResumed();
    expect(realtime.ensureLiveCalled, isTrue);
  });
}
