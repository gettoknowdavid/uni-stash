import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/features/chats/data/realtime_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MockDio extends Mock implements Dio {}

/// Records frames pushed to the socket.
class FakeWebSocketSink extends Fake implements WebSocketSink {
  final List<String> sent = [];

  @override
  void add(dynamic data) => sent.add(data as String);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
}

/// A WebSocketChannel whose frames the test both records (outgoing) and
/// feeds (incoming) without touching the network.
class FakeWebSocketChannel extends Fake implements WebSocketChannel {
  final controller = StreamController<dynamic>();
  final fakeSink = FakeWebSocketSink();

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  WebSocketSink get sink => fakeSink;
}

void main() {
  late MockDio dio;
  late FakeWebSocketChannel channel;
  late RealtimeClient client;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    dio = MockDio();
    channel = FakeWebSocketChannel();
    when(
      () => dio.post<dynamic>(any(), data: any(named: 'data')),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        data: '{"auth":"app-key:signature"}',
        requestOptions: RequestOptions(path: '/api/v1/realtime/auth'),
      ),
    );
    client = RealtimeClient(
      dio: dio,
      logger: Logger(),
      pusherKey: 'app-key',
      pusherCluster: 'eu',
      authEndpoint: 'https://api.test/api/v1/realtime/auth',
      connector: (_) => channel,
    );
  });

  tearDown(() async {
    client.disconnect();
    await channel.controller.close();
  });

  test(
    'connects, authenticates and subscribes to private-chat-{id} (7.4)',
    () async {
      final connectionStates = <bool>[];
      client.onConnectionChanged = ({required connected}) =>
          connectionStates.add(connected);

      Map<String, dynamic>? received;
      await client.subscribeToChat(
        'c1',
        onNewMessage: (data) => received = data,
        onReadReceipt: (_) {},
      );

      // Socket opened, but without the Pusher handshake no subscribe frame
      // may have been sent yet.
      expect(client.isConnected, isFalse);
      expect(channel.fakeSink.sent, isEmpty);

      // Pusher handshake.
      channel.controller.add(
        jsonEncode({
          'event': 'pusher:connection_established',
          'data': jsonEncode({'socket_id': '100.1', 'activity_timeout': 30}),
        }),
      );
      await pumpEventQueue();

      expect(client.isConnected, isTrue);
      expect(connectionStates, [true]);

      // The channel auth was requested from the backend...
      verify(
        () => dio.post<dynamic>(
          'https://api.test/api/v1/realtime/auth',
          data: any(named: 'data'),
        ),
      ).called(1);

      // ...and the subscribe frame targets the private chat channel with
      // the returned signature.
      final frames = channel.fakeSink.sent
          .map((f) => jsonDecode(f) as Map<String, dynamic>)
          .toList();
      final subscribe = frames.firstWhere(
        (f) => f['event'] == 'pusher:subscribe',
      );
      final data = subscribe['data'] as Map<String, dynamic>;
      expect(data['channel'], 'private-chat-c1');
      expect(data['auth'], 'app-key:signature');

      // A message.new frame for the channel reaches the callback with the
      // decoded payload.
      channel.controller.add(
        jsonEncode({
          'event': 'message.new',
          'channel': 'private-chat-c1',
          'data': jsonEncode({'type': 'message_new', 'chat_id': 'c1'}),
        }),
      );
      await pumpEventQueue();

      expect(received, {'type': 'message_new', 'chat_id': 'c1'});
    },
  );

  test('frames for unknown channels are ignored', () async {
    await client.subscribeToChat(
      'c1',
      onNewMessage: (_) => fail('must not be called'),
      onReadReceipt: (_) {},
    );
    channel.controller.add(
      jsonEncode({
        'event': 'pusher:connection_established',
        'data': jsonEncode({'socket_id': '100.1', 'activity_timeout': 30}),
      }),
    );
    await pumpEventQueue();

    channel.controller.add(
      jsonEncode({
        'event': 'message.new',
        'channel': 'private-chat-other',
        'data': jsonEncode({'type': 'message_new', 'chat_id': 'other'}),
      }),
    );
    await pumpEventQueue();

    // Reaching this point without the callback firing is the assertion;
    // add a cheap explicit one too.
    expect(client.isConnected, isTrue);
  });
}
