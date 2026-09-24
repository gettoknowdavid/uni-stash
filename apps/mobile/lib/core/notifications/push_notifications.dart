import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:pusher_beams/pusher_beams.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/notifications/push_handler.dart';

/// Pusher Beams push-notification manager (guide 7.9 / 7.10).
///
/// Beams addresses devices through *interests*: the backend publishes to
/// `user-{uuid}` (see `apps/api/src/core/notifications/beams.rs`) and each
/// device subscribes to the same interest. This class owns the device half
/// of that contract:
///
/// * [bootstrap] — loads the persisted preference, registers the foreground
///   handler, starts the SDK, and deep-links when a notification tap
///   cold-started the app.
/// * [onUserSignedIn] / [onUserSignedOut] — subscribe/clear this device's
///   `user-{id}` interest around authentication (guide 7.9).
/// * [setEnabled] — the Settings toggle (guide: "tie push enable/disable to
///   settings"): off calls the SDK's `stop()` so the device is deregistered
///   and receives nothing; on restarts the SDK and restores the interest.
///
/// Every SDK call is best-effort: failures are logged and never bubble into
/// login, navigation, or the toggle itself — a missing
/// `google-services.json`, an unset `BEAMS_INSTANCE_ID`, etc. degrade push
/// silently instead of crashing the app.
class PushNotifications {
  PushNotifications({
    required this.instanceId,
    required FlutterSecureStorage storage,
    required Logger logger,
  }) : _storage = storage,
       _logger = logger;

  /// Secure-storage key holding the user's push preference.
  static const String enabledKey = 'push_notifications_enabled';

  /// Beams interest every device of [userId] subscribes to. Must match the
  /// backend's `BeamsPushSender::user_interest`.
  static String userInterest(String userId) => 'user-$userId';

  /// Beams instance id (`Config.beamsInstanceId`). Empty disables push.
  final String instanceId;

  final FlutterSecureStorage _storage;
  final Logger _logger;

  /// Whether push notifications are on — persisted; defaults to on.
  /// The Settings page reads this signal; writes go through [setEnabled].
  final Signal<bool> enabled = signal(true);

  bool _bootstrapped = false;
  bool _started = false;
  bool _fgHandlerRegistered = false;
  String? _userId;

  /// Whether the Beams SDK successfully started on this device.
  bool get isStarted => _started;

  /// The user this device is currently registered for, if signed in.
  String? get userId => _userId;

  /// Loads the preference, wires the SDK, and starts push when enabled.
  /// Called once from `main()` before `runApp`.
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    final stored = await _storage.read(key: enabledKey);
    enabled.value = stored != 'false';

    await _registerForegroundHandler();
    if (enabled.value) await _start();

    // A tap that cold-started the app only surfaces via getInitialMessage()
    // once the app is up; the callback is registered pre-runApp here and
    // runs right after the first frame (after AuthViewModel.bootstrap has
    // settled, so router redirects apply correctly).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleInitialMessage());
    });
  }

  /// Persist and apply the Settings toggle.
  // ignore: avoid_positional_boolean_parameters
  Future<void> setEnabled(bool value) async {
    if (enabled.value != value) enabled.value = value;
    await _storage.write(key: enabledKey, value: '$value');

    if (value) {
      // stop() clears the SDK's Dart-side callbacks — re-register first.
      await _registerForegroundHandler();
      await _start();
      final userId = _userId;
      if (userId != null) await _applyInterest(userId);
      return;
    }

    if (await _safe('stop', PusherBeams.instance.stop)) {
      _started = false;
      _fgHandlerRegistered = false;
    }
  }

  /// Registers this device for [userId]'s pushes (guide 7.9). Called after
  /// login and after session bootstrap; fire-and-forget from the auth hooks.
  Future<void> onUserSignedIn(String userId) async {
    _userId = userId;
    if (!enabled.value) return;
    await _start();
    await _applyInterest(userId);
  }

  /// This device must stop receiving [userId]'s pushes on sign-out.
  Future<void> onUserSignedOut() async {
    _userId = null;
    await _safe('clear interests', PusherBeams.instance.clearDeviceInterests);
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  Future<void> _start() async {
    if (_started || instanceId.isEmpty) return;
    final ok = await _safe(
      'start',
      () => PusherBeams.instance.start(instanceId),
    );
    _started = ok;
    if (!ok) {
      _logger.w(
        'Pusher Beams failed to start — check BEAMS_INSTANCE_ID and, on '
        'Android, that app/google-services.json is present.',
      );
    }
  }

  Future<void> _applyInterest(String userId) =>
      _safe('set device interests', () async {
        await PusherBeams.instance.setDeviceInterests([userInterest(userId)]);
      });

  Future<void> _registerForegroundHandler() async {
    if (_fgHandlerRegistered) return;
    _fgHandlerRegistered = await _safe(
      'register foreground handler',
      () =>
          PusherBeams.instance.onMessageReceivedInTheForeground(_onForeground),
    );
  }

  /// Foreground messages. Android delivers `{title, body, data}` with a
  /// flat (string-valued) `data` map; iOS delivers the APNs payload's
  /// `data` object directly. [normalizePushData] + `parseChatPush` handle
  /// both, including Beams' `info` nesting.
  void _onForeground(Map<Object?, Object?> message) {
    final nested = message['data'];
    final data = normalizePushData(
      nested is Map ? nested : Map<Object?, Object?>.from(message),
    );
    if (data.isEmpty) return;
    handleForegroundPush(data);
  }

  /// Deep-link when the app was launched by tapping a notification.
  /// The SDK keeps this in memory for the current launch only, so it can
  /// never re-fire on a later, unrelated cold start.
  Future<void> _handleInitialMessage() async {
    try {
      final Object? message = await PusherBeams.instance.getInitialMessage();
      if (message is! Map) return;
      final nested = message['data'];
      final data = normalizePushData(
        nested is Map ? nested : Map<Object?, Object?>.from(message),
      );
      if (data.isEmpty) return;
      handleForegroundPush(data);
    } on Object catch (e, s) {
      _logger.w(
        'Push notifications: initial message failed',
        error: e,
        stackTrace: s,
      );
    }
  }

  /// Runs [run], logging instead of throwing — push must never break the
  /// caller. Returns whether the call succeeded.
  Future<bool> _safe(String what, Future<void> Function() run) async {
    try {
      await run();
      return true;
    } on Object catch (e, s) {
      _logger.w(
        'Push notifications: $what failed',
        error: e,
        stackTrace: s,
      );
      return false;
    }
  }
}
