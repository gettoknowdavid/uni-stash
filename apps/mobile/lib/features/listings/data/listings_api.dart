import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

part 'listings_api.g.dart';

@RestApi()
abstract class ListingsApi {
  factory ListingsApi(Dio dio, {String? baseUrl}) = _ListingsApi;
}
