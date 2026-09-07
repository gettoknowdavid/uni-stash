import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

part 'listings_api.g.dart';

@RestApi()
abstract class ListingsApi {
  factory ListingsApi(Dio dio, {String? baseUrl}) = _ListingsApi;

  @POST('/api/v1/listings')
  Future<ApiResponse<Listing>> createListing(
    @Body() CreateListingRequest request,
  );

  @PATCH('/api/v1/listings/{id}')
  Future<ApiResponse<Listing>> updateListing(
    @Path() String id,
    @Body() UpdateListingRequest request,
  );

  @DELETE('/api/v1/listings/{id}')
  Future<ApiResponse<void>> deleteListing(@Path() String id);

  @GET('/api/v1/listings/{id}')
  Future<ApiResponse<ListListingsResponse?>> getListing(@Path() String id);

  @GET('/api/v1/listings/')
  Future<ApiResponse<ListListingsResponse>> getListings({
    @Query('q') String? q,
    @Query('category') int? category,
    @Query('min_price') double? minPrice,
    @Query('max_price') double? maxPrice,
    @Query('status') ListingStatus? status,
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });

  // @POST('/api/v1/listings/{id}/reserve')
  // Future<ApiResponse<Listing>> createListing(
  //   @Body() CreateListingRequest request,
  // );
}
