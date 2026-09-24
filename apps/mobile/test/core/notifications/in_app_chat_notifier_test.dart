import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_stash_mobile/core/notifications/in_app_chat_notifier.dart';

void main() {
  late InAppChatNotifier notifier;

  setUp(() => notifier = InAppChatNotifier());

  test('dedups repeat notifications for the same chat within the window', () {
    final t0 = DateTime(2026, 1, 1, 12);

    expect(notifier.shouldShow('c1', t0), isTrue);
    notifier.markShown('c1', t0);

    // Same chat a second later — deduped (realtime + push double fire).
    expect(
      notifier.shouldShow('c1', t0.add(const Duration(seconds: 2))),
      isFalse,
    );
    // Different chat is unaffected.
    expect(
      notifier.shouldShow('c2', t0.add(const Duration(seconds: 2))),
      isTrue,
    );
    // After the window it shows again.
    expect(
      notifier.shouldShow(
        'c1',
        t0.add(InAppChatNotifier.dedupWindow + const Duration(seconds: 1)),
      ),
      isTrue,
    );
  });

  test('without a host context nothing is shown', () {
    expect(
      notifier.show(
        chatId: 'c1',
        title: 'New message from Ada',
        onOpen: () {},
      ),
      isFalse,
    );
    expect(notifier.isAttached, isFalse);
  });

  test('detach clears the host', () {
    // A context that is never mounted — attach/detach bookkeeping only.
    final ctx = _UnmountedContext();
    notifier.attach(ctx);
    expect(notifier.isAttached, isFalse);
    notifier.detach();
    expect(notifier.isAttached, isFalse);
  });
}

/// Minimal BuildContext stand-in — `mounted` false, which is all
/// [InAppChatNotifier] reads before attaching the real one.
class _UnmountedContext implements BuildContext {
  @override
  bool get mounted => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.toString());
}
