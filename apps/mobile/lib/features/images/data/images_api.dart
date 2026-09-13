import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/images/models/images_dto.dart';

part 'images_api.g.dart';

/// Image upload pipeline (CM-6.1 / CM-6.2 / CM-6.3).
///
/// The backend never proxies image bytes: it hands out a short-lived presigned
/// PUT URL (`presign`), the client uploads the file directly to object storage
/// with that URL, then registers the upload with `confirm`.
@RestApi()
abstract class ImagesApiClient {
  factory ImagesApiClient(Dio dio, {String? baseUrl}) = _ImagesApiClient;

  @POST('/api/v1/images/presign')
  Future<ApiResponse<PresignResponse>> presign(
    @Body() PresignRequest request,
  );

  @POST('/api/v1/images/confirm')
  Future<ApiResponse<ConfirmResponse>> confirm(
    @Body() ConfirmRequest request,
  );
}
