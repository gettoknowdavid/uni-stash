import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';

part 'categories_api.g.dart';

@RestApi()
abstract class CategoriesApiClient {
  factory CategoriesApiClient(
    Dio dio, {
    String? baseUrl,
  }) = _CategoriesApiClient;

  /// CM-4.9 — public, no auth. Returns all categories ordered by
  /// `sort_order` (then label).
  @GET('/api/v1/categories/')
  Future<ApiResponse<ListCategoriesResponse>> getCategories();
}
