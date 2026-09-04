import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';

/// Abstraction over auth data sources.
///
/// All public methods return [Result] so callers never need
/// to catch exceptions.
abstract interface class IAuthRepository {
  Future<Result<LoginResponse>> login(LoginRequest request);

  Future<Result<SignUpResponse>> signUp(SignUpRequest request);

  Future<Result<void>> forgotPassword(ForgotPasswordRequest request);

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
      return Result.failure(_humanize(e));
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
      return Result.failure(_humanize(e));
    } on Object catch (e) {
      _logger.e(
        '[AuthRepository] signUp unexpected error',
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
      return Result.failure(_humanize(e));
    } on Object catch (e) {
      _logger.e(
        '[AuthRepository] forgotPassword unexpected error',
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
      return Result.failure(_humanize(e));
    } on Object catch (e) {
      _logger.e(
        '[AuthRepository] me unexpected error',
        error: e,
      );
      return const Result.failure('An unexpected error occurred.');
    }
  }

  /// Turns a [DioException] into a human-readable message.
  String _humanize(DioException e) {
    if (e.response?.data is Map<String, dynamic>) {
      final data = e.response!.data as Map<String, dynamic>;
      final message = data['message'] as String?;
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

  String _humanizeStatus(int? status) => switch (status) {
    401 => 'Invalid email or password.',
    409 => 'An account with this email already exists.',
    422 => 'Please check your input and try again.',
    final s? => 'Server error ($s). Please try again later.',
    null => 'Unknown server error.',
  };
}
