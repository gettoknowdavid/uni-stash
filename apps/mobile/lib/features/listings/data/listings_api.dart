import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

part 'listings_api.g.dart';

@RestApi()
abstract class ListingsApiClient {
  factory ListingsApiClient(Dio dio, {String? baseUrl}) = _ListingsApiClient;

  @POST('/api/v1/listings')
  Future<ApiResponse<Listing>> create(@Body() CreateListingRequest request);

  @PATCH('/api/v1/listings/{id}')
  Future<ApiResponse<Listing>> update(
    @Path() String id,
    @Body() UpdateListingRequest request,
  );

  @DELETE('/api/v1/listings/{id}')
  Future<ApiResponse<void>> delete(@Path() String id);

  @GET('/api/v1/listings/{id}')
  Future<ApiResponse<ListingDetailResponse?>> getListing(@Path() String id);

  @GET('/api/v1/listings')
  Future<ApiResponse<ListListingsResponse>> getList({
    @Query('q') String? q,
    @Query('category_id') int? categoryId,
    @Query('min_price') int? minPrice,
    @Query('max_price') int? maxPrice,
    @Query('status') ListingStatus? status,
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });

  @POST('/api/v1/listings/{id}/reserve')
  Future<ApiResponse<Listing>> reserve(@Path() String id);

  @POST('/api/v1/listings/{id}/unreserve')
  Future<ApiResponse<Listing>> unreserve(@Path() String id);

  @POST('/api/v1/listings/{id}/mark-sold')
  Future<ApiResponse<Listing>> markSold(@Path() String id);
}
