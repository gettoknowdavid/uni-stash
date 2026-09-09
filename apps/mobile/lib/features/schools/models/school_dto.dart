import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uni_stash_mobile/features/schools/models/models.dart';

part 'school_dto.freezed.dart';
part 'school_dto.g.dart';

@freezed
abstract class ListSchoolsQuery with _$ListSchoolsQuery {
  const factory ListSchoolsQuery({
    String? q,
    String? cursor,
    @Default(50) int limit,
  }) = _ListSchoolsQuery;

  factory ListSchoolsQuery.fromJson(Map<String, dynamic> json) =>
      _$ListSchoolsQueryFromJson(json);
}

@freezed
abstract class ListSchoolsResponse with _$ListSchoolsResponse {
  const factory ListSchoolsResponse({
    required List<School> schools,
    @JsonKey(name: 'next_cursor') String? nextCursor,
  }) = _ListSchoolsResponse;

  factory ListSchoolsResponse.fromJson(Map<String, dynamic> json) =>
      _$ListSchoolsResponseFromJson(json);
}
