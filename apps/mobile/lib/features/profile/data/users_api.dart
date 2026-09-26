import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/profile/models/public_profile.dart';

part 'users_api.g.dart';

@RestApi()
abstract class UsersApiClient {
  factory UsersApiClient(Dio dio, {String baseUrl}) = _UsersApiClient;

  /// GET /api/v1/users/{user_id} — public profile + rating + stats.
  @GET('/api/v1/users/{user_id}')
  Future<ApiResponse<PublicProfile>> getProfile(
    @Path('user_id') String userId,
  );

  /// GET /api/v1/users/{user_id}/listings — the user's public listings.
  @GET('/api/v1/users/{user_id}/listings')
  Future<ApiResponse<ListListingsResponse>> getUserListings(
    @Path('user_id') String userId, {
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });
}

/// Re-export so the generated file's return types resolve.
typedef ListingSummaryAlias = ListingSummary;
