import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';

part 'chat_dto.freezed.dart';
part 'chat_dto.g.dart';

@freezed
abstract class CreateChatRequest with _$CreateChatRequest {
  const factory CreateChatRequest({
    @JsonKey(name: 'listing_id') required String listingId,
  }) = _CreateChatRequest;

  factory CreateChatRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateChatRequestFromJson(json);
}

@freezed
abstract class SendMessageRequest with _$SendMessageRequest {
  const factory SendMessageRequest({
    required String body,
  }) = _SendMessageRequest;

  factory SendMessageRequest.fromJson(Map<String, dynamic> json) =>
      _$SendMessageRequestFromJson(json);
}

@freezed
abstract class ChatCreatedResponse with _$ChatCreatedResponse {
  const factory ChatCreatedResponse({
    @JsonKey(name: 'chat_id') required String chatId,
  }) = _ChatCreatedResponse;

  factory ChatCreatedResponse.fromJson(Map<String, dynamic> json) =>
      _$ChatCreatedResponseFromJson(json);
}

@freezed
abstract class ListChatResponse with _$ListChatResponse {
  const factory ListChatResponse({
    required List<ChatThread> chats,
  }) = _ListChatResponse;

  factory ListChatResponse.fromJson(Map<String, dynamic> json) =>
      _$ListChatResponseFromJson(json);
}

@freezed
abstract class ListMessageResponse with _$ListMessageResponse {
  const factory ListMessageResponse({
    required List<ChatMessage> messages,
    @JsonKey(name: 'next_cursor') String? nextCursor,
  }) = _ListMessageResponse;

  factory ListMessageResponse.fromJson(Map<String, dynamic> json) =>
      _$ListMessageResponseFromJson(json);
}

@freezed
abstract class MessagesQuery with _$MessagesQuery {
  const factory MessagesQuery({
    String? cursor,
    @Default(50) int limit,
  }) = _MessagesQuery;

  factory MessagesQuery.fromJson(Map<String, dynamic> json) =>
      _$MessagesQueryFromJson(json);
}
