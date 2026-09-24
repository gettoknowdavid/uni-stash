import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pusher_beams_platform_interface/pusher_beams_platform_interface.dart';
import 'package:uni_stash_mobile/core/notifications/push_notifications.dart';

class MockStorage extends Mock implements FlutterSecureStorage {}

/// In-memory [PusherBeamsPlatform] recording every SDK call. Assigned once
/// per test file: `PusherBeams` captures its platform reference in a static
/// final on first use, so the same instance must serve every test — state
/// is reset between tests instead.
class RecordingBeams extends PusherBeamsPlatform {
  final List<String> calls = <String>[];
  String? startedWith;
  List<String>? interests;
  bool stopped = false;
  int fgRegistrations = 0;

  /// When set, the next [start] throws — simulating a device without the
  /// Firebase config. (Swapping `PusherBeamsPlatform.instance` per test
  /// doesn't work: the app-facing SDK caches the platform in a static
  /// final on first use, so failure modes live on the one instance.)
  bool failNextStart = false;

  void reset() {
    calls.clear();
    startedWith = null;
    interests = null;
    stopped = false;
    fgRegistrations = 0;
    failNextStart = false;
  }

  @override
  Future<void> start(String instanceId) async {
    if (failNextStart) {
      failNextStart = false;
      throw PlatformException(
        code: 'BEAMS_START_FAILED',
        message: 'google-services.json missing',
      );
    }
    calls.add('start');
    startedWith = instanceId;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    stopped = true;
  }

  @override
  Future<void> setDeviceInterests(List<String> interests) async {
    calls.add('setDeviceInterests');
    this.interests = interests;
  }

  @override
  Future<void> clearDeviceInterests() async {
    calls.add('clearDeviceInterests');
    interests = <String>[];
  }

  @override
  Future<void> onMessageReceivedInTheForeground(dynamic callbackId) async {
    // The app-facing wrapper passes a callback id (dynamic dispatch), which
    // the real plugin forwards over its method channel.
    calls.add('onMessageReceivedInTheForeground');
    fgRegistrations += 1;
  }

  @override
  Future<Map<String, dynamic>?> getInitialMessage() async => null;
}

/// Valid UUID: `PusherBeams.start()` runs the id through `UuidValue`.
const String _instanceId = '00000000-0000-4000-8000-00000000beef';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingBeams beams;
  late MockStorage storage;
  late PushNotifications push;

  setUpAll(() {
    beams = RecordingBeams();
    PusherBeamsPlatform.instance = beams;
  });

  setUp(() {
    beams.reset();
    storage = MockStorage();
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => null);
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    push = PushNotifications(
      instanceId: _instanceId,
      storage: storage,
      logger: Logger(level: Level.off),
    );
  });

  void optOutOnDisk() {
    when(() => storage.read(key: PushNotifications.enabledKey))
        .thenAnswer((_) async => 'false');
  }

  test(
    'bootstrap defaults to enabled, starts the SDK, wires handlers (7.9)',
    () async {
      await push.bootstrap();

      expect(push.enabled.value, isTrue);
      expect(push.isStarted, isTrue);
      expect(beams.startedWith, _instanceId);
      expect(beams.fgRegistrations, 1);
      expect(beams.calls, contains('start'));
    },
  );

  test('bootstrap respects a stored opt-out', () async {
    optOutOnDisk();
    await push.bootstrap();

    expect(push.enabled.value, isFalse);
    expect(push.isStarted, isFalse);
    expect(beams.startedWith, isNull);
    expect(beams.calls, isNot(contains('start')));
  });

  test('setEnabled(false) stops the SDK and persists the preference', () async {
    await push.bootstrap();
    expect(push.isStarted, isTrue);

    await push.setEnabled(false);

    expect(push.enabled.value, isFalse);
    expect(beams.stopped, isTrue);
    expect(push.isStarted, isFalse);
    verify(
      () => storage.write(
        key: PushNotifications.enabledKey,
        value: 'false',
      ),
    ).called(1);
  });

  test(
    'setEnabled(true) after opt-out restarts and restores the interest',
    () async {
      optOutOnDisk();
      await push.bootstrap();
      await push.onUserSignedIn('u1');
      // Opted out — sign-in must not register the device.
      expect(beams.interests, isNull);

      await push.setEnabled(true);

    expect(push.enabled.value, isTrue);
    expect(push.isStarted, isTrue);
    expect(beams.interests, <String>['user-u1']);
    // The foreground handler was never registered while opted out, so the
    // restart registers it exactly once.
    expect(beams.fgRegistrations, 1);

      verify(
        () => storage.write(
          key: PushNotifications.enabledKey,
          value: 'true',
        ),
      ).called(1);
    },
  );

  test('sign-in and sign-out manage the user interest (7.9)', () async {
    await push.bootstrap();

    await push.onUserSignedIn('u42');
    expect(push.userId, 'u42');
    expect(beams.interests, <String>['user-u42']);
    expect(
      PushNotifications.userInterest('u42'),
      'user-u42',
    );

    await push.onUserSignedOut();
    expect(push.userId, isNull);
    expect(beams.calls, contains('clearDeviceInterests'));
    expect(beams.interests, isEmpty);
  });

  test(
    'sign-in while opted out records the user but registers nothing',
    () async {
      optOutOnDisk();
      await push.bootstrap();
      beams.reset();

      await push.onUserSignedIn('u7');

      expect(push.userId, 'u7');
      expect(beams.calls, isEmpty);
    },
  );

  test('bootstrap is idempotent', () async {
    await push.bootstrap();
    await push.bootstrap();

    expect(beams.calls.where((call) => call == 'start'), hasLength(1));
    expect(beams.fgRegistrations, 1);
  });  test('a failing SDK start degrades gracefully instead of throwing',
      () async {
    beams.failNextStart = true;

    await push.bootstrap();

    expect(push.enabled.value, isTrue);
    expect(push.isStarted, isFalse);
  });
}
