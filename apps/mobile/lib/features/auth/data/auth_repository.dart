import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';

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
      return _dioFailure(e);
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
      return _dioFailure(e);
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
      return _dioFailure(e);
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
      return _dioFailure(e);
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
      return _dioFailure(e);
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
      return _dioFailure(e);
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
      return _dioFailure(e);
    } on Object catch (e) {
      _logger.e(
        '[AuthRepository] me unexpected error',
        error: e,
      );
      return const Result.failure('An unexpected error occurred.');
    }
  }

  /// Builds a failure for a [DioException], extracting the backend's
  /// machine-readable `error.code` (when present) alongside the message.
  Result<T> _dioFailure<T>(DioException e) =>
      Result.failure(_humanize(e), code: _errorCode(e));

  /// Turns a [DioException] into a human-readable message.
  String _humanize(DioException e) {
    if (e.response?.data is Map<String, dynamic>) {
      final data = e.response!.data as Map<String, dynamic>;
      final error = data['error'];
      final message = error is Map<String, dynamic>
          ? error['message'] as String?
          : data['message'] as String?;
      if (message != null && message.isNotEmpty) return message;
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'Connection timed out. Please check your network.',
      DioExceptionType.connectionError => 'No internet connection.',
      DioExceptionType.badResponse => _humanizeStatus(
        e.response?.statusCode,
      ),
      _ => 'Network error. Please check your connection.',
    };
  }

  /// Extracts the machine-readable error code from the backend's
  /// `{ "error": { "code": "..." } }` envelope, or `null` when absent.
  String? _errorCode(DioException e) {
    final data = e.response?.data;
    if (data is! Map<String, dynamic>) return null;
    final error = data['error'];
    if (error is Map<String, dynamic>) {
      final code = error['code'];
      if (code is String && code.isNotEmpty) return code;
    }
    return null;
  }

  String _humanizeStatus(int? status) => switch (status) {
    401 => 'Invalid email or password.',
    403 => 'Your email address is not verified yet.',
    409 => 'An account with this email already exists.',
    422 => 'Please check your input and try again.',
    final s? => 'Server error ($s). Please try again later.',
    null => 'Unknown server error.',
  };
}
