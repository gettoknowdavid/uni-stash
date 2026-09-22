import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/sales/models/sales_dto.dart';

part 'sales_api.g.dart';

@RestApi()
abstract class SalesApiClient {
  factory SalesApiClient(Dio dio, {String? baseUrl}) = _SalesApiClient;

  @GET('/api/v1/sales/purchases')
  Future<ApiResponse<SalesListResponse>> myPurchases({
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });

  @GET('/api/v1/sales/mine')
  Future<ApiResponse<SalesListResponse>> mySales({
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });
}
