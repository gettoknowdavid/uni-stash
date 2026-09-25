import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/blocks/models/models.dart';

part 'blocks_api.g.dart';

@RestApi()
abstract class BlocksApiClient {
  factory BlocksApiClient(Dio dio, {String baseUrl}) = _BlocksApiClient;

  /// GET /api/v1/blocks/mine
  @GET('/api/v1/blocks/mine')
  Future<ApiResponse<BlockedUsersResponse>> listBlocked();

  /// POST /api/v1/blocks/{user_id}
  @POST('/api/v1/blocks/{user_id}')
  Future<ApiResponse<void>> blockUser(@Path('user_id') String userId);

  /// DELETE /api/v1/blocks/{user_id}
  @DELETE('/api/v1/blocks/{user_id}')
  Future<void> unblockUser(@Path('user_id') String userId);
}
