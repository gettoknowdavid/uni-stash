import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/reviews/models/reviews_models.dart';

part 'reviews_api.g.dart';

@RestApi()
abstract class ReviewsApiClient {
  factory ReviewsApiClient(Dio dio, {String? baseUrl}) = _ReviewsApiClient;

  /// Rates the counterpart of a completed sale. One review per author
  /// per sale (409 on duplicate).
  @POST('/api/v1/reviews/{sale_id}')
  Future<ApiResponse<Review>> create(
    @Path('sale_id') String saleId,
    @Body() CreateReviewRequest request,
  );

  /// A user's rating wall + average/count summary.
  @GET('/api/v1/reviews/users/{user_id}')
  Future<ApiResponse<UserReviewsResponse>> forUser(
    @Path('user_id') String userId,
  );

  /// The caller's existing review for a sale (duplicate check), or null.
  @GET('/api/v1/reviews/sales/{sale_id}/mine')
  Future<ApiResponse<Review?>> myReviewForSale(
    @Path('sale_id') String saleId,
  );
}
