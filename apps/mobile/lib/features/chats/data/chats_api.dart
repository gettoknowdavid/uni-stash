import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/chats/models/chat_dto.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';

part 'chats_api.g.dart';

@RestApi()
abstract class ChatsApiClient {
  factory ChatsApiClient(Dio dio, {String? baseUrl}) = _ChatsApiClient;

  // Create or fetch existing chat thread for a listing.
  // Idempotent: calling twice for the same listing+buyer returns the same chat_id.
  @POST('/api/v1/chats')
  Future<ApiResponse<ChatCreatedResponse>> createChat(
    @Body() CreateChatRequest request,
  );

  // List the current user's chat threads (with unread counts).
  @GET('/api/v1/chats')
  Future<ApiResponse<ListChatResponse>> listChats({
    @Query('limit') int? limit,
  });

  // Cursor-paginated message history for a chat.
  // Returns newest-first; client reverses for display.
  @GET('/api/v1/chats/{id}/messages')
  Future<ApiResponse<ListMessageResponse>> listMessages(
    @Path() String id, {
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });

  // Send a message (REST fallback; realtime is the primary path).
  @POST('/api/v1/chats/{id}/messages')
  Future<ApiResponse<ChatMessage>> sendMessage(
    @Path() String id,
    @Body() SendMessageRequest request,
  );

  // Mark all counterpart messages as read.
  @POST('/api/v1/chats/{id}/read')
  Future<ApiResponse<void>> markRead(@Path() String id);
}
