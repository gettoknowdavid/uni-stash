import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/features/chats/data/realtime_client.dart';

class MockDio extends Mock implements Dio {}

const MethodChannel _channel = MethodChannel('pusher_channels_flutter');
const StandardMethodCodec _codec = StandardMethodCodec();

final List<MethodCall> _outbound = <MethodCall>[];

/// Simulates a message arriving *from* the platform (native → Dart), which
/// is how the plugin delivers connection states, events and auth requests.
Future<ByteData?> _inject(String method, Map<String, dynamic> args) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _channel.name,
        _codec.encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDio dio;

  setUp(() {
    dio = MockDio();
    _outbound.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          _outbound.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  RealtimeClient buildClient({
    String key = 'test-key',
    Duration healthCheckInterval = const Duration(seconds: 6),
    Duration resubscribeGrace = const Duration(milliseconds: 1200),
  }) => RealtimeClient(
    dio: dio,
    logger: Logger(level: Level.off),
    pusherKey: key,
    pusherCluster: 'mt1',
    authEndpoint: 'https://api.test/api/v1/realtime/auth',
    healthCheckInterval: healthCheckInterval,
    resubscribeGrace: resubscribeGrace,
  );

  List<String> methods() =>
      _outbound.map((call) => call.method).toList(growable: false);

  MethodCall callNamed(String method) =>
      _outbound.firstWhere((call) => call.method == method);

  void stubAuthOk() {
    when(
      () => dio.post<Object?>(
        any(),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response<Object?>(
        requestOptions: RequestOptions(path: '/api/v1/realtime/auth'),
        data: <String, dynamic>{'auth': 'test-key:signature'},
      ),
    );
  }

  test('subscribeToChat inits the SDK with the app key and subscribes '
      'private-chat-{id} (7.4)', () async {
    final client = buildClient();
    await client.subscribeToChat(
      'c1',
      onNewMessage: (_) {},
      onReadReceipt: (_) {},
    );

    expect(methods(), containsAllInOrder(<String>['init', 'connect']));
    expect(methods(), contains('subscribe'));

    final init = callNamed('init').arguments as Map;
    expect(init['apiKey'], 'test-key');
    expect(init['cluster'], 'mt1');
    expect(init['authorizer'], isTrue);
    expect(init['authEndpoint'], 'https://api.test/api/v1/realtime/auth');

    final subscribe = callNamed('subscribe').arguments as Map;
    expect(subscribe['channelName'], 'private-chat-c1');

    await client.disconnect();
  });

  test('subscribing twice for the same chat subscribes only once', () async {
    final client = buildClient();
    Future<void> subscribe() => client.subscribeToChat(
      'c1',
      onNewMessage: (_) {},
      onReadReceipt: (_) {},
    );

    await subscribe();
    await subscribe();

    expect(
      _outbound.where((call) => call.method == 'subscribe'),
      hasLength(1),
    );

    await client.disconnect();
  });

  test(
    'private-channel auth posts socket id and channel, returns auth',
    () async {
      stubAuthOk();
      final client = buildClient();
      await client.subscribeToChat(
        'c1',
        onNewMessage: (_) {},
        onReadReceipt: (_) {},
      );

      final reply = await _inject('onAuthorizer', <String, dynamic>{
        'channelName': 'private-chat-c1',
        'socketId': '123.456',
      });

      final decoded = reply == null ? null : _codec.decodeEnvelope(reply);
      expect(decoded, <String, dynamic>{'auth': 'test-key:signature'});

      final captured = verify(
        () => dio.post<Object?>(
          'https://api.test/api/v1/realtime/auth',
          data: captureAny(named: 'data'),
        ),
      ).captured.single;
      expect(captured, <String, dynamic>{
        'socket_id': '123.456',
        'channel_name': 'private-chat-c1',
      });

      await client.disconnect();
    },
  );

  test(
    'failed private-channel auth returns null instead of throwing',
    () async {
      when(
        () => dio.post<Object?>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenThrow(Exception('boom'));

      final client = buildClient();
      await client.subscribeToChat(
        'c1',
        onNewMessage: (_) {},
        onReadReceipt: (_) {},
      );

      final reply = await _inject('onAuthorizer', <String, dynamic>{
        'channelName': 'private-chat-c1',
        'socketId': '123.456',
      });

      expect(reply, isNotNull);
      expect(_codec.decodeEnvelope(reply!), isNull);

      await client.disconnect();
    },
  );

  test('message events reach the subscription handlers; JSON and map data '
      'both decode (7.4/7.6)', () async {
    final client = buildClient();
    final received = <Map<String, dynamic>>[];
    final receipts = <Map<String, dynamic>>[];

    await client.subscribeToChat(
      'c1',
      onNewMessage: received.add,
      onReadReceipt: receipts.add,
    );

    // iOS hands event data over as a JSON string.
    await _inject('onEvent', <String, dynamic>{
      'channelName': 'private-chat-c1',
      'eventName': 'message.new',
      'data': jsonEncode(<String, dynamic>{'id': 'm9', 'body': 'hi'}),
    });
    // Android hands it over as a map.
    await _inject('onEvent', <String, dynamic>{
      'channelName': 'private-chat-c1',
      'eventName': 'message.read',
      'data': <String, dynamic>{'last_read_message_id': 'm9'},
    });
    // An unrelated event name is ignored.
    await _inject('onEvent', <String, dynamic>{
      'channelName': 'private-chat-c1',
      'eventName': 'pusher:ping',
      'data': <String, dynamic>{},
    });

    expect(received, hasLength(1));
    expect(received.single['id'], 'm9');
    expect(receipts, hasLength(1));
    expect(receipts.single['last_read_message_id'], 'm9');

    await client.disconnect();
  });

  test('events for channels we never subscribed are not delivered', () async {
    final client = buildClient();
    final received = <Map<String, dynamic>>[];

    await client.subscribeToChat(
      'c1',
      onNewMessage: received.add,
      onReadReceipt: (_) {},
    );

    await _inject('onEvent', <String, dynamic>{
      'channelName': 'private-chat-c99',
      'eventName': 'message.new',
      'data': jsonEncode(<String, dynamic>{'id': 'm1'}),
    });

    expect(received, isEmpty);

    await client.disconnect();
  });

  test(
    'connection state changes drive isConnected and the banner callback',
    () async {
      final client = buildClient();
      final banner = <bool>[];
      client.onConnectionChanged = ({required connected}) {
        banner.add(connected);
      };

      await client.subscribeToChat(
        'c1',
        onNewMessage: (_) {},
        onReadReceipt: (_) {},
      );
      expect(client.isConnected, isFalse);

      await _inject('onConnectionStateChange', <String, dynamic>{
        'currentState': 'connected',
        'previousState': 'connecting',
      });
      expect(client.isConnected, isTrue);
      expect(banner, <bool>[true]);

      await _inject('onConnectionStateChange', <String, dynamic>{
        'currentState': 'disconnected',
        'previousState': 'connected',
      });
      expect(client.isConnected, isFalse);
      expect(banner, <bool>[true, false]);

      // Cancels the scheduled reconnect so no timer outlives the test.
      await client.disconnect();
    },
  );

  test('an empty pusher key keeps the client inert (REST-only mode)', () async {
    final client = buildClient(key: '');
    await client.subscribeToChat(
      'c1',
      onNewMessage: (_) {},
      onReadReceipt: (_) {},
    );

    expect(_outbound, isEmpty);
    expect(client.isConnected, isFalse);
  });

  test(
    'subscribers fan out and cancel independently (re-enter safe)',
    () async {
      final client = buildClient();
      final first = <Map<String, dynamic>>[];
      final second = <Map<String, dynamic>>[];

      final subA = await client.subscribeToChat(
        'c1',
        onNewMessage: first.add,
        onReadReceipt: (_) {},
      );
      final subB = await client.subscribeToChat(
        'c1',
        onNewMessage: second.add,
        onReadReceipt: (_) {},
      );

      // One native subscribe serves both subscribers.
      expect(
        _outbound.where((call) => call.method == 'subscribe'),
        hasLength(1),
      );

      await _inject('onEvent', <String, dynamic>{
        'channelName': 'private-chat-c1',
        'eventName': 'message.new',
        'data': jsonEncode(<String, dynamic>{'id': 'm1'}),
      });
      expect(first, hasLength(1));
      expect(second, hasLength(1));

      // A late dispose (previous page visit) cancels ONLY its own handlers —
      // the new page keeps receiving events.
      subA.cancel();
      await _inject('onEvent', <String, dynamic>{
        'channelName': 'private-chat-c1',
        'eventName': 'message.new',
        'data': jsonEncode(<String, dynamic>{'id': 'm2'}),
      });
      expect(first, hasLength(1), reason: 'cancelled subscriber is detached');
      expect(
        second,
        hasLength(2),
        reason: 'surviving subscriber still gets it',
      );
      expect(
        _outbound.where((call) => call.method == 'unsubscribe'),
        isEmpty,
        reason: 'channel stays up while a subscriber remains',
      );

      // Last subscriber out turns the lights off.
      subB.cancel();
      await pumpEventQueue();
      expect(
        _outbound.where((call) => call.method == 'unsubscribe'),
        hasLength(1),
      );

      await client.disconnect();
    },
  );

  test('subscribeToUserChannel subscribes private-user-{id}', () async {
    final client = buildClient();
    final received = <Map<String, dynamic>>[];

    await client.subscribeToUserChannel(
      'u42',
      onNewMessage: received.add,
    );

    final subscribe = callNamed('subscribe').arguments as Map;
    expect(subscribe['channelName'], 'private-user-u42');

    await _inject('onEvent', <String, dynamic>{
      'channelName': 'private-user-u42',
      'eventName': 'message.new',
      'data': jsonEncode(<String, dynamic>{
        'type': 'message_new',
        'chat_id': 'c9',
        'sender_id': 'u7',
      }),
    });
    expect(received.single['chat_id'], 'c9');

    await client.disconnect();
  });

  test(
    'an unconfirmed subscription is forced again after the health window',
    () async {
      final client = buildClient(
        healthCheckInterval: const Duration(milliseconds: 10),
      );
      await client.subscribeToChat(
        'c1',
        onNewMessage: (_) {},
        onReadReceipt: (_) {},
      );
      // No pusher:subscription_succeeded arrives — the watchdog must force
      // an unsubscribe→subscribe round-trip instead of silently rotting.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        _outbound.where((call) => call.method == 'unsubscribe'),
        isNotEmpty,
        reason: 'stuck channel is unsubscribed first',
      );
      expect(
        _outbound.where((call) => call.method == 'subscribe'),
        hasLength(greaterThan(1)),
        reason: 'then re-subscribed',
      );

      await client.disconnect();
    },
  );

  test('a confirmed subscription is left alone by the health window', () async {
    final client = buildClient(
      healthCheckInterval: const Duration(milliseconds: 10),
    );
    await client.subscribeToChat(
      'c1',
      onNewMessage: (_) {},
      onReadReceipt: (_) {},
    );

    await _inject('onEvent', <String, dynamic>{
      'channelName': 'private-chat-c1',
      'eventName': 'pusher:subscription_succeeded',
      'data': '{}',
    });
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(
      _outbound.where((call) => call.method == 'unsubscribe'),
      isEmpty,
      reason: 'healthy channels are not churned',
    );

    await client.disconnect();
  });

  test('reconnect re-confirms channels that never confirmed', () async {
    final client = buildClient(
      resubscribeGrace: const Duration(milliseconds: 10),
    );
    await client.subscribeToChat(
      'c1',
      onNewMessage: (_) {},
      onReadReceipt: (_) {},
    );

    await _inject('onConnectionStateChange', <String, dynamic>{
      'currentState': 'connected',
      'previousState': 'connecting',
    });
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(
      _outbound.where((call) => call.method == 'unsubscribe'),
      isNotEmpty,
      reason: 'unconfirmed channels are forced after reconnect',
    );

    await client.disconnect();
  });
}
