import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uni_stash_mobile/core/user/models.dart';

part 'auth_dto.freezed.dart';
part 'auth_dto.g.dart';

@freezed
abstract class ForgotPasswordRequest with _$ForgotPasswordRequest {
  const factory ForgotPasswordRequest({
    required String email,
  }) = _ForgotPasswordRequest;

  factory ForgotPasswordRequest.fromJson(Map<String, dynamic> json) =>
      _$ForgotPasswordRequestFromJson(json);
}

@freezed
abstract class LoginRequest with _$LoginRequest {
  const factory LoginRequest({
    required String email,
    required String password,
  }) = _LoginRequest;

  factory LoginRequest.fromJson(Map<String, dynamic> json) =>
      _$LoginRequestFromJson(json);
}

@freezed
abstract class LoginResponse with _$LoginResponse {
  const factory LoginResponse({
    @JsonKey(name: 'access_token') required String accessToken,
    @JsonKey(name: 'refresh_token') required String refreshToken,
    @JsonKey(name: 'expires_in') required int expiresIn,
    required User user,
  }) = _LoginResponse;

  factory LoginResponse.fromJson(Map<String, dynamic> json) =>
      _$LoginResponseFromJson(json);
}

@freezed
abstract class LogoutRequest with _$LogoutRequest {
  const factory LogoutRequest({
    @JsonKey(name: 'refresh_token') required String refreshToken,
  }) = _LogoutRequest;

  factory LogoutRequest.fromJson(Map<String, dynamic> json) =>
      _$LogoutRequestFromJson(json);
}

@freezed
abstract class LogoutResponse with _$LogoutResponse {
  const factory LogoutResponse({
    required String status,
  }) = _LogoutResponse;

  factory LogoutResponse.fromJson(Map<String, dynamic> json) =>
      _$LogoutResponseFromJson(json);
}

@freezed
abstract class MessageResponse with _$MessageResponse {
  const factory MessageResponse({
    required String message,
  }) = _MessageResponse;

  factory MessageResponse.fromJson(Map<String, dynamic> json) =>
      _$MessageResponseFromJson(json);
}

@freezed
abstract class DeleteAccountRequest with _$DeleteAccountRequest {
  const factory DeleteAccountRequest({
    required String password,
  }) = _DeleteAccountRequest;

  factory DeleteAccountRequest.fromJson(Map<String, dynamic> json) =>
      _$DeleteAccountRequestFromJson(json);
}

@freezed
abstract class DeleteAccountResponse with _$DeleteAccountResponse {
  const factory DeleteAccountResponse({
    required String message,
    @JsonKey(name: 'deletion_scheduled_at') required String deletionScheduledAt,
  }) = _DeleteAccountResponse;

  factory DeleteAccountResponse.fromJson(Map<String, dynamic> json) =>
      _$DeleteAccountResponseFromJson(json);
}

@freezed
abstract class ProfileStatsResponse with _$ProfileStatsResponse {
  const factory ProfileStatsResponse({
    @JsonKey(name: 'active_listings') required int activeListings,
    @JsonKey(name: 'items_sold') required int itemsSold,
    required int saved,
  }) = _ProfileStatsResponse;

  factory ProfileStatsResponse.fromJson(Map<String, dynamic> json) =>
      _$ProfileStatsResponseFromJson(json);
}

@freezed
abstract class RefreshRequest with _$RefreshRequest {
  const factory RefreshRequest({
    @JsonKey(name: 'refresh_token') required String refreshToken,
  }) = _RefreshRequest;

  factory RefreshRequest.fromJson(Map<String, dynamic> json) =>
      _$RefreshRequestFromJson(json);
}

@freezed
abstract class RefreshResponse with _$RefreshResponse {
  const factory RefreshResponse({
    @JsonKey(name: 'access_token') required String accessToken,
    @JsonKey(name: 'refresh_token') required String refreshToken,
    @JsonKey(name: 'expires_in') required int expiresIn,
    required User user,
  }) = _RefreshResponse;

  factory RefreshResponse.fromJson(Map<String, dynamic> json) =>
      _$RefreshResponseFromJson(json);
}

@freezed
abstract class ResendVerificationRequest with _$ResendVerificationRequest {
  const factory ResendVerificationRequest({
    required String email,
  }) = _ResendVerificationRequest;

  factory ResendVerificationRequest.fromJson(Map<String, dynamic> json) =>
      _$ResendVerificationRequestFromJson(json);
}

@freezed
abstract class ResetPasswordRequest with _$ResetPasswordRequest {
  const factory ResetPasswordRequest({
    required String code,
    @JsonKey(name: 'new_password') required String newPassword,
  }) = _ResetPasswordRequest;

  factory ResetPasswordRequest.fromJson(Map<String, dynamic> json) =>
      _$ResetPasswordRequestFromJson(json);
}

@freezed
abstract class SignUpRequest with _$SignUpRequest {
  const factory SignUpRequest({
    required String email,
    required String password,
    @JsonKey(name: 'display_name') required String displayName,
  }) = _SignUpRequest;

  factory SignUpRequest.fromJson(Map<String, dynamic> json) =>
      _$SignUpRequestFromJson(json);
}

@freezed
abstract class SignUpResponse with _$SignUpResponse {
  const factory SignUpResponse({
    required User user,
    @JsonKey(name: 'access_token') String? accessToken,
    @JsonKey(name: 'refresh_token') String? refreshToken,
    @JsonKey(name: 'expires_in') int? expiresIn,
  }) = _SignUpResponse;

  factory SignUpResponse.fromJson(Map<String, dynamic> json) =>
      _$SignUpResponseFromJson(json);
}

@freezed
abstract class UpdateProfileRequest with _$UpdateProfileRequest {
  const factory UpdateProfileRequest({
    @JsonKey(name: 'display_name') String? displayName,
  }) = _UpdateProfileRequest;

  factory UpdateProfileRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateProfileRequestFromJson(json);
}

@freezed
abstract class VerifyOtpRequest with _$VerifyOtpRequest {
  const factory VerifyOtpRequest({
    required String code,
    @JsonKey(name: 'otp_type') required String otpType,
  }) = _VerifyOtpRequest;

  factory VerifyOtpRequest.fromJson(Map<String, dynamic> json) =>
      _$VerifyOtpRequestFromJson(json);
}

@freezed
abstract class VerifyOtpResponse with _$VerifyOtpResponse {
  const factory VerifyOtpResponse({
    required bool verified,
    @JsonKey(name: 'access_token') String? accessToken,
    @JsonKey(name: 'refresh_token') String? refreshToken,
    @JsonKey(name: 'expires_in') int? expiresIn,
    User? user,
  }) = _VerifyOtpResponse;

  factory VerifyOtpResponse.fromJson(Map<String, dynamic> json) =>
      _$VerifyOtpResponseFromJson(json);
}

enum UserRole { admin, student }
