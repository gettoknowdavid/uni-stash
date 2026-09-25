import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/_result.dart';
import 'package:uni_stash_mobile/features/notifications/data/notifications_api.dart';
import 'package:uni_stash_mobile/features/notifications/models/notifications_dto.dart';

/// Device registration + in-app notifications inbox.
abstract interface class INotificationsRepository {
  /// Registers [token] for the current user on [platform]
  /// (`ios` / `android` / `web`). Swallows every error — push
  /// registration is best-effort.
  Future<void> registerDevice(String token, String platform);

  /// The caller's inbox, newest first. Returns the page plus the live
  /// unread count.
  Future<Result<InboxResponse>> listInbox({String? cursor, int limit});

  /// Marks one notification read.
  Future<Result<void>> markRead(String id);

  /// Marks everything read; returns how many rows changed.
  Future<Result<int>> markAllRead();

  /// Deletes one notification.
  Future<Result<void>> delete(String id);
}

class NotificationsRepository implements INotificationsRepository {
  NotificationsRepository(this._client, this._logger);

  final NotificationsApiClient _client;
  final Logger _logger;

  @override
  Future<void> registerDevice(String token, String platform) async {
    try {
      await _client.registerDevice(
        RegisterDeviceRequest(token: token, platform: platform),
      );
    } on Object catch (e) {
      // Best-effort: don't block login if registration fails.
      _logger.w('[Notifications] Device registration failed', error: e);
    }
  }

  @override
  Future<Result<InboxResponse>> listInbox({String? cursor, int limit = 20}) async {
    try {
      final response = await _client.listInbox(cursor: cursor, limit: limit);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[Notifications] listInbox failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[Notifications] listInbox unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> markRead(String id) async {
    try {
      final response = await _client.markRead(id);
      if (!response.status) return Result.failure(response.message);
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.e('[Notifications] markRead failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[Notifications] markRead unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<int>> markAllRead() async {
    try {
      final response = await _client.markAllRead();
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[Notifications] markAllRead failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[Notifications] markAllRead unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      final response = await _client.deleteNotification(id);
      final code = response.response.statusCode ?? 0;
      if (code >= 200 && code < 300) return const Result.success(null);
      return Result.failure('Failed to delete notification ($code)');
    } on DioException catch (e) {
      _logger.e('[Notifications] delete failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[Notifications] delete unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
