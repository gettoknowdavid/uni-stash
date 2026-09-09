import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

@freezed
abstract class School with _$School {
  const factory School({
    required String id,
    required String name,
    required String slug,
    required String domain,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'logo_url') String? logoUrl,
  }) = _School;

  factory School.fromJson(Map<String, dynamic> json) => _$SchoolFromJson(json);
}
