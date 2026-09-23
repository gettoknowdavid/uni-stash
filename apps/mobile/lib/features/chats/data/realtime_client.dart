import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Pusher Channels client for real-time chat events (guide 7.4).
///
/// This is the ONLY file that knows Pusher's wire protocol. The rest of the
/// app talks to [RealtimeClient] through its plain methods, so swapping
/// Pusher for another provider means changing only this file.
///
/// Transport: the Pusher WebSocket protocol over `web_socket_channel`
/// (already in pubspec.yaml) — no native Pusher SDK needed.
///
/// Flow:
///  1. [connect] opens `wss://ws-{cluster}.pusher.com/app/{key}`.
///  2. Pusher sends `pusher:connection_established` carrying a `socket_id`.
///  3. [subscribeToChat] registers the channel's callbacks, POSTs
///     `{socket_id, channel_name}` to the backend's `/api/v1/realtime/auth`
///     to get a signature, then sends `pusher:subscribe`.
///  4. The backend publishes `message.new` / `message.read` on
///     `private-chat-{id}` (see `apps/api/src/core/realtime/pusher.rs`);
///     frames for registered channels are dispatched to the callbacks.
///
/// Everything degrades to REST: if the socket or the channel auth fails,
/// subscriptions simply don't happen — the DB row stays the source of
/// truth and clients catch up by refetching.
class RealtimeClient {
  RealtimeClient({
    required Dio dio,
    required Logger logger,
    required this.pusherKey,
    required this.pusherCluster,
    required this.authEndpoint,
    WebSocketChannel Function(Uri uri)? connector,
  }) : _dio = dio,
       _logger = logger,
       _connector = connector ?? WebSocketChannel.connect;

  final Dio _dio;
  final Logger _logger;

  /// Opens the WebSocket — injectable for tests; defaults to
  /// [WebSocketChannel.connect].
  final WebSocketChannel Function(Uri uri) _connector;

  /// The public Pusher app key (safe to ship in the client).
  final String pusherKey;

  /// Pusher cluster, e.g. `eu` — also builds the WebSocket host.
  final String pusherCluster;

  /// Full URL of the backend's private-channel auth endpoint,
  /// `POST /api/v1/realtime/auth`.
  final String authEndpoint;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSubscription;
  String? _socketId;
  bool _isConnected = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  /// Registered per-channel callbacks — also the source of truth for
  /// re-subscribing after a reconnect.
  final Map<String, _ChatSubscription> _subscriptions = {};

  /// Notified whenever the socket goes up/down so view models can surface
  /// it (e.g. `ChatViewModel.isConnected`). Set by the owning view model,
  /// cleared on its dispose.
  void Function({required bool connected})? onConnectionChanged;

  /// Whether the Pusher handshake has completed on the current socket.
  bool get isConnected => _isConnected;

  Uri get _wsUri => Uri(
    scheme: 'wss',
    host: 'ws-$pusherCluster.pusher.com',
    path: '/app/$pusherKey',
    queryParameters: const {
      'protocol': '7',
      'client': 'uni-stash-flutter',
      'version': '1.0.0',
      'flash': 'false',
    },
  );

  /// Opens the WebSocket. Idempotent — an existing socket is left alone.
  /// Completes immediately; [onConnectionChanged] reports when the Pusher
  /// handshake actually finishes.
  Future<void> connect() async {
    if (_disposed || _channel != null) return;
    _reconnectTimer?.cancel();

    final channel = _connector(_wsUri);
    _channel = channel;
    _wsSubscription = channel.stream.listen(
      _handleFrame,
      onDone: _handleDisconnect,
      onError: (Object _, StackTrace _) => _handleDisconnect(),
      cancelOnError: true,
    );
  }

  /// Registers [onNewMessage]/[onReadReceipt] for `private-chat-{chatId}`
  /// and authenticates the subscription once the socket is up.
  Future<void> subscribeToChat(
    String chatId, {
    required void Function(Map<String, dynamic> data) onNewMessage,
    required void Function(Map<String, dynamic> data) onReadReceipt,
  }) async {
    if (_disposed) return;
    final channel = 'private-chat-$chatId';
    _subscriptions[channel] = _ChatSubscription(onNewMessage, onReadReceipt);

    await connect();

    // No handshake yet — the subscription is flushed when
    // `pusher:connection_established` arrives (see _resubscribeAll).
    if (_socketId == null) return;
    await _authenticateAndSubscribe(channel);
  }

  /// Stops listening to a chat channel.
  void unsubscribeFromChat(String chatId) {
    final channel = 'private-chat-$chatId';
    if (_subscriptions.remove(channel) == null) return;
    _send({
      'event': 'pusher:unsubscribe',
      'data': {'channel': channel},
    });
  }

  /// Tears everything down (socket, timers, subscriptions) and stops
  /// reconnecting. Terminal — DI disposes this on scope teardown.
  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    unawaited(_wsSubscription?.cancel());
    _wsSubscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
    _socketId = null;
    _subscriptions.clear();
    _setConnected(false);
  }

  // ---------------------------------------------------------------------------
  // Pusher protocol handling
  // ---------------------------------------------------------------------------

  void _handleFrame(dynamic raw) {
    final frame = _decodeJson(raw);
    if (frame == null) return;

    switch (frame['event'] as String?) {
      case 'pusher:connection_established':
        final data = _decodeJson(frame['data']);
        _socketId = data?['socket_id'] as String?;
        _reconnectAttempt = 0;
        _setConnected(true);
        unawaited(_resubscribeAll());

      case 'pusher:error':
        // Non-fatal protocol error (e.g. bad subscription auth) — log and
        // keep the socket; the affected chat degrades to REST.
        _logger.w('Pusher error frame: ${frame['data']}');

      case 'pusher:ping':
        _send({'event': 'pusher:pong', 'data': <String, dynamic>{}});

      case 'message.new':
        _dispatch(frame, (sub, data) => sub.onNewMessage(data));

      case 'message.read':
        _dispatch(frame, (sub, data) => sub.onReadReceipt(data));

      // `pusher_internal:*` subscription acknowledgements, pong replies
      // and anything else need no handling.
      default:
        break;
    }
  }

  void _dispatch(
    Map<String, dynamic> frame,
    void Function(_ChatSubscription sub, Map<String, dynamic> data) run,
  ) {
    final channel = frame['channel'];
    if (channel is! String) return;
    final sub = _subscriptions[channel];
    if (sub == null) return;
    final data = _decodeJson(frame['data']);
    if (data == null) return;
    run(sub, data);
  }

  Future<void> _resubscribeAll() async {
    for (final channel in _subscriptions.keys.toList()) {
      await _authenticateAndSubscribe(channel);
    }
  }

  Future<void> _authenticateAndSubscribe(String channel) async {
    final socketId = _socketId;
    if (socketId == null) return;

    final auth = await _authenticateChannel(socketId, channel);
    // Auth failed: degrade to REST (the chat still works, just without
    // live updates), or the socket was replaced mid-auth — either way
    // don't subscribe on a stale socket.
    if (auth == null || _disposed || _socketId != socketId) return;

    _send({
      'event': 'pusher:subscribe',
      'data': {'channel': channel, 'auth': auth},
    });
  }

  /// Signs a private-channel subscription with the backend.
  ///
  /// POSTs `{ socket_id, channel_name }` to `/api/v1/realtime/auth` on the
  /// authenticated Dio (its interceptor attaches the JWT). Returns the
  /// `auth` signature, or null on any failure — callers then skip the
  /// subscription and the chat degrades to REST.
  Future<String?> _authenticateChannel(String socketId, String channel) async {
    try {
      final response = await _dio.post<dynamic>(
        authEndpoint,
        data: {'socket_id': socketId, 'channel_name': channel},
      );
      // The backend answers with the auth JSON; depending on content-type
      // Dio may hand it back already decoded or as a raw string.
      final body = _decodeJson(response.data);
      final auth = body?['auth'];
      return auth is String ? auth : null;
    } on DioException catch (e) {
      _logger.e('[RealtimeClient] channel auth failed', error: e);
      return null;
    } on Object catch (e) {
      _logger.e('[RealtimeClient] channel auth unexpected error', error: e);
      return null;
    }
  }

  void _handleDisconnect() {
    _channel = null;
    _wsSubscription = null;
    _socketId = null;
    _setConnected(false);
    if (_disposed || _subscriptions.isEmpty) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    // Exponential backoff: 1s, 2s, 4s, 8s, …, capped at 30s. Reset to 1s
    // on the next successful handshake.
    final seconds = min(30, 1 << min(_reconnectAttempt, 10));
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (_disposed) return;
      unawaited(connect());
    });
  }

  void _setConnected(bool value) {
    if (_isConnected == value) return;
    _isConnected = value;
    onConnectionChanged?.call(connected: value);
  }

  void _send(Map<String, dynamic> event) {
    _channel?.sink.add(jsonEncode(event));
  }

  /// Pusher frames (and the auth response) may carry JSON as an already
  /// decoded map or as a string — accept both, drop anything malformed.
  Map<String, dynamic>? _decodeJson(Object? raw) {
    try {
      if (raw is Map<String, dynamic>) return raw;
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } on Object catch (_) {
      // Malformed frame — never crash the socket loop.
    }
    return null;
  }
}

typedef _ChatHandler = void Function(Map<String, dynamic> data);

class _ChatSubscription {
  const _ChatSubscription(this.onNewMessage, this.onReadReceipt);

  final _ChatHandler onNewMessage;
  final _ChatHandler onReadReceipt;
}
