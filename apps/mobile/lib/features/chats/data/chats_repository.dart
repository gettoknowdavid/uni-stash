import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/chats/data/chats_api.dart';
import 'package:uni_stash_mobile/features/chats/models/chat_dto.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';

/// Repository interface for chat-related operations.
abstract class ChatsRepository {
  /// Create or fetch an existing chat for a listing.
  Future<Result<String>> createChat(String listingId);

  /// List the current user's chat threads.
  Future<Result<List<ChatThread>>> listThreads({int? limit});

  /// Fetch message history for a chat (newest first).
  Future<Result<ListMessageResponse>> listMessages(
    String chatId, {
    String? cursor,
    int? limit,
  });

  /// Send a message in a chat.
  Future<Result<ChatMessage>> sendMessage(String chatId, String body);

  /// A single thread's metadata (listing + counterpart identity), for
  /// deep-linked chat views.
  Future<Result<ChatThread>> getChat(String chatId);

  /// Mark all counterpart messages as read.
  Future<Result<void>> markRead(String chatId);
}

class ChatsRepositoryImpl implements ChatsRepository {
  ChatsRepositoryImpl(this._client, this._logger);

  final ChatsApiClient _client;
  final Logger _logger;

  @override
  Future<Result<String>> createChat(String listingId) async {
    try {
      final request = CreateChatRequest(listingId: listingId);
      final response = await _client.createChat(request);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data.chatId);
    } on DioException catch (e) {
      _logger.e('[ChatsRepository] createChat failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ChatsRepository] createChat unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<ListMessageResponse>> listMessages(
    String chatId, {
    String? cursor,
    int? limit,
  }) async {
    try {
      final response = await _client.listMessages(
        chatId,
        cursor: cursor,
        limit: limit,
      );
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ChatsRepository] listMessages failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ChatsRepository] listMessages unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<List<ChatThread>>> listThreads({int? limit}) async {
    try {
      final response = await _client.listChats(limit: limit);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data.chats);
    } on DioException catch (e) {
      _logger.e('[ChatsRepository] listThreads failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ChatsRepository] listThreads unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> markRead(String chatId) async {
    try {
      final response = await _client.markRead(chatId);
      if (!response.status) return Result.failure(response.message);
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.e('[ChatsRepository] markRead failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ChatsRepository] markRead unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<ChatMessage>> sendMessage(String chatId, String body) async {
    try {
      final request = SendMessageRequest(body: body);
      final response = await _client.sendMessage(chatId, request);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ChatsRepository] sendMessage failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ChatsRepository] sendMessage unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<ChatThread>> getChat(String chatId) async {
    try {
      final response = await _client.getChat(chatId);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ChatsRepository] getChat failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ChatsRepository] getChat unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
