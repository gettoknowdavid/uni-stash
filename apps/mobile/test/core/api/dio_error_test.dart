import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';

DioException makeDioException({
  DioExceptionType type = DioExceptionType.badResponse,
  int? statusCode,
  Map<String, dynamic>? responseData,
}) {
  return DioException(
    type: type,
    requestOptions: RequestOptions(path: '/api/v1/test'),
    response: (responseData != null || statusCode != null)
        ? Response(
            data: responseData,
            statusCode: statusCode,
            requestOptions: RequestOptions(path: '/api/v1/test'),
          )
        : null,
  );
}

void main() {
  group('dioFailure', () {
    group('timeout errors', () {
      test('returns timeout message for connectionTimeout', () {
        final result = dioFailure<Object?>(
          makeDioException(type: DioExceptionType.connectionTimeout),
        );
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, contains('timed out'));
        }
      });

      test('returns timeout message for sendTimeout', () {
        final result = dioFailure<Object?>(
          makeDioException(type: DioExceptionType.sendTimeout),
        );
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, contains('timed out'));
        }
      });

      test('returns timeout message for receiveTimeout', () {
        final result = dioFailure<Object?>(
          makeDioException(type: DioExceptionType.receiveTimeout),
        );
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, contains('timed out'));
        }
      });
    });

    group('connection errors', () {
      test('returns no internet for connectionError', () {
        final result = dioFailure<Object?>(
          makeDioException(type: DioExceptionType.connectionError),
        );
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, contains('internet connection'));
        }
      });
    });

    group('HTTP status codes', () {
      test('returns invalid credentials for 401', () {
        final result = dioFailure<Object?>(makeDioException(statusCode: 401));
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, contains('Invalid email or password'));
        }
      });

      test('returns not verified for 403', () {
        final result = dioFailure<Object?>(makeDioException(statusCode: 403));
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, contains('not verified'));
        }
      });

      test('returns not found for 404', () {
        final result = dioFailure<Object?>(makeDioException(statusCode: 404));
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, contains('not found'));
        }
      });

      test('returns already exists for 409', () {
        final result = dioFailure<Object?>(makeDioException(statusCode: 409));
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, contains('already exists'));
        }
      });

      test('returns check input for 422', () {
        final result = dioFailure<Object?>(makeDioException(statusCode: 422));
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, contains('check your input'));
        }
      });

      test('returns server error for 500', () {
        final result = dioFailure<Object?>(makeDioException(statusCode: 500));
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, contains('Server error'));
        }
      });
    });

    group('response body message extraction', () {
      test('extracts top-level message', () {
        final result = dioFailure<Object?>(
          makeDioException(
            statusCode: 500,
            responseData: {'message': 'Custom error'},
          ),
        );
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, 'Custom error');
        }
      });

      test('extracts nested error.message', () {
        final result = dioFailure<Object?>(
          makeDioException(
            statusCode: 403,
            responseData: {
              'error': {'message': 'Email not verified'},
            },
          ),
        );
        expect(result.isFailure, isTrue);
        if (result case Failure(:final message)) {
          expect(message, 'Email not verified');
        }
      });
    });

    group('error code extraction', () {
      test('extracts error.code from nested envelope', () {
        final result = dioFailure<Object?>(
          makeDioException(
            statusCode: 403,
            responseData: {
              'error': {
                'code': 'email_not_verified',
                'message': 'not verified',
              },
            },
          ),
        );
        expect(result.failureCode, 'email_not_verified');
      });

      test('returns null code when no error envelope', () {
        final result = dioFailure<Object?>(
          makeDioException(statusCode: 500),
        );
        expect(result.failureCode, isNull);
      });
    });
  });
}
