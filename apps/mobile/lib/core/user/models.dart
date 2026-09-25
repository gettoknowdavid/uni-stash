import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

@freezed
abstract class User with _$User {
  const factory User({
    required String id,
    required String email,
    @JsonKey(name: 'display_name') required String displayName,
    @JsonKey(name: 'email_verified') required bool emailVerified,
    required String role,
    @JsonKey(name: 'email_notifications_enabled')
    @Default(false)
    bool emailNotificationsEnabled,
    @JsonKey(name: 'profile_visibility')
    @Default('public')
    String profileVisibility,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
