import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/core/user/models.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';

/// Abstraction over the profile data source.
///
/// The backend exposes no dedicated profile endpoints — the only
/// profile-shaped data is `GET /api/v1/auth/me` (the slim user profile:
/// id, email, display_name, email_verified, role), served by the auth API.
/// This repository exists so profile screens depend on a profile-facing
/// contract instead of the auth feature directly; when dedicated endpoints
/// land (profile update, avatar upload, my-listings), they slot in here
/// without touching consumers.
/// This deliberately stays an interface despite the single member:
/// every feature repo in the app follows the interface-based contract
/// (mockable in tests, swappable in DI), and dedicated profile
/// endpoints are expected to land here.
// ignore: one_member_abstracts
abstract interface class ProfileRepository {
  /// Fetches the signed-in user's profile (DB-fresh, not the cached
  /// session user held by AuthViewModel).
  Future<Result<User>> getProfile();
}

class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl(this._client, this._logger);

  final AuthApiClient _client;
  final Logger _logger;

  @override
  Future<Result<User>> getProfile() async {
    try {
      final response = await _client.me();
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ProfileRepository] getProfile failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ProfileRepository] getProfile unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
