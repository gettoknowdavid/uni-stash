import 'package:dio/dio.dart';
import 'package:uni_stash_mobile/core/result/result.dart';

/// Builds a [Result.failure] from a [DioException], extracting the backend's
/// machine-readable `error.code` (when present) alongside a human-readable
/// message.
Result<T> dioFailure<T>(DioException e) {
  return Result.failure(_humanize(e), code: _errorCode(e));
}

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
  404 => 'The requested resource was not found.',
  409 => 'An account with this email already exists.',
  422 => 'Please check your input and try again.',
  final s? => 'Server error ($s). Please try again later.',
  null => 'Unknown server error.',
};
