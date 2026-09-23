import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/chats/data/chats_repository.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';
import 'package:uni_stash_mobile/features/chats/view_models/chat_threads_view_model.dart';

class MockChatsRepository extends Mock implements ChatsRepository {}

ChatThread buildThread({
  String id = 'c1',
  int unreadCount = 0,
  String preview = 'Hi',
}) {
  return ChatThread(
    id: id,
    listingId: 'l1',
    listingTitle: 'Mini Fridge',
    counterpartId: 'u2',
    counterpartName: 'Ada',
    unreadCount: unreadCount,
    createdAt: DateTime(2026),
    lastMessagePreview: preview,
  );
}

void main() {
  late MockChatsRepository repo;
  late ChatThreadsViewModel model;

  setUp(() {
    repo = MockChatsRepository();
    model = ChatThreadsViewModel(repo);
  });

  tearDown(() => model.dispose());

  test('fetch loads threads and exposes the aggregate unread count', () async {
    when(() => repo.listThreads()).thenAnswer(
      (_) async => Result.success([
        buildThread(),
        buildThread(id: 'c2', unreadCount: 2),
        buildThread(id: 'c3', unreadCount: 3),
      ]),
    );

    model.fetch();
    await pumpEventQueue();

    expect(model.threads.value.length, 3);
    expect(model.unreadCount.value, 5);
    expect(model.isLoading.value, isFalse);
    expect(model.error.value, isNull);
  });

  test('fetch failure surfaces the error and keeps the list empty', () async {
    when(
      () => repo.listThreads(),
    ).thenAnswer((_) async => const Result.failure('boom'));

    model.fetch();
    await pumpEventQueue();

    expect(model.error.value, 'boom');
    expect(model.threads.value, isEmpty);
    expect(model.isLoading.value, isFalse);
  });

  test(
    'onNewMessage bumps unread, updates preview and moves thread to top',
    () async {
      when(
        () => repo.listThreads(),
      ).thenAnswer(
        (_) async => Result.success([buildThread(), buildThread(id: 'c2')]),
      );
      model.fetch();
      await pumpEventQueue();

      model.onNewMessage('c1', 'See you there');
      await pumpEventQueue();

      final first = model.threads.value.first;
      expect(first.id, 'c1');
      expect(first.lastMessagePreview, 'See you there');
      expect(first.unreadCount, 1);
      expect(first.lastMessageAt, isNotNull);
      expect(model.unreadCount.value, 1);

      // Unknown chat id is a no-op.
      model.onNewMessage('nope', 'ignored');
      expect(model.threads.value.length, 2);
    },
  );

  test('markThreadRead clears only that thread', () async {
    when(() => repo.listThreads()).thenAnswer(
      (_) async => Result.success([
        buildThread(unreadCount: 4),
        buildThread(id: 'c2', unreadCount: 7),
      ]),
    );
    model.fetch();
    await pumpEventQueue();

    model.markThreadRead('c1');
    await pumpEventQueue();

    expect(model.threads.value.first.unreadCount, 0);
    expect(model.unreadCount.value, 7);
  });
}
