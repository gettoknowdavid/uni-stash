import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

@freezed
abstract class BlockedUser with _$BlockedUser {
  const factory BlockedUser({
    @JsonKey(name: 'blocked_id') required String blockedId,
    @JsonKey(name: 'display_name') required String displayName,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'photo_url') String? photoUrl,
  }) = _BlockedUser;

  factory BlockedUser.fromJson(Map<String, dynamic> json) =>
      _$BlockedUserFromJson(json);
}

@freezed
abstract class BlockedUsersResponse with _$BlockedUsersResponse {
  const factory BlockedUsersResponse({
    @JsonKey(name: 'blocked_users')
    required List<BlockedUser> blockedUsers,
  }) = _BlockedUsersResponse;

  factory BlockedUsersResponse.fromJson(Map<String, dynamic> json) =>
      _$BlockedUsersResponseFromJson(json);
}
