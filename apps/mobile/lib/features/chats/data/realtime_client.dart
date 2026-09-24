import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

/// Handle for one subscriber's registration on a channel.
///
/// Cancelling removes *only* that subscriber's handlers; the underlying
/// native subscription is torn down when the last subscriber cancels.
/// This makes the page-scope race harmless: if an old ChatViewModel's
/// late dispose cancels after a new page already subscribed, the new
/// subscriber keeps receiving events.
class RealtimeSubscription {
  RealtimeSubscription._(this._cancel);

  static final RealtimeSubscription _nop = RealtimeSubscription._(() {});

  /// A no-op subscription handed out when the client is inert (no key,
  /// disposed, …) so callers can always cancel without a null check.
  static RealtimeSubscription none() => _nop;

  final void Function() _cancel;
  bool _canceled = false;

  bool get isCanceled => _canceled;

  void cancel() {
    if (_canceled) return;
    _canceled = true;
    _cancel();
  }
}

/// One subscriber's callbacks for a channel.
typedef _Handler = ({
  void Function(Map<String, dynamic> data) onNewMessage,
  void Function(Map<String, dynamic> data)? onReadReceipt,
});

/// Bookkeeping for one desired channel.
class _Channel {
  _Channel(this.name);

  final String name;
  final List<_Handler> handlers = [];

  /// A native subscribe is in flight (or active) and no unsubscribe was
  /// issued since.
  bool nativeActive = false;

  /// The *current* socket confirmed `pusher:subscription_succeeded`.
  /// Cleared whenever the connection drops — a new socket means the old
  /// subscriptions are gone, and we must confirm them again.
  bool subscribed = false;

  /// Attempts since the last confirmation — drives backoff.
  int attempts = 0;

  Timer? healthTimer;
  Timer? retryTimer;
}

/// Realtime chat transport built on the official `pusher_channels_flutter`
/// plugin (guide 7.4). The plugin wraps the native Pusher SDKs
/// (pusher-websocket-java / pusher-websocket-swift), which own the socket,
/// automatic reconnection and channel resubscription.
///
/// The app-facing surface:
///
/// * [connect] / [disconnect] — socket lifecycle for the authenticated scope
/// * [subscribeToChat] / [subscribeToUserChannel] — `private-chat-{id}` and
///   `private-user-{id}` channels; both return a [RealtimeSubscription]
///   whose `cancel()` removes exactly that subscriber (fan-out registry)
/// * [isConnected] / [onConnectionChanged] — drives the chat page's
///   connection banner (guide 7.8)
///
/// **Why the registry + health checks exist:** the native SDK can lose a
/// subscribe message when the socket is mid-connect/reconnect (observed as
/// `Cannot send a message while in CONNECTING state`), and a first-caller-
/// wins subscription set silently starves a second subscriber (e.g. a page
/// re-entered while the previous visit's dispose is still in flight). Both
/// failures are *silent* — the dashboard shows events published, but the app
/// never sees them. So:
///
/// * handlers fan out from a live map, so any generation of the native
///   subscription delivers to every current subscriber;
/// * every channel must confirm `pusher:subscription_succeeded`
///   (see [_Channel.subscribed]) within a health window, otherwise we force
///   an unsubscribe→subscribe round-trip with exponential backoff;
/// * every reconnect transition re-confirms all wanted channels after a
///   short grace period (the native SDK retries on its own; we only act
///   when its attempt didn't confirm);
/// * lifecycle milestones are logged so the next field failure is
///   diagnosable from logcat instead of guesswork.
///
/// **Private-channel auth:** when the native SDK subscribes to a
/// `private-*` channel it calls back into [_authorize] (the plugin's
/// `onAuthorizer`), which POSTs `{socket_id, channel_name}` to the backend
/// — on the auth-bearing [Dio], so the JWT interceptor applies — and returns
/// `{'auth': ...}`. A failed auth returns null, which lets the native SDK
/// fail that subscription gracefully while REST-loaded content stays on
/// screen.
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
    this.healthCheckInterval = const Duration(seconds: 6),
    this.resubscribeGrace = const Duration(milliseconds: 1200),
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

  /// How long a native subscribe may stay unconfirmed before we force an
  /// unsubscribe→subscribe round-trip. Test seam.
  final Duration healthCheckInterval;

  /// Grace period after a reconnect before checking that the native SDK's
  /// own resubscribe actually confirmed. Test seam.
  final Duration resubscribeGrace;

  final PusherChannelsFlutter _pusher = PusherChannelsFlutter.getInstance();

  /// Invoked with `connected: true|false` whenever the socket state changes.
  void Function({required bool connected})? onConnectionChanged;

  /// Desired channels → live subscriber list (fan-out registry).
  final Map<String, _Channel> _channels = <String, _Channel>{};

  bool _initialized = false;
  bool _connected = false;
  bool _connecting = false;
  bool _connectRequested = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _resubscribeTimer;

  /// Whether the socket is currently connected.
  bool get isConnected => _connected;

  /// The private channel name for a conversation.
  String channelNameFor(String chatId) => 'private-chat-$chatId';

  /// The private channel carrying "someone messaged me" events for a user.
  /// Every participant device subscribes once per session (see the chat
  /// realtime coordinator), which is what makes in-app notifications and
  /// live thread-list updates possible for chats the user isn't viewing.
  String userChannelNameFor(String userId) => 'private-user-$userId';

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
    _logger.i('Realtime: connecting (pusher cluster $pusherCluster)');
    try {
      await _pusher.connect();
    } on Object catch (e, s) {
      _connecting = false;
      _logger.w('Pusher connect failed, will retry', error: e, stackTrace: s);
      _scheduleReconnect();
    }
  }

  /// Re-checks liveness when the app returns to the foreground: reconnects
  /// if the socket dropped while dozed, and re-verifies subscriptions that
  /// never confirmed (the OS often kills the socket silently).
  void ensureLive() {
    if (_disposed || pusherKey.isEmpty) return;
    unawaited(connect());
    if (_connected) _scheduleResubscribeCheck();
  }

  Future<void> _initialize() async {
    await _pusher.init(
      apiKey: pusherKey,
      cluster: pusherCluster,
      authEndpoint: authEndpoint,
      onConnectionStateChange: _onConnectionStateChange,
      onSubscriptionSucceeded: _onSubscriptionSucceeded,
      onSubscriptionError: (message, error) {
        _onSubscriptionError('$message ($error)');
      },
      onError: (message, code, error) {
        _logger.w('Pusher error ($code): $message ($error)');
      },
      onAuthorizer: _authorize,
    );
  }

  // -------------------------------------------------------------------------
  // Subscriptions
  // -------------------------------------------------------------------------

  /// Subscribes to `private-chat-{chatId}` and routes the two backend events
  /// (see `core/realtime/pusher.rs`) to the given handlers. Safe to call
  /// repeatedly and concurrently: every caller gets its own
  /// [RealtimeSubscription]; the native subscribe happens once and only
  /// disappears when the last subscriber cancels.
  Future<RealtimeSubscription> subscribeToChat(
    String chatId, {
    required void Function(Map<String, dynamic> data) onNewMessage,
    required void Function(Map<String, dynamic> data) onReadReceipt,
  }) => _subscribe(
    channelNameFor(chatId),
    onNewMessage: onNewMessage,
    onReadReceipt: onReadReceipt,
  );

  /// Subscribes to `private-user-{userId}`, which carries `message.new`
  /// events for messages *addressed to this user* (any chat). Used for
  /// in-app notifications and thread-list updates while the user is not
  /// on that chat's detail page.
  Future<RealtimeSubscription> subscribeToUserChannel(
    String userId, {
    required void Function(Map<String, dynamic> data) onNewMessage,
  }) => _subscribe(
    userChannelNameFor(userId),
    onNewMessage: onNewMessage,
  );

  Future<RealtimeSubscription> _subscribe(
    String channelName, {
    required void Function(Map<String, dynamic> data) onNewMessage,
    void Function(Map<String, dynamic> data)? onReadReceipt,
  }) async {
    if (_disposed || channelName.isEmpty) {
      return RealtimeSubscription.none();
    }

    await connect();
    // Init failed or no key configured — degrade to REST-only.
    if (!_initialized || _disposed) return RealtimeSubscription.none();

    final channel = _channels.putIfAbsent(
      channelName,
      () => _Channel(channelName),
    );
    final handler = (onNewMessage: onNewMessage, onReadReceipt: onReadReceipt);
    channel.handlers.add(handler);

    final subscription = RealtimeSubscription._(() {
      channel.handlers.remove(handler);
      if (channel.handlers.isEmpty) unawaited(_deactivate(channel));
    });

    // First subscriber (or a previous native subscribe that failed) is the
    // one that talks to the platform.
    if (!channel.nativeActive) {
      channel.nativeActive = true;
      try {
        await _pusher.subscribe(
          channelName: channelName,
          onEvent: (dynamic raw) => _dispatch(channelName, raw),
        );
        _logger.i('Realtime: subscribe issued for $channelName');
        if (_disposed) return subscription;
        if (channel.handlers.isEmpty) {
          // Cancelled while the native call was in flight.
          channel.nativeActive = false;
          unawaited(_unsubscribe(channelName));
          return subscription;
        }
        _armHealthCheck(channel);
      } on Object catch (e, s) {
        channel.nativeActive = false;
        _logger.w(
          'Realtime: subscribe failed for $channelName',
          error: e,
          stackTrace: s,
        );
        _scheduleRetry(channel);
        _scheduleReconnect();
      }
    }
    return subscription;
  }

  /// Tears down a channel whose last subscriber cancelled.
  Future<void> _deactivate(_Channel channel) async {
    channel.healthTimer?.cancel();
    channel.healthTimer = null;
    channel.retryTimer?.cancel();
    channel.retryTimer = null;
    channel.subscribed = false;
    channel.attempts = 0;
    _channels.remove(channel.name);
    if (_disposed || !channel.nativeActive) return;
    channel.nativeActive = false;
    await _unsubscribe(channel.name);
  }

  /// Fans an incoming plugin event out to every current subscriber.
  ///
  /// Reads the live registry at dispatch time, so the closure works no
  /// matter which subscribe generation registered it with the plugin.
  void _dispatch(String channelName, dynamic raw) {
    if (_disposed || raw is! PusherEvent) return;
    final channel = _channels[channelName];
    if (channel == null || channel.handlers.isEmpty) return;

    final data = _decodeData(raw.data);
    if (data == null) return;
    _logger.d('Realtime: event ${raw.eventName} on $channelName');

    switch (raw.eventName) {
      case 'message.new':
        for (final handler in List<_Handler>.of(channel.handlers)) {
          handler.onNewMessage(data);
        }
      case 'message.read':
        for (final handler in List<_Handler>.of(channel.handlers)) {
          handler.onReadReceipt?.call(data);
        }
      default:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Subscription health
  // -------------------------------------------------------------------------

  void _onSubscriptionSucceeded(String channelName, Object? data) {
    _logger.i('Realtime: subscribed to $channelName');
    final channel = _channels[channelName];
    if (channel == null) return;
    channel.subscribed = true;
    channel.attempts = 0;
    channel.healthTimer?.cancel();
    channel.healthTimer = null;
    channel.retryTimer?.cancel();
    channel.retryTimer = null;
  }

  void _onSubscriptionError(String message) {
    _logger.w('Pusher subscription error: $message');
    // The plugin doesn't tell us *which* channel failed — nudge every
    // wanted channel that hasn't confirmed yet. The next auth attempt
    // runs through Dio, so a 401 triggers the token refresh automatically.
    // Retries back off through [_scheduleRetry]/[_forceResubscribe].
    for (final channel in _channels.values.toList()) {
      if (!channel.subscribed) _scheduleRetry(channel);
    }
  }

  /// Starts the "did the subscription ever confirm?" watchdog. The window
  /// widens with consecutive failures so a permanently rejected channel
  /// (e.g. auth 400) backs off instead of churning the socket.
  void _armHealthCheck(_Channel channel) {
    channel.healthTimer?.cancel();
    if (_disposed || channel.subscribed) return;
    var gap = healthCheckInterval;
    if (channel.attempts > 1) {
      final backoff = Duration(
        seconds: min(30, 1 << min(channel.attempts - 1, 5)),
      );
      if (backoff > gap) gap = backoff;
    }
    channel.healthTimer = Timer(gap, () {
      if (_disposed || channel.subscribed) return;
      if (!_channels.containsKey(channel.name)) return;
      _logger.w(
        'Realtime: no subscription confirmation for ${channel.name} — '
        'forcing resubscribe',
      );
      unawaited(_forceResubscribe(channel));
    });
  }

  /// Forces an unsubscribe→subscribe round-trip so a lost subscribe message
  /// (or a dead native channel) can't leave us silently unsubscribed.
  Future<void> _forceResubscribe(_Channel channel) async {
    if (_disposed || channel.handlers.isEmpty) return;
    channel.attempts += 1;
    channel.healthTimer?.cancel();
    channel.healthTimer = null;
    try {
      // Removes the (possibly stuck) native channel and the plugin's
      // Dart-side entry; a failed unsubscribe is fine — the subscribe
      // below re-registers anyway.
      await _pusher.unsubscribe(channelName: channel.name);
    } on Object catch (_) {
      // Channel may not exist natively — expected during recovery.
    }
    if (_disposed || channel.handlers.isEmpty) return;
    try {
      channel.nativeActive = true;
      await _pusher.subscribe(
        channelName: channel.name,
        onEvent: (dynamic raw) => _dispatch(channel.name, raw),
      );
      _logger.i('Realtime: resubscribe issued for ${channel.name}');
      _armHealthCheck(channel);
    } on Object catch (e, s) {
      channel.nativeActive = false;
      _logger.w(
        'Realtime: resubscribe failed for ${channel.name}',
        error: e,
        stackTrace: s,
      );
      _scheduleRetry(channel);
    }
  }

  /// Schedules another [_forceResubscribe] with exponential backoff while
  /// the channel is still wanted. [after] overrides the backoff (seconds).
  void _scheduleRetry(_Channel channel, {int? after}) {
    if (_disposed) return;
    if (after != null) {
      channel.retryTimer?.cancel();
      channel.retryTimer = Timer(Duration(seconds: after), () {
        if (!_disposed && channel.handlers.isNotEmpty) {
          unawaited(_forceResubscribe(channel));
        }
      });
      return;
    }
    if (channel.handlers.isEmpty) return;
    channel.retryTimer?.cancel();
    final gap = min(30, 1 << min(channel.attempts, 5));
    _logger.i(
      'Realtime: retrying ${channel.name} in ${gap}s '
      '(attempt ${channel.attempts})',
    );
    channel.retryTimer = Timer(Duration(seconds: gap), () {
      if (!_disposed && channel.handlers.isNotEmpty) {
        unawaited(_forceResubscribe(channel));
      }
    });
  }

  /// After a reconnect, give the native SDK's automatic resubscribe a
  /// moment to confirm — then force whatever didn't.
  void _scheduleResubscribeCheck() {
    _resubscribeTimer?.cancel();
    _resubscribeTimer = Timer(resubscribeGrace, () async {
      if (_disposed || !_connected) return;
      for (final channel in _channels.values.toList()) {
        if (channel.subscribed || channel.handlers.isEmpty) continue;
        _logger.w(
          'Realtime: ${channel.name} unconfirmed after reconnect — '
          'forcing resubscribe',
        );
        await _forceResubscribe(channel);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Unsubscribe / lifecycle
  // -------------------------------------------------------------------------

  /// Unsubscribes a channel on the platform. Fire-and-forget: the native
  /// SDK performs the round-trip.
  Future<void> _unsubscribe(String channelName) async {
    try {
      await _pusher.unsubscribe(channelName: channelName);
      _logger.i('Realtime: unsubscribed $channelName');
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
    _resubscribeTimer?.cancel();
    _resubscribeTimer = null;
    for (final channel in _channels.values) {
      channel.healthTimer?.cancel();
      channel.retryTimer?.cancel();
    }
    _channels.clear();
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
      _logger.i('Realtime: authed $channelName');
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
      _logger.i('Realtime: socket connected');
      if (_connected) return;
      _connected = true;
      onConnectionChanged?.call(connected: true);
      // New socket — nothing is subscribed on it yet, even if the native
      // SDK says it will retry. Verify, then force what didn't confirm.
      for (final channel in _channels.values) {
        channel.subscribed = false;
      }
      _scheduleResubscribeCheck();
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
      _logger.w('Realtime: socket disconnected ($previous → $current)');
      onConnectionChanged?.call(connected: false);
    }
    for (final channel in _channels.values) {
      channel.subscribed = false;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !_connectRequested || _connected || _connecting) return;
    if (_channels.isEmpty) return;
    if (_reconnectTimer?.isActive ?? false) return;

    final gapSeconds = min(30, 1 << min(_reconnectAttempts, 5));
    _reconnectAttempts += 1;
    _logger.i(
      'Realtime: reconnect in ${gapSeconds}s '
      '(attempt $_reconnectAttempts)',
    );
    _reconnectTimer = Timer(Duration(seconds: gapSeconds), () {
      unawaited(_reconnect());
    });
  }

  Future<void> _reconnect() async {
    if (_disposed || _connected || _connecting || _channels.isEmpty) {
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
