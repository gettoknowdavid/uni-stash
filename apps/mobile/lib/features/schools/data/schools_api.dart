import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/schools/models/models.dart';
import 'package:uni_stash_mobile/features/schools/models/school_dto.dart';

part 'schools_api.g.dart';

@RestApi()
abstract class SchoolsApiClient {
  factory SchoolsApiClient(Dio dio, {String? baseUrl}) = _SchoolsApiClient;

  @GET('/api/v1/schools/')
  Future<ApiResponse<ListSchoolsResponse>> getList({
    @Query('q') String? q,
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });

  @GET('/api/v1/schools/{id}')
  Future<ApiResponse<School>> getSchool(@Path() String id);
}
