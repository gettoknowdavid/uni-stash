import 'package:freezed_annotation/freezed_annotation.dart';

part 'public_profile.freezed.dart';
part 'public_profile.g.dart';

/// Public profile of another user (`GET /api/v1/users/{id}`) — only fields
/// safe to show to other students.
@freezed
abstract class PublicProfile with _$PublicProfile {
  const factory PublicProfile({
    required String id,
    @JsonKey(name: 'display_name') required String displayName,
    required String domain,
    required DateTime joinedAt,
    @JsonKey(name: 'photo_url') String? photoUrl,
    @JsonKey(name: 'average_rating') double? averageRating,
    @JsonKey(name: 'review_count') @Default(0) int reviewCount,
    @JsonKey(name: 'active_listings') @Default(0) int activeListings,
  }) = _PublicProfile;

  factory PublicProfile.fromJson(Map<String, dynamic> json) =>
      _$PublicProfileFromJson(json);
}
