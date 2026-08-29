import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';

part 'auth_api.g.dart';

@RestApi()
abstract class AuthApiClient {
  factory AuthApiClient(Dio dio, {String? baseUrl}) = _AuthApiClient;

  @POST('/api/v1/auth/signup')
  Future<ApiResponse<SignUpResponse>> signUp(@Body() SignUpRequest request);

  @POST('/api/v1/auth/login')
  Future<ApiResponse<LoginResponse>> login(@Body() LoginRequest request);

  @POST('/api/v1/auth/verify-otp')
  Future<ApiResponse<VerifyOtpResponse>> verifyOtp(
    @Body() VerifyOtpRequest request,
  );

  @POST('/api/v1/auth/resend-verification')
  Future<ApiResponse<MessageResponse>> resendVerification(
    @Body() ResendVerificationRequest request,
  );

  @POST('/api/v1/auth/forgot-password')
  Future<ApiResponse<MessageResponse>> forgotPassword(
    @Body() ForgotPasswordRequest request,
  );

  @POST('/api/v1/auth/reset-password')
  Future<ApiResponse<MessageResponse>> resetPassword(
    @Body() ResetPasswordRequest request,
  );

  @POST('/api/v1/auth/refresh')
  Future<ApiResponse<RefreshResponse>> refresh(@Body() RefreshRequest request);

  @POST('/api/v1/auth/logout')
  Future<ApiResponse<LogoutResponse>> logout(@Body() LogoutRequest request);

  @GET('/api/v1/auth/me')
  Future<ApiResponse<User>> me();
}
