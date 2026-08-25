import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';

part 'api_client.g.dart';

@RestApi()
abstract class ApiClient {
  factory ApiClient(Dio dio, {String? baseUrl}) = _ApiClient;

  @POST('/api/v1/auth/signup')
  Future<SignUpResponse> signUp(@Body() SignUpRequest request);

  @POST('/api/v1/auth/login')
  Future<LoginResponse> login(@Body() LoginRequest request);

  @POST('/api/v1/auth/verify-otp')
  Future<VerifyOtpResponse> verifyOtp(@Body() VerifyOtpRequest request);

  @POST('/api/v1/auth/resend-verification')
  Future<MessageResponse> resendVerification(
    @Body() ResendVerificationRequest request,
  );

  @POST('/api/v1/auth/forgot-password')
  Future<MessageResponse> forgotPassword(
    @Body() ForgotPasswordRequest request,
  );

  @POST('/api/v1/auth/reset-password')
  Future<MessageResponse> resetPassword(
    @Body() ResetPasswordRequest request,
  );

  @POST('/api/v1/auth/refresh')
  Future<RefreshResponse> refresh(@Body() RefreshRequest request);

  @POST('/api/v1/auth/logout')
  Future<LogoutResponse> logout(@Body() LogoutRequest request);

  @GET('/api/v1/auth/me')
  Future<UserProfile> me();
}
