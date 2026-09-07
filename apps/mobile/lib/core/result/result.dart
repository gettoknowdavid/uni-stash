import 'package:freezed_annotation/freezed_annotation.dart';

part 'result.freezed.dart';

/// A discriminated union representing either a [Success] or a [Failure].
///
/// Use this to propagate domain-level errors without exceptions.
///
/// ```dart
/// Result<int> divide(int a, int b) {
///   if (b == 0) return const Failure('Division by zero');
///   return Success(a ~/ b);
/// }
///
/// final result = divide(10, 2);
/// switch (result) {
///   case Success(:final value):
///     print('Result: $value');
///   case Failure(:final error):
///     print('Error: $error');
/// }
/// ```
@freezed
sealed class Result<T> with _$Result<T> {
  const Result._();

  const factory Result.success(T value) = Success<T>;

  /// Creates a failure carrying a human-readable [message] and, when known, a
  /// machine-readable [code] (e.g. the backend `error.code` value such as
  /// `email_not_verified`) so callers can branch on the failure kind without
  /// string-matching the message.
  const factory Result.failure(String message, {String? code}) = Failure<T>;

  /// Returns `true` when this is a [Success].
  bool get isSuccess => this is Success<T>;

  /// Returns `true` when this is a [Failure].
  bool get isFailure => this is Failure<T>;

  /// Transforms the success value using [fn], propagating failures unchanged.
  Result<R> map<R>(R Function(T value) fn) => switch (this) {
    Success(:final value) => Result.success(fn(value)),
    Failure(:final message) => Result.failure(message),
  };

  /// Returns the success value, or throws if this is a [Failure].
  T get orThrow => switch (this) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };

  /// Returns the success value, or [defaultValue] if this is a [Failure].
  T orElse(T defaultValue) => switch (this) {
    Success(:final value) => value,
    Failure() => defaultValue,
  };

  /// The machine-readable code attached to a [Failure], or `null` for a
  /// [Success] or a failure created without a code.
  String? get failureCode => switch (this) {
    Success() => null,
    Failure(:final code) => code,
  };

  /// Unwraps the result, calling [onSuccess] or [onFailure].
  R fold<R>(
    R Function(T value) onSuccess,
    R Function(String message) onFailure,
  ) => switch (this) {
    Success(:final value) => onSuccess(value),
    Failure(:final message) => onFailure(message),
  };
}
