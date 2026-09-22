import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

@freezed
abstract class ChatThread with _$ChatThread {
  const factory ChatThread({
    required String id,
    @JsonKey(name: 'listing_id') required String listingId,
    @JsonKey(name: 'listing_title') required String listingTitle,
    @JsonKey(name: 'counterpart_id') required String counterpartId,
    @JsonKey(name: 'counterpart_name') required String counterpartName,
    @JsonKey(name: 'unread_count') required int unreadCount,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'counterpart_photo_url') String? counterpartPhotoUrl,
    @JsonKey(name: 'last_message_preview') String? lastMessagePreview,
    @JsonKey(name: 'last_message_at') DateTime? lastMessageAt,
  }) = _ChatThread;

  factory ChatThread.fromJson(Map<String, dynamic> json) =>
      _$ChatThreadFromJson(json);
}

@freezed
abstract class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    @JsonKey(name: 'sender_id') required String senderId,
    @JsonKey(name: 'chat_id') required String chatId,
    required String body,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'read_at') DateTime? readAt,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}
