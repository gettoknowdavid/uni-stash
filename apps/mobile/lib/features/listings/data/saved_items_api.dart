import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/listings/data/saved_items_dto.dart';

part 'saved_items_api.g.dart';

@RestApi()
abstract class SavedItemsApiClient {
  factory SavedItemsApiClient(
    Dio dio, {
    String? baseUrl,
  }) = _SavedItemsApiClient;

  /// The signed-in user's saved listings, newest
  /// first, cursor-paginated.
  @GET('/api/v1/saved-items')
  Future<ApiResponse<SavedItemsListResponse>> list({
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });

  /// Saves a listing (idempotent).
  @POST('/api/v1/saved-items/{id}')
  Future<ApiResponse<void>> save(@Path() String id);

  /// Unsaves a listing (idempotent).
  @DELETE('/api/v1/saved-items/{id}')
  Future<HttpResponse<void>> unsave(@Path() String id);

  /// Whether the signed-in user saved a listing.
  @GET('/api/v1/saved-items/{id}/status')
  Future<ApiResponse<SavedItemStatusResponse>> status(@Path() String id);
}
