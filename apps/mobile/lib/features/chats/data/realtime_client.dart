import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

/// Realtime chat transport built on the official `pusher_channels_flutter`
/// plugin (guide 7.4). The plugin wraps the native Pusher SDKs
/// (pusher-websocket-java / pusher-websocket-swift), which own the socket,
/// automatic reconnection and channel resubscription.
///
/// The app-facing surface is intentionally small:
///
/// * [connect] / [disconnect] — socket lifecycle for the authenticated scope
/// * [subscribeToChat] / [unsubscribeFromChat] — `private-chat-{id}` channels
/// * [isConnected] / [onConnectionChanged] — drives the chat page's
///   connection banner (guide 7.8)
///
/// **Private-channel auth:** when the native SDK subscribes to a
/// `private-*` channel it calls back into [_authorize] (the plugin's
/// `onAuthorizer`), which POSTs `{socket_id, channel_name}` to the backend
/// — on the auth-bearing [Dio], so the JWT interceptor applies — and returns
/// `{'auth': ...}`, the exact shape both native SDKs consume (iOS force-casts
/// `[String: String]`, Android gson-serializes the map). A failed auth
/// returns null, which lets the native SDK fail that subscription gracefully
/// while REST-loaded content stays on screen.
///
/// Reconnection: the native SDKs retry on their own; [_scheduleReconnect]
/// adds a bounded exponential backoff (1s → 30s) on top for the case where
/// they give up, and always resubscribes channels that are still wanted.
///
/// Note: this app targets Android/iOS, where the Dart authorizer above runs.
/// On web the embedded pusher-js would fetch [authEndpoint] itself — without
/// auth headers — so private channels are not supported there.
class RealtimeClient {
  RealtimeClient({
    required Dio dio,
    required Logger logger,
    required this.pusherKey,
    required this.pusherCluster,
    required this.authEndpoint,
  }) : _dio = dio,
       _logger = logger;

  final Dio _dio;
  final Logger _logger;

  /// Pusher Channels app key (`Config.pusherKey`).
  final String pusherKey;

  /// Pusher Channels cluster (`Config.pusherCluster`).
  final String pusherCluster;

  /// Backend private-channel auth endpoint; posted to with the JWT attached.
  final String authEndpoint;

  final PusherChannelsFlutter _pusher = PusherChannelsFlutter.getInstance();

  /// Invoked with `connected: true|false` whenever the socket state changes.
  void Function({required bool connected})? onConnectionChanged;

  final Set<String> _subscriptions = <String>{};

  bool _initialized = false;
  bool _connected = false;
  bool _connecting = false;
  bool _connectRequested = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  /// Whether the socket is currently connected.
  bool get isConnected => _connected;

  /// The private channel name for a conversation.
  String channelNameFor(String chatId) => 'private-chat-$chatId';

  /// Initializes the plugin (once) and opens the socket. Idempotent.
  Future<void> connect() async {
    if (_disposed || pusherKey.isEmpty) return;

    if (!_initialized) {
      try {
        await _initialize();
        _initialized = true;
      } on Object catch (e, s) {
        // No native plugin (e.g. tests/web) or bad options — stay in
        // REST-only mode rather than crashing chat.
        _logger.e('Pusher init failed', error: e, stackTrace: s);
        return;
      }
    }

    _connectRequested = true;
    if (_connected || _connecting) return;

    _connecting = true;
    try {
      await _pusher.connect();
    } on Object catch (e, s) {
      _connecting = false;
      _logger.w('Pusher connect failed, will retry', error: e, stackTrace: s);
      _scheduleReconnect();
    }
  }

  Future<void> _initialize() async {
    await _pusher.init(
      apiKey: pusherKey,
      cluster: pusherCluster,
      authEndpoint: authEndpoint,
      onConnectionStateChange: _onConnectionStateChange,
      onSubscriptionError: (message, error) {
        _logger.w('Pusher subscription error: $message ($error)');
      },
      onError: (message, code, error) {
        _logger.w('Pusher error ($code): $message ($error)');
      },
      onAuthorizer: _authorize,
    );
  }

  /// Subscribes to `private-chat-{chatId}` and routes the two backend events
  /// (see `core/realtime/pusher.rs`) to the given handlers. Safe to call
  /// repeatedly; the socket is connected on demand.
  Future<void> subscribeToChat(
    String chatId, {
    required void Function(Map<String, dynamic> data) onNewMessage,
    required void Function(Map<String, dynamic> data) onReadReceipt,
  }) async {
    if (_disposed || chatId.isEmpty) return;

    await connect();
    // Init failed or no key configured — degrade to REST-only.
    if (!_initialized || _disposed) return;

    final channelName = channelNameFor(chatId);
    if (!_subscriptions.add(channelName)) return;

    try {
      await _pusher.subscribe(
        channelName: channelName,
        onEvent: (dynamic raw) {
          if (raw is! PusherEvent || _disposed) return;
          final data = _decodeData(raw.data);
          if (data == null) return;
          switch (raw.eventName) {
            case 'message.new':
              onNewMessage(data);
            case 'message.read':
              onReadReceipt(data);
            default:
              break;
          }
        },
      );
      if (!_connected) _scheduleReconnect();
    } on Object catch (e, s) {
      _subscriptions.remove(channelName);
      _logger.w(
        'Pusher subscribe failed for $channelName',
        error: e,
        stackTrace: s,
      );
      _scheduleReconnect();
    }
  }

  /// Unsubscribes from a chat's channel. Fire-and-forget: the native SDK
  /// performs the round-trip.
  void unsubscribeFromChat(String chatId) {
    if (chatId.isEmpty) return;
    final channelName = channelNameFor(chatId);
    if (!_subscriptions.remove(channelName)) return;
    if (_disposed) return;
    unawaited(_unsubscribe(channelName));
  }

  Future<void> _unsubscribe(String channelName) async {
    try {
      await _pusher.unsubscribe(channelName: channelName);
    } on Object catch (e, s) {
      _logger.w(
        'Pusher unsubscribe failed for $channelName',
        error: e,
        stackTrace: s,
      );
    }
  }

  /// Disconnects the socket and releases the client (authenticated-scope
  /// disposal, i.e. logout). Idempotent; no further reconnects after this.
  Future<void> disconnect() async {
    _disposed = true;
    _connectRequested = false;
    _connecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscriptions.clear();
    if (_connected) {
      _connected = false;
      onConnectionChanged?.call(connected: false);
    }
    try {
      await _pusher.disconnect();
    } on Object catch (e, s) {
      _logger.w('Pusher disconnect failed', error: e, stackTrace: s);
    }
  }

  // -------------------------------------------------------------------------
  // Auth
  // -------------------------------------------------------------------------

  /// The plugin's `onAuthorizer`: called by the native SDK right before it
  /// subscribes to a private channel.
  Future<dynamic> _authorize(
    String channelName,
    String socketId,
    dynamic options,
  ) async {
    try {
      // Intentionally untyped: the endpoint returns JSON without an
      // application/json content type, so Dio hands the body over as a String
      // and a `Map<String, dynamic>` cast would throw.
      final response = await _dio.post<Object?>(
        authEndpoint,
        data: {'socket_id': socketId, 'channel_name': channelName},
      );
      final auth = _authFrom(response.data);
      if (auth == null) {
        _logger.w('Pusher auth response missing "auth" for $channelName');
        return null;
      }
      return <String, String>{'auth': auth};
    } on Object catch (e, s) {
      _logger.w(
        'Pusher auth failed for $channelName',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }

  /// Accepts both decoded maps and raw JSON text — the backend's auth
  /// endpoint returns JSON without an application/json content type, so Dio
  /// may hand the body over as a [String].
  String? _authFrom(Object? body) {
    if (body is Map) {
      final auth = body['auth'];
      if (auth is String && auth.isNotEmpty) return auth;
      return null;
    }
    if (body is String) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final auth = decoded['auth'];
          if (auth is String && auth.isNotEmpty) return auth;
        }
      } on Object catch (_) {
        return null;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Connection state & reconnect
  // -------------------------------------------------------------------------

  void _onConnectionStateChange(String current, String previous) {
    if (_disposed) return;

    if (current == 'CONNECTED') {
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _connecting = false;
      if (_connected) return;
      _connected = true;
      onConnectionChanged?.call(connected: true);
      return;
    }

    _connecting = false;
    if (current == 'CONNECTING') {
      // The native SDK is already retrying on its own — stand down.
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      return;
    }
    if (_connected) {
      _connected = false;
      onConnectionChanged?.call(connected: false);
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !_connectRequested || _connected || _connecting) return;
    if (_subscriptions.isEmpty) return;
    if (_reconnectTimer?.isActive ?? false) return;

    final gapSeconds = min(30, 1 << min(_reconnectAttempts, 5));
    _reconnectAttempts += 1;
    _reconnectTimer = Timer(Duration(seconds: gapSeconds), () {
      unawaited(_reconnect());
    });
  }

  Future<void> _reconnect() async {
    if (_disposed || _connected || _connecting || _subscriptions.isEmpty) {
      return;
    }
    _connecting = true;
    try {
      await _pusher.connect();
    } on Object catch (e, s) {
      _connecting = false;
      _logger.w('Pusher reconnect failed', error: e, stackTrace: s);
      _scheduleReconnect();
    }
  }

  // -------------------------------------------------------------------------
  // Event payloads
  // -------------------------------------------------------------------------

  /// Event data arrives as a JSON [String] from the iOS SDK and as a [Map]
  /// from Android — normalize to a string-keyed map.
  Map<String, dynamic>? _decodeData(dynamic raw) {
    dynamic decoded = raw;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } on Object catch (_) {
        return null;
      }
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }
}
