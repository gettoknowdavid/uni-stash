import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/core/user/models.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';

/// Machine-readable codes returned by the backend in
/// `{ "error": { "code": ... } }` envelopes.
abstract final class AuthErrorCode {
  /// Login rejected because the account's email has not been verified.
  static const String emailNotVerified = 'email_not_verified';
}

/// Abstraction over auth data sources.
///
/// All public methods return [Result] so callers never need
/// to catch exceptions.
abstract interface class IAuthRepository {
  Future<Result<LoginResponse>> login(LoginRequest request);

  Future<Result<SignUpResponse>> signUp(SignUpRequest request);

  /// Verifies an OTP. For the `email_verify` flow the backend marks the
  /// account verified and returns fresh tokens + the updated user.
  Future<Result<VerifyOtpResponse>> verifyOtp(VerifyOtpRequest request);

  /// (Re)sends the email-verification OTP to [request]'s email address.
  Future<Result<void>> resendVerification(ResendVerificationRequest request);

  Future<Result<void>> forgotPassword(ForgotPasswordRequest request);

  Future<Result<void>> resetPassword(ResetPasswordRequest request);

  Future<Result<User>> me();
}

class AuthRepository implements IAuthRepository {
  AuthRepository(this._client, this._logger);

  final AuthApiClient _client;
  final Logger _logger;

  @override
  Future<Result<LoginResponse>> login(LoginRequest request) async {
    try {
      final response = await _client.login(request);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[AuthRepository] login failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e(
        '[AuthRepository] login unexpected error',
        error: e,
      );
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<SignUpResponse>> signUp(SignUpRequest request) async {
    try {
      final response = await _client.signUp(request);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[AuthRepository] signUp failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e(
        '[AuthRepository] signUp unexpected error',
        error: e,
      );
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<VerifyOtpResponse>> verifyOtp(VerifyOtpRequest request) async {
    try {
      final response = await _client.verifyOtp(request);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[AuthRepository] verifyOtp failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e(
        '[AuthRepository] verifyOtp unexpected error',
        error: e,
      );
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> resendVerification(
    ResendVerificationRequest request,
  ) async {
    try {
      final response = await _client.resendVerification(request);
      if (!response.status) return Result.failure(response.message);
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.e('[AuthRepository] resendVerification failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e(
        '[AuthRepository] resendVerification unexpected error',
        error: e,
      );
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> forgotPassword(ForgotPasswordRequest request) async {
    try {
      final response = await _client.forgotPassword(request);
      if (!response.status) return Result.failure(response.message);
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.e('[AuthRepository] forgotPassword failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e(
        '[AuthRepository] forgotPassword unexpected error',
        error: e,
      );
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> resetPassword(ResetPasswordRequest request) async {
    try {
      final response = await _client.resetPassword(request);
      if (!response.status) return Result.failure(response.message);
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.e('[AuthRepository] resetPassword failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e(
        '[AuthRepository] resetPassword unexpected error',
        error: e,
      );
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<User>> me() async {
    try {
      final response = await _client.me();
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[AuthRepository] me failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e(
        '[AuthRepository] me unexpected error',
        error: e,
      );
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
